// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloClient
import SmdKit
import SmdSidecar

// MARK: - Drafts

/// Drafts from Wikidata: an item read as the containers it would be, its facts Wikidata's and its
/// outline and artwork TMDb's, read through the TMDb ids Wikidata holds and attributed, shaped by the
/// operator before anything is made, and made through the silo's create route, which takes containers
/// as documents whoever wrote them. An item smddb holds is imported from smddb instead, and one the
/// library holds is not drafted. `Proposals/Wikidata.md`.
extension AdminConsole {
    /// Whether the console can ask TMDb, and why not when it cannot: no token, or one TMDb refuses.
    public nonisolated static func tmdbStanding(
        token: String?,
        source: @Sendable (String) -> any TMDbSource
    ) async -> TMDb.Unavailable? {
        guard let token, !token.isEmpty else { return .noToken }
        do {
            try await source(token).authenticate()
            return nil
        } catch let unavailable as TMDb.Unavailable {
            return unavailable
        } catch {
            return .answered(0)
        }
    }

    /// How to read a series: which of its seasons, by Wikidata's id for each, all of them when nil.
    public struct DraftShape: Hashable, Sendable {
        public var seasons: Set<String>?

        public init(seasons: Set<String>? = nil) {
            self.seasons = seasons
        }
    }

    /// What picking an item to walk comes to: smddb's container to import instead, the library's
    /// container that carries the item's reference already, or a walk rooted at a draft of it.
    public enum ReviewWalkStart: Hashable, Sendable {
        case importFromSmddb(Container)
        case held(SiloClient.ContainerSummary)
        case walk(ReviewWalk)
    }

    /// Starts a walk of an item the library does not hold, rooted at a draft of it: smddb's container to
    /// import is said first, then the library's container that carries the item's reference, and
    /// otherwise the item is read as containers, the walk's draft. With no TMDb, the draft holds no
    /// outline and offers no artwork. Nothing is kept: the console keeps the walk as it keeps any walk.
    // swiftlint:disable:next function_parameter_count
    public func startWalk(
        drafting item: Wikidata.Item,
        shape: DraftShape = DraftShape(),
        into library: String,
        of silo: Silo,
        from database: any ContainerDatabase,
        wikidata: any WikidataSource,
        tmdb: (any TMDbSource)?
    ) async throws -> ReviewWalkStart {
        let type = item.kind.containerType
        if let known = try await database.containers().first(where: {
            $0.type == type && $0.externalRefs.contains(item.ref)
        }) {
            return .importFromSmddb(known)
        }
        if let held = try await carrying(item, in: library, of: silo) { return .held(held) }

        var reader = Reader(wikidata: wikidata, tmdb: tmdb, database: database)
        let top: Container
        var creating = ContainerDraft.Creating()
        switch item.kind {
        case .film:
            let film = try await wikidata.film(item.id)
            top = try await reader.film(film)
            for collection in film.partOf {
                if let holder = try await carrying(Wikidata.Item(.collection, collection), in: library, of: silo) {
                    creating = ContainerDraft.Creating(parent: holder.id)
                    break
                }
            }
        case .collection:
            top = try await reader.collection(try await wikidata.collection(item.id))
        case .series:
            top = try await reader.series(try await wikidata.series(item.id), shape: shape)
        case .season, .serial, .episode:
            throw NoReading(reason: "a \(item.kind) is drafted beneath the series that holds it")
        }
        return .walk(ReviewWalk(drafting: reader.tree(top: top, item: item, library: library, creating: creating)))
    }

    /// A draft of a child a walk's stop lacks, a series' season or a season's serial, filed where it is
    /// said to be, kept nowhere: what a walk makes a missing child into. A season's content is read
    /// through the TMDb series given.
    // swiftlint:disable:next function_parameter_count
    public func draft(
        of child: Wikidata.Summary,
        at creating: ContainerDraft.Creating,
        into library: String,
        from database: any ContainerDatabase,
        wikidata: any WikidataSource,
        tmdb: (any TMDbSource)?,
        tmdbSeries: String? = nil
    ) async throws -> DraftTree {
        var reader = Reader(wikidata: wikidata, tmdb: tmdb, database: database)
        let top: Container
        switch child.kind {
        case .season:
            if let tmdb { reader.tmdbSeasons = try? await Self.tmdbSeasons(of: tmdbSeries, from: tmdb) }
            top = try await reader.season(try await wikidata.season(child.id))
        case .serial:
            top = try await reader.serial(try await wikidata.serial(child.id))
        default:
            throw NoReading(reason: "a \(child.kind) is drafted only as an entry of what holds it")
        }
        return reader.tree(top: top, item: Wikidata.Item(child.kind, child.id), library: library, creating: creating)
    }

    /// The library's container that carries an item's reference, of the item's kind, if any.
    private func carrying(
        _ item: Wikidata.Item,
        in library: String,
        of silo: Silo
    ) async throws -> SiloClient.ContainerSummary? {
        try await withOperator(silo) { try await $0.lookup(provider: "wikidata", value: item.id) }
            .first { $0.library == library && $0.type == item.kind.containerType.rawValue }
    }

    /// Reads Wikidata's items as containers, each with an id from smddb's client, its content read from
    /// TMDb through the TMDb id its item holds, gathering what the tree keeps beside them.
    struct Reader {
        let wikidata: any WikidataSource
        let tmdb: (any TMDbSource)?
        let database: any ContainerDatabase
        var attributions: [ContainerID: [Attribution]] = [:]
        var containers: [Container] = []
        var episodeTitles: [String: String] = [:]
        var airDates: [String: CalendarDate] = [:]
        var specials: [Special] = []
        /// The images TMDb holds for each container read whose item carries a TMDb id.
        var images: [ContainerID: DraftTree.RecordImages] = [:]
        /// The TMDb series the seasons read are TMDb's seasons of.
        var tmdbSeasons: TMDbSeasons?

        init(wikidata: any WikidataSource, tmdb: (any TMDbSource)?, database: any ContainerDatabase) {
            self.wikidata = wikidata
            self.tmdb = tmdb
            self.database = database
        }

        func tree(top: Container, item: Wikidata.Item, library: String, creating: ContainerDraft.Creating) -> DraftTree
        {
            DraftTree(
                library: library,
                item: item,
                creating: creating,
                containers: containers,
                top: top.id,
                attributions: attributions,
                episodeTitles: episodeTitles,
                airDates: airDates,
                specials: specials,
                images: images
            )
        }

        /// A container from an item's facts, its outline TMDb's overview, attributed, and its images
        /// TMDb's. Content is offered, not needed: a draft is read without it when TMDb will not say.
        private mutating func make(_ type: ContainerType, _ work: Wikidata.Work) async throws -> Container {
            let content: Content? =
                if let tmdb {
                    try? await AdminConsole.content(
                        of: type,
                        tmdb: work.ref(.tmdb)?.value,
                        seasons: tmdbSeasons,
                        from: tmdb
                    )
                } else { nil }
            let overview = content?.overview.flatMap { $0.isEmpty ? nil : $0 }
            var container = Container(
                id: try await database.provisionalID(),
                type: type,
                title: Title(work.title) ?? Title("Untitled")!,
                year: type.hasYear ? work.year : nil,
                yearInTitle: type == .movie || type == .series,
                outline: overview,
                externalRefs: Special(episode: work).refs
            )
            container.sequences = []
            if let content {
                if overview != nil {
                    attributions[container.id] = [
                        Attribution(subject: .outline, provider: .tmdb, value: String(content.record.id), read: .today)
                    ]
                }
                images[container.id] = DraftTree.RecordImages(content.record, content.images)
            }
            return container
        }

        mutating func film(_ film: Wikidata.Work) async throws -> Container {
            var container = try await make(.movie, film)
            container.sequences = [
                Sequence(id: "main", items: [.leaf(Entry.Leaf(id: ItemID("feature")!, type: .movie))])
            ]
            containers.append(container)
            return container
        }

        mutating func collection(_ collection: Wikidata.Collection) async throws -> Container {
            var container = try await make(.collection, collection.work)
            containers.append(container)
            var items: [Entry] = []
            for work in collection.films {
                let film = try await self.film(work)
                items.append(.child(Entry.Child(id: Self.itemID(film.title.rawValue, in: items), container: film.id)))
            }
            container.sequences = [Sequence(id: "movies", items: items)]
            replace(container)
            return container
        }

        mutating func series(_ series: Wikidata.Series, shape: DraftShape) async throws -> Container {
            if let tmdb {
                tmdbSeasons = try? await AdminConsole.tmdbSeasons(of: series.work.ref(.tmdb)?.value, from: tmdb)
            }
            var container = try await make(.series, series.work)
            containers.append(container)
            let wanted = series.seasons.filter { shape.seasons?.contains($0.id) ?? true }
            let read = try await AdminConsole.concurrently(wanted) { [wikidata] summary in
                try await wikidata.season(summary.id)
            }
            var items: [Entry] = []
            for record in read {
                let season = try await self.season(record)
                items.append(
                    .child(Entry.Child(id: Self.itemID(season.title.rawValue, in: items), container: season.id))
                )
            }
            container.sequences = [Sequence(id: "seasons", items: items)]
            replace(container)
            for episode in series.specials { note(episode) }
            specials = series.specials.map { Special(episode: $0) }
            return container
        }

        /// A season, holding its episodes as entries and its serials as containers beneath it, in
        /// Wikidata's order.
        mutating func season(_ season: Wikidata.Season) async throws -> Container {
            var container = try await make(.season, season.work)
            containers.append(container)
            var items: [Entry] = []
            for member in season.members {
                switch member {
                case .episode(let episode):
                    items.append(entry(episode, in: items))
                case .serial(let serial):
                    let made = try await self.serial(serial)
                    items.append(
                        .child(Entry.Child(id: Self.itemID(made.title.rawValue, in: items), container: made.id))
                    )
                }
            }
            let serials = season.members.allSatisfy { if case .serial = $0 { true } else { false } }
            container.sequences = [Sequence(id: serials && !items.isEmpty ? "serials" : "episodes", items: items)]
            replace(container)
            return container
        }

        /// A serial, holding its parts as entries in Wikidata's order.
        mutating func serial(_ serial: Wikidata.Serial) async throws -> Container {
            var container = try await make(.serial, serial.work)
            var items: [Entry] = []
            for part in serial.parts { items.append(entry(part, in: items)) }
            container.sequences = [Sequence(id: "parts", items: items)]
            containers.append(container)
            return container
        }

        /// An episode as an entry, carrying its references and no title, since Wikidata has one for it.
        private mutating func entry(_ episode: Wikidata.Work, in entries: [Entry]) -> Entry {
            note(episode)
            return .leaf(
                Entry.Leaf(
                    id: Self.itemID(episode.title, in: entries),
                    type: .episode,
                    externalRefs: Special(episode: episode).refs
                )
            )
        }

        private mutating func note(_ episode: Wikidata.Work) {
            episodeTitles[episode.id] = episode.title
            if let premiered = episode.premiered { airDates[episode.id] = premiered }
        }

        private mutating func replace(_ container: Container) {
            if let index = containers.firstIndex(where: { $0.id == container.id }) { containers[index] = container }
        }

        static func itemID(_ title: String, in entries: [Entry]) -> ItemID {
            ItemID(Slug.unique(from: title, avoiding: Set(entries.compactMap { $0.id?.value })))!
        }
    }

    // MARK: Specials

    /// A placement the console thinks most likely for a special, and why; nil placement when the reason
    /// is advice rather than a place.
    public struct SpecialSuggestion: Hashable, Sendable, Codable {
        /// What a suggestion rests on, strongest first.
        public enum Basis: Int, Hashable, Sendable, Comparable, Codable {
            case smddb
            case breakout
            case duplicate
            case alternative
            case aired
            case title

            public static func < (lhs: Basis, rhs: Basis) -> Bool { lhs.rawValue < rhs.rawValue }
        }

        public var placement: SpecialPlacement?
        public var reason: String
        public var basis: Basis

        public init(placement: SpecialPlacement?, reason: String, basis: Basis = .title) {
            self.placement = placement
            self.reason = reason
            self.basis = basis
        }
    }

    /// The suggestions for the specials of a walk's drafted series, as a draft's are suggested. A walk
    /// rooted at no drafted series is as it was.
    public func suggest(
        in walk: ReviewWalk,
        of silo: Silo,
        from database: any ContainerDatabase,
        progress: @Sendable (StepProgress) async -> Void = { _ in }
    ) async throws -> ReviewWalk {
        guard walk.drafting, walk.series == walk.root, var tree = walk.drafts[walk.root] else { return walk }
        tree.specials = walk.specials
        tree.placements = walk.placements
        var walk = walk
        walk.suggestions = try await suggest(for: tree, of: silo, from: database, progress: progress)
        return walk
    }

    /// A suggestion for each unassigned special that has one, strongest first: where smddb files its
    /// reference; the breakout the specials either side of it are in; a duplicate of the item a library
    /// holds that carries one of the other ids Wikidata holds for it; another way to play a container its
    /// title names; where it aired among the tree's episodes; and, for a special whose title says what
    /// it is, an extra of that type, or declined for a trailer. Nothing is kept.
    public func suggest(
        for tree: DraftTree,
        of silo: Silo,
        from database: any ContainerDatabase,
        progress: @Sendable (StepProgress) async -> Void = { _ in }
    ) async throws -> [String: SpecialSuggestion] {
        let clone = try await database.containers()
        let unplaced = tree.specials.indices.filter { tree.placements[tree.specials[$0].id] == nil }
        let step = "Suggesting where the specials go"
        await progress(StepProgress(step, of: unplaced.count))
        // Each special is read on its own, against the tree as it came: none's suggestion rests on another's.
        let read = try await Self.concurrently(
            unplaced,
            done: { await progress(StepProgress(step, done: $0, of: unplaced.count)) }
        ) { [tree] index in
            try await self.suggestion(for: tree.specials[index], at: index, in: tree, clone: clone, of: silo)
        }
        var suggestions: [String: SpecialSuggestion] = [:]
        for (index, suggestion) in zip(unplaced, read) { suggestions[tree.specials[index].id] = suggestion }
        return suggestions
    }

    /// The strongest suggestion for one special.
    private func suggestion(
        for special: Special,
        at index: Int,
        in tree: DraftTree,
        clone: [Container],
        of silo: Silo
    ) async throws -> SpecialSuggestion? {
        if let found = smddbFiling(of: special, in: clone, tree: tree) { return found }
        if let beside = breakoutBeside(index, in: tree) { return beside }
        if let duplicate = try await duplicate(of: special, in: tree, of: silo) { return duplicate }
        if let alternative = Self.alternative(of: special, in: tree.containers, titles: tree.episodeTitles) {
            return alternative
        }
        if let aired = airedPosition(of: special, in: tree) { return aired }
        return Self.byItsTitle(special, in: tree)
    }

    /// Where smddb's record of the series files the special's reference: in the container of the tree
    /// that carries a reference smddb's filing container does, since the tree's ids are new ones.
    private nonisolated func smddbFiling(
        of special: Special,
        in clone: [Container],
        tree: DraftTree
    ) -> SpecialSuggestion? {
        let drafted = tree.containers
        let refs = special.refs
        for container in clone {
            guard
                let mine = drafted.first(where: { drafted in
                    drafted.externalRefs.contains { container.externalRefs.contains($0) }
                })
            else { continue }
            if container.sequences.flatMap(\.items).contains(where: { $0.externalRefs.contains(where: refs.contains) })
            {
                return SpecialSuggestion(
                    placement: .entry(in: mine.id.value),
                    reason: "smddb files it in \(container.displayTitle)",
                    basis: .smddb
                )
            }
            if let extra = container.extras.first(where: { $0.externalRefs.contains(where: refs.contains) }) {
                return SpecialSuggestion(
                    placement: .extra(
                        of: mine.id.value,
                        type: extra.type?.rawValue ?? EntryType.featurette.rawValue
                    ),
                    reason: "smddb files it among \(container.displayTitle)'s extras",
                    basis: .smddb
                )
            }
        }
        return nil
    }

    /// The breakout holding the specials just before and just after it, by the date each aired.
    private nonisolated func breakoutBeside(_ index: Int, in tree: DraftTree) -> SpecialSuggestion? {
        guard index > 0, index + 1 < tree.specials.count,
            case .breakout(let before, let from, let asExtra)? = tree.placements[tree.specials[index - 1].id],
            case .breakout(let after, _, _)? = tree.placements[tree.specials[index + 1].id],
            before == after
        else { return nil }
        let title = tree.container(before)?.displayTitle ?? before
        return SpecialSuggestion(
            placement: .breakout(before, from: from, asExtra: asExtra),
            reason: "the specials either side of it are in \(title)",
            basis: .breakout
        )
    }

    /// The item a library holds that carries one of the special's ids other than Wikidata's, as a
    /// duplicate of that item: a special that is also a film, or an episode of another series.
    private func duplicate(of special: Special, in tree: DraftTree, of silo: Silo) async throws -> SpecialSuggestion? {
        for ref in special.refs where ref.provider != .wikidata {
            guard let home = try await home(of: ref, of: silo) else { continue }
            let named = ref.provider == .imdb ? "IMDb" : ref.provider == .tvdb ? "TVDB" : "TMDb"
            return SpecialSuggestion(
                placement: .duplicate(
                    home: home.container,
                    item: home.item,
                    library: home.library,
                    from: tree.top,
                    asExtra: home.isFilm == false
                ),
                reason: "its \(named) id is \(home.title)'s, which \(home.library) holds",
                basis: .duplicate
            )
        }
        return nil
    }

    /// Where a library holds an item: the library, the container, the item's id in it, its title, and
    /// whether it is a film's own item rather than an entry.
    private struct Home {
        var library: String
        var container: String
        var item: String
        var title: String
        var isFilm: Bool
    }

    /// The item a library holds that carries a reference, in any library: a film's own item, or the
    /// entry that carries it.
    private func home(of ref: ExternalRef, of silo: Silo) async throws -> Home? {
        let held = try await withOperator(silo) {
            try await $0.lookup(provider: ref.provider.rawValue, value: ref.value)
        }
        for summary in held {
            let opened = try await open(container: summary.id, in: summary.library, of: silo)
            let container = try SidecarFile.sidecar(from: opened.sidecar).container
            let entries = container.sequences.flatMap(\.items) + container.extras
            if let entry = entries.first(where: { $0.externalRefs.contains(ref) }), let item = entry.id {
                return Home(
                    library: summary.library,
                    container: summary.id,
                    item: item.value,
                    title: entry.title ?? container.displayTitle,
                    isFilm: false
                )
            }
            if container.externalRefs.contains(ref), let item = container.sequences.first?.items.first?.id {
                return Home(
                    library: summary.library,
                    container: summary.id,
                    item: item.value,
                    title: container.displayTitle,
                    isFilm: container.type == .movie
                )
            }
        }
        return nil
    }

    /// Another way to play a container the special's title names: a new edition of it, beside a word
    /// such as "Omnibus"; or a version of one of its items whose title the special's names beside words
    /// such as "Special Edition".
    nonisolated static func alternative(
        of special: Special,
        in containers: [Container],
        titles: [String: String]
    ) -> SpecialSuggestion? {
        let title = special.episode.title.lowercased()
        let versioned = ["special edition", "enhanced", "new effects"].contains { title.contains($0) }
        let collected = ["omnibus", "compilation"].first { title.contains($0) }
        func named(_ entry: Entry) -> String? {
            entry.title ?? entry.externalRefs.first { $0.provider == .wikidata }.flatMap { titles[$0.value] }
        }
        for container in containers {
            if versioned {
                for entry in container.sequences.flatMap(\.items) {
                    guard let item = entry.id?.value, let name = named(entry), name.count > 3,
                        title.contains(name.lowercased())
                    else { continue }
                    return SpecialSuggestion(
                        placement: .version(of: container.id.value, item: item, title: "Special edition"),
                        reason: "its title names \(name) as another version of it",
                        basis: .alternative
                    )
                }
            }
            guard title.contains(container.title.rawValue.lowercased()), let collected else { continue }
            return SpecialSuggestion(
                placement: .edition(of: container.id.value, title: collected.capitalized),
                reason: "its title names \(container.displayTitle) as an \(collected)",
                basis: .alternative
            )
        }
        return nil
    }

    /// Between the two of the tree's episodes it aired between: an entry after the earlier.
    private nonisolated func airedPosition(of special: Special, in tree: DraftTree) -> SpecialSuggestion? {
        guard let aired = special.episode.premiered else { return nil }
        let specials = Set(tree.specials.map(\.id))
        let dated = tree.airDates.filter { !specials.contains($0.key) }
        guard let before = dated.filter({ $0.value <= aired }).max(by: { $0.value < $1.value }),
            let after = dated.filter({ $0.value > aired }).min(by: { $0.value < $1.value }),
            let place = Self.after(ExternalRef(provider: .wikidata, value: before.key), in: tree)
        else { return nil }
        let earlier = tree.episodeTitles[before.key] ?? before.key
        let later = tree.episodeTitles[after.key] ?? after.key
        return SpecialSuggestion(placement: place, reason: "it aired between \(earlier) and \(later)", basis: .aired)
    }

    /// An entry just after the one carrying a reference, in the container of the tree that holds it.
    private nonisolated static func after(_ ref: ExternalRef, in tree: DraftTree) -> SpecialPlacement? {
        for container in tree.containers {
            for sequence in container.sequences {
                if let index = sequence.items.firstIndex(where: { $0.externalRefs.contains(ref) }) {
                    return .entry(in: container.id.value, sequence: sequence.id, position: index + 1)
                }
            }
        }
        return nil
    }

    /// For a special whose title says what it is: an extra of the series of that type, or declined for a
    /// trailer.
    private nonisolated static func byItsTitle(_ special: Special, in tree: DraftTree) -> SpecialSuggestion? {
        let title = special.episode.title.lowercased()
        if title.contains("trailer") {
            return SpecialSuggestion(placement: .declined, reason: "its title says it is a trailer")
        }
        let kinds: [(String, EntryType)] = [
            ("behind the scenes", .behindTheScenes), ("making of", .behindTheScenes), ("deleted", .deletedScene),
            ("interview", .interview), ("featurette", .featurette),
        ]
        guard let (words, type) = kinds.first(where: { title.contains($0.0) }) else { return nil }
        return SpecialSuggestion(
            placement: .extra(of: tree.top, type: type.rawValue),
            reason: "its title says it is \(words == "making of" ? "a making-of" : words)"
        )
    }

    // MARK: What a walk's store makes outside its stops

    /// Adds references to what a library's container declines, its own fields as they stand.
    func decline(_ refs: [ExternalRef], in container: String, of library: String, on silo: Silo) async throws {
        let opened = try await open(container: container, in: library, of: silo)
        let sidecar = try SidecarFile.sidecar(from: opened.sidecar)
        var declined = sidecar.declined
        for ref in refs where !declined.contains(ref) { declined.append(ref) }
        let document = try ContainerDraft.document(of: opened.sidecar)
        let refs = declined.map { SiloClient.Container.ExternalRef(provider: $0.provider.rawValue, value: $0.value) }
        _ = try await withOperator(silo) {
            try await $0.edit(
                container: container,
                in: library,
                document: document,
                basedOn: opened.container.digest,
                declined: refs
            )
        }
    }

    /// One edit of a container a library holds that a placement makes, onto its sidecar as it is now.
    func apply(_ edit: DraftTree.Making.HeldEdit, on silo: Silo) async throws {
        let opened = try await open(container: edit.container, in: edit.library, of: silo)
        var draft = try ContainerDraft.change(opened.container, sidecar: opened.sidecar)
        guard var container = draft.value else { return }
        Self.applying(edit, to: &container)
        draft.set(container)
        switch try await store(draft, of: silo) {
        case .stored: break
        case .refused(let result):
            throw StoreRefused(reason: result.findings.map(\.text).joined(separator: "; "))
        case .landedFirst:
            throw StoreRefused(reason: "\(edit.container) changed in \(edit.library) as it was edited; try again")
        }
    }

    /// What an edit a placement makes does to the container it is of.
    nonisolated static func applying(_ edit: DraftTree.Making.HeldEdit, to container: inout Container) {
        if let item = edit.item, let ref = edit.ref {
            container.sequences = container.sequences.map { sequence in
                var sequence = sequence
                sequence.items = sequence.items.map { Self.adding(ref, to: $0, if: item) }
                return sequence
            }
            container.extras = container.extras.map { Self.adding(ref, to: $0, if: item) }
        }
        if let special = edit.entry, let entryID = edit.entryID.flatMap(ItemID.init) {
            // An extra's type named makes it one of the container's extras; otherwise it is an episode.
            if let type = edit.entryType {
                container.extras.append(.leaf(Entry.Leaf(id: entryID, type: type, externalRefs: special.refs)))
            } else {
                DraftTree.insert(
                    .leaf(Entry.Leaf(id: entryID, type: .episode, externalRefs: special.refs)),
                    into: &container,
                    sequence: nil,
                    at: nil
                )
            }
        }
        if let refer = edit.refer { DraftTree.refer(to: refer, from: &container, asExtra: edit.asExtra) }
    }

    private nonisolated static func adding(_ ref: ExternalRef, to entry: Entry, if item: String) -> Entry {
        guard entry.id?.value == item else { return entry }
        switch entry {
        case .leaf(var leaf):
            if !leaf.externalRefs.contains(ref) { leaf.externalRefs.append(ref) }
            return .leaf(leaf)
        case .child(var child):
            if !child.externalRefs.contains(ref) { child.externalRefs.append(ref) }
            return .child(child)
        case .ref:
            return entry
        }
    }
}
