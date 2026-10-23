// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloClient
import SmdKit
import SmdSidecar

// MARK: - TMDb

/// Drafts from TMDb: a record read as the containers it would be, facts taken plainly and the outline
/// attributed, shaped by the operator before anything is made, and made through the silo's create
/// route, which takes containers as documents whoever wrote them. A record smddb holds is imported
/// from smddb instead, and one the library holds is not drafted. `Tmdb.md`.
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

    /// How to read a series: which of its seasons, all of them but season 0 when nil, and whether to
    /// read one of its episode groups in their place, each group a child of the type given.
    public struct TMDbShape: Hashable, Sendable {
        public var seasons: Set<Int>?
        public var group: String?
        public var groupType: ContainerType
        public var groupTypeLabel: String?

        public init(
            seasons: Set<Int>? = nil,
            group: String? = nil,
            groupType: ContainerType = .serial,
            groupTypeLabel: String? = nil
        ) {
            self.seasons = seasons
            self.group = group
            self.groupType = groupType
            self.groupTypeLabel = groupTypeLabel
        }
    }

    /// What picking a TMDb record comes to: smddb's container to import instead, the library's
    /// container that carries the record's reference already, or a draft.
    public enum TMDbStart: Hashable, Sendable {
        case importFromSmddb(Container)
        case held(SiloClient.ContainerSummary)
        case draft(TMDbTree)
    }

    /// Starts a draft of a TMDb record for a library: smddb first, the library next, and otherwise the
    /// record read as containers, kept on this Mac.
    public func startDraft(
        of record: TMDb.Record,
        shape: TMDbShape = TMDbShape(),
        into library: String,
        of silo: Silo,
        from database: any ContainerDatabase,
        tmdb: any TMDbSource
    ) async throws -> TMDbStart {
        if let known = try await database.containers().first(where: {
            $0.type == record.containerType && $0.externalRefs.contains(record.ref)
        }) {
            return .importFromSmddb(known)
        }
        if let held = try await carrying(record, in: library, of: silo) { return .held(held) }

        var reader = Reader(tmdb: tmdb, database: database)
        let top: Container
        var creating = ContainerDraft.Creating()
        switch record.kind {
        case .movie:
            let movie = try await tmdb.movie(record.id)
            top = try await reader.movie(movie)
        case .collection:
            top = try await reader.collection(try await tmdb.collection(record.id))
        case .series:
            top = try await reader.series(try await tmdb.series(record.id), shape: shape)
        }
        if record.kind == .movie, let collection = reader.collectionAbove,
            let holder = try await carrying(TMDb.Record(.collection, collection), in: library, of: silo)
        {
            creating = ContainerDraft.Creating(parent: holder.id)
        }
        let tree = reader.tree(top: top, record: record, library: library, creating: creating)
        try tmdbDrafts.save(tree, for: silo.id)
        return .draft(tree)
    }

    /// Starts a draft of one of a series' seasons beneath the series a library holds by its reference.
    public func startDraft(
        ofSeason number: Int,
        of series: Int,
        beneath held: String,
        into library: String,
        of silo: Silo,
        from database: any ContainerDatabase,
        tmdb: any TMDbSource
    ) async throws -> TMDbTree {
        var reader = Reader(tmdb: tmdb, database: database)
        let season = try await reader.season(try await tmdb.season(number, of: series))
        let tree = reader.tree(
            top: season,
            record: TMDb.Record(.series, series),
            library: library,
            creating: ContainerDraft.Creating(parent: held)
        )
        try tmdbDrafts.save(tree, for: silo.id)
        return tree
    }

    /// The library's container that carries a record's reference, of the record's kind, if any.
    private func carrying(
        _ record: TMDb.Record,
        in library: String,
        of silo: Silo
    ) async throws -> SiloClient.ContainerSummary? {
        try await withOperator(silo) { try await $0.lookup(provider: "tmdb", value: String(record.id)) }
            .first { $0.library == library && $0.type == record.containerType.rawValue }
    }

    /// Reads TMDb records as containers, each with an id from smddb's client, gathering what the tree
    /// keeps beside them.
    private struct Reader {
        let tmdb: any TMDbSource
        let database: any ContainerDatabase
        var attributions: [ContainerID: [Attribution]] = [:]
        var containers: [Container] = []
        var episodeTitles: [String: String] = [:]
        var airDates: [String: String] = [:]
        var episodeGroups: [String] = []
        var specials: [Special] = []
        /// The collection a movie read is in, for filing it beneath one the library holds.
        var collectionAbove: Int?

        init(tmdb: any TMDbSource, database: any ContainerDatabase) {
            self.tmdb = tmdb
            self.database = database
        }

        func tree(top: Container, record: TMDb.Record, library: String, creating: ContainerDraft.Creating) -> TMDbTree {
            TMDbTree(
                library: library,
                record: record,
                creating: creating,
                containers: containers,
                top: top.id,
                attributions: attributions,
                episodeTitles: episodeTitles,
                airDates: airDates,
                episodeGroups: episodeGroups,
                specials: specials
            )
        }

        /// A container from a record's facts, its outline TMDb's overview, attributed.
        private mutating func make(
            _ type: ContainerType,
            title: String,
            year: Int?,
            overview: String?,
            refs: [ExternalRef]
        ) async throws -> Container {
            var container = Container(
                id: try await database.provisionalID(),
                type: type,
                title: Title(title) ?? Title("Untitled")!,
                year: type.hasYear ? year : nil,
                yearInTitle: type == .movie || type == .series,
                outline: overview,
                externalRefs: refs
            )
            container.sequences = []
            if let overview, !overview.isEmpty, let tmdb = refs.first(where: { $0.provider == .tmdb }) {
                attributions[container.id] = [Attribution(subject: .outline, provider: .tmdb, value: tmdb.value)]
            }
            return container
        }

        mutating func movie(_ movie: TMDb.Movie) async throws -> Container {
            var container = try await make(
                .movie,
                title: movie.title,
                year: movie.year,
                overview: movie.overview,
                refs: [ExternalRef(provider: .tmdb, value: String(movie.id))] + movie.externalIDs.refs
            )
            container.sequences = [
                Sequence(id: "main", items: [.leaf(Entry.Leaf(id: ItemID("feature")!, type: .movie))])
            ]
            collectionAbove = movie.collection
            containers.append(container)
            return container
        }

        mutating func collection(_ collection: TMDb.Collection) async throws -> Container {
            var container = try await make(
                .collection,
                title: collection.name,
                year: nil,
                overview: collection.overview,
                refs: [ExternalRef(provider: .tmdb, value: String(collection.id))]
            )
            containers.append(container)
            var items: [Entry] = []
            for part in collection.parts {
                let movie = try await self.movie(try await tmdb.movie(part.id))
                items.append(.child(Entry.Child(id: Self.itemID(movie.title.rawValue, in: items), container: movie.id)))
            }
            container.sequences = [Sequence(id: "movies", items: items)]
            replace(container)
            return container
        }

        mutating func series(_ series: TMDb.Series, shape: TMDbShape) async throws -> Container {
            var container = try await make(
                .series,
                title: series.name,
                year: series.year,
                overview: series.overview,
                refs: [ExternalRef(provider: .tmdb, value: String(series.id))] + series.externalIDs.refs
            )
            containers.append(container)
            episodeGroups = series.episodeGroups.map(\.id)
            var placed: Set<Int> = []
            var items: [Entry] = []
            if let group = shape.group {
                for part in try await tmdb.episodeGroup(group).groups {
                    var child = try await make(shape.groupType, title: part.name, year: nil, overview: nil, refs: [])
                    child.typeLabel = shape.groupTypeLabel
                    child.sequences = [Sequence(id: "parts", items: episodes(part.episodes))]
                    placed.formUnion(part.episodes.map(\.id))
                    containers.append(child)
                    items.append(.child(Entry.Child(id: Self.itemID(part.name, in: items), container: child.id)))
                }
            } else {
                let wanted = series.seasons.filter { $0.number != 0 && shape.seasons?.contains($0.number) ?? true }
                let records = try await AdminConsole.concurrently(wanted) { [tmdb, id = series.id] summary in
                    try await tmdb.season(summary.number, of: id)
                }
                for record in records {
                    let season = try await self.season(record)
                    items.append(
                        .child(Entry.Child(id: Self.itemID(season.title.rawValue, in: items), container: season.id))
                    )
                }
            }
            container.sequences = [Sequence(id: "seasons", items: items)]
            replace(container)
            if series.seasons.contains(where: { $0.number == 0 }) {
                let pool = try await tmdb.season(0, of: series.id).episodes.filter { !placed.contains($0.id) }
                for episode in pool { note(episode) }
                specials = pool.map { Special(episode: $0) }
            }
            return container
        }

        mutating func season(_ season: TMDb.Season) async throws -> Container {
            var container = try await make(
                .season,
                title: season.name,
                year: season.year,
                overview: season.overview,
                refs: [ExternalRef(provider: .tmdb, value: String(season.id))]
            )
            container.sequences = [Sequence(id: "episodes", items: episodes(season.episodes))]
            containers.append(container)
            return container
        }

        /// Episodes as entries, each carrying its reference and no title, since TMDb has one for it.
        private mutating func episodes(_ episodes: [TMDb.Episode]) -> [Entry] {
            var entries: [Entry] = []
            for episode in episodes {
                note(episode)
                entries.append(
                    .leaf(
                        Entry.Leaf(
                            id: Self.itemID(episode.title, in: entries),
                            type: .episode,
                            externalRefs: [episode.ref]
                        )
                    )
                )
            }
            return entries
        }

        private mutating func note(_ episode: TMDb.Episode) {
            episodeTitles[String(episode.id)] = episode.title
            if let airDate = episode.airDate { airDates[String(episode.id)] = airDate }
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
    /// is advice rather than a place, as for a duplicate whose home no library holds yet.
    public struct SpecialSuggestion: Hashable, Sendable {
        public var placement: SpecialPlacement?
        public var reason: String

        public init(placement: SpecialPlacement?, reason: String) {
            self.placement = placement
            self.reason = reason
        }
    }

    /// A suggestion for each unassigned special that has one, strongest first: where smddb files its
    /// reference; the breakout the specials either side of it are in; a duplicate of the record whose
    /// IMDb or TVDB id it shares; the position an episode group gives it; where it aired among the tree's
    /// episodes; and, for a short special whose title says what it is, an extra of that type, or
    /// declined for a trailer. Asking TMDb for each special's other ids, the tree gains them.
    public func suggest(
        for tree: TMDbTree,
        of silo: Silo,
        from database: any ContainerDatabase,
        tmdb: any TMDbSource,
        progress: @Sendable (TMDbProgress) async -> Void = { _ in }
    ) async throws -> (TMDbTree, [Int: SpecialSuggestion]) {
        let (suggested, suggestions) = try await suggestions(
            for: tree,
            of: silo,
            from: database,
            tmdb: tmdb,
            progress: progress
        )
        try tmdbDrafts.save(suggested, for: silo.id)
        return (suggested, suggestions)
    }

    /// The suggestions `suggest(for:of:from:tmdb:progress:)` makes, keeping nothing.
    func suggestions(
        for tree: TMDbTree,
        of silo: Silo,
        from database: any ContainerDatabase,
        tmdb: any TMDbSource,
        progress: @Sendable (TMDbProgress) async -> Void = { _ in }
    ) async throws -> (TMDbTree, [Int: SpecialSuggestion]) {
        var tree = tree
        var suggestions: [Int: SpecialSuggestion] = [:]
        let clone = try await database.containers()
        let unplaced = tree.specials.indices.filter { tree.placements[tree.specials[$0].id] == nil }
        var group: TMDb.EpisodeGroup?
        if let first = tree.episodeGroups.first { group = try await tmdb.episodeGroup(first) }
        let step = "Suggesting where the specials go"
        await progress(TMDbProgress(step, of: unplaced.count))
        // Each special is read on its own, against the tree as it came: none's suggestion rests on another's.
        let reading: @Sendable (Int) async throws -> (Special, SpecialSuggestion?) = { [tree, group] index in
            var special = tree.specials[index]
            if special.refs.count == 1, let ids = try? await tmdb.externalIDs(of: special.episode, in: tree.record.id) {
                special.refs = [special.episode.ref] + ids.refs
            }
            let suggestion = try await self.suggestion(
                for: special,
                at: index,
                in: tree,
                clone: clone,
                group: group,
                of: silo,
                tmdb: tmdb
            )
            return (special, suggestion)
        }
        let read = try await Self.concurrently(
            unplaced,
            done: { await progress(TMDbProgress(step, done: $0, of: unplaced.count)) },
            reading
        )
        for (index, (special, suggestion)) in zip(unplaced, read) {
            tree.specials[index] = special
            suggestions[special.id] = suggestion
        }
        return (tree, suggestions)
    }

    /// The strongest suggestion for one special, the special carrying the other ids TMDb holds for it.
    private func suggestion(
        for special: Special,
        at index: Int,
        in tree: TMDbTree,
        clone: [Container],
        group: TMDb.EpisodeGroup?,
        of silo: Silo,
        tmdb: any TMDbSource
    ) async throws -> SpecialSuggestion? {
        if let found = smddbFiling(of: special, in: clone, tree: tree) { return found }
        if let beside = breakoutBeside(index, in: tree) { return beside }
        if let duplicate = try await duplicate(of: special, in: tree, of: silo, tmdb: tmdb) { return duplicate }
        if let group, let grouped = Self.groupPosition(of: special, in: tree, group: group) { return grouped }
        if let aired = airedPosition(of: special, in: tree) { return aired }
        return Self.byItsTitle(special, in: tree)
    }

    /// Where smddb's record of the series files the special's reference: in the container of the tree
    /// that carries a reference smddb's filing container does, since the tree's ids are new ones.
    private nonisolated func smddbFiling(
        of special: Special,
        in clone: [Container],
        tree: TMDbTree
    ) -> SpecialSuggestion? {
        let drafted = tree.containers
        for container in clone {
            guard
                let mine = drafted.first(where: { drafted in
                    drafted.externalRefs.contains { container.externalRefs.contains($0) }
                })
            else { continue }
            if container.sequences.flatMap(\.items).contains(where: { $0.externalRefs.contains(special.episode.ref) }) {
                return SpecialSuggestion(
                    placement: .entry(in: mine.id.value),
                    reason: "smddb files it in \(container.displayTitle)"
                )
            }
            if let extra = container.extras.first(where: { $0.externalRefs.contains(special.episode.ref) }) {
                return SpecialSuggestion(
                    placement: .extra(
                        of: mine.id.value,
                        type: extra.type?.rawValue ?? EntryType.featurette.rawValue
                    ),
                    reason: "smddb files it among \(container.displayTitle)'s extras"
                )
            }
        }
        return nil
    }

    /// The breakout holding the specials just before and just after it in TMDb's season 0 order.
    private nonisolated func breakoutBeside(_ index: Int, in tree: TMDbTree) -> SpecialSuggestion? {
        guard index > 0, index + 1 < tree.specials.count,
            case .breakout(let before, let from, let asExtra)? = tree.placements[tree.specials[index - 1].id],
            case .breakout(let after, _, _)? = tree.placements[tree.specials[index + 1].id],
            before == after
        else { return nil }
        let title = tree.container(before)?.displayTitle ?? before
        return SpecialSuggestion(
            placement: .breakout(before, from: from, asExtra: asExtra),
            reason: "the specials either side of it are in \(title)"
        )
    }

    /// The record whose IMDb or TVDB id the special shares, as a duplicate of the item a library holds
    /// for it; advice to draft it first when none holds it.
    private func duplicate(
        of special: Special,
        in tree: TMDbTree,
        of silo: Silo,
        tmdb: any TMDbSource
    ) async throws -> SpecialSuggestion? {
        for ref in special.refs where ref.provider == .imdb || ref.provider == .tvdb {
            let found = try await tmdb.find(ref)
            let others = found.episodes.filter { $0.series != tree.record.id }
            let named = ref.provider == .imdb ? "IMDb" : "TVDB"
            if let movie = found.movies.first {
                let reason = "its \(named) id is \(movie.title)'s, TMDb's movie \(movie.id)"
                guard let home = try await home(of: ExternalRef(provider: .tmdb, value: String(movie.id)), of: silo)
                else {
                    return SpecialSuggestion(
                        placement: nil,
                        reason: "\(reason), which no library holds: draft it first"
                    )
                }
                return SpecialSuggestion(
                    placement: .duplicate(
                        home: home.container,
                        item: home.item,
                        library: home.library,
                        from: tree.top,
                        asExtra: false
                    ),
                    reason: "\(reason), which \(home.library) holds"
                )
            }
            if let other = others.first {
                let reason = "its \(named) id is \(other.episode.title)'s, an episode of TMDb's series \(other.series)"
                guard let home = try await home(of: other.episode.ref, of: silo) else {
                    return SpecialSuggestion(
                        placement: nil,
                        reason: "\(reason), which no library holds: draft it first"
                    )
                }
                return SpecialSuggestion(
                    placement: .duplicate(
                        home: home.container,
                        item: home.item,
                        library: home.library,
                        from: tree.top,
                        asExtra: true
                    ),
                    reason: "\(reason), which \(home.library) holds"
                )
            }
        }
        return nil
    }

    /// The item a library holds that carries a reference, in any library: a movie's own item, or the
    /// entry that carries it.
    private func home(
        of ref: ExternalRef,
        of silo: Silo
    ) async throws -> (library: String, container: String, item: String)? {
        let held = try await withOperator(silo) {
            try await $0.lookup(provider: ref.provider.rawValue, value: ref.value)
        }
        for summary in held {
            let opened = try await open(container: summary.id, in: summary.library, of: silo)
            let container = try SidecarFile.sidecar(from: opened.sidecar).container
            let entries = container.sequences.flatMap(\.items) + container.extras
            if let entry = entries.first(where: { $0.externalRefs.contains(ref) }), let item = entry.id {
                return (summary.library, summary.id, item.value)
            }
            if container.externalRefs.contains(ref), let item = container.sequences.first?.items.first?.id {
                return (summary.library, summary.id, item.value)
            }
        }
        return nil
    }

    /// The position the series' first episode group gives the special: after the episode it follows
    /// there, in the container of the tree that holds that episode.
    private nonisolated static func groupPosition(
        of special: Special,
        in tree: TMDbTree,
        group: TMDb.EpisodeGroup
    ) -> SpecialSuggestion? {
        for part in group.groups {
            guard let index = part.episodes.firstIndex(where: { $0.id == special.id }), index > 0 else { continue }
            let before = part.episodes[index - 1]
            guard let place = Self.after(before.ref, in: tree) else { continue }
            return SpecialSuggestion(
                placement: place,
                reason: "\(group.name) places it after \(before.title)"
            )
        }
        return nil
    }

    /// Between the two of the tree's episodes it aired between: an entry after the earlier.
    private nonisolated func airedPosition(of special: Special, in tree: TMDbTree) -> SpecialSuggestion? {
        guard let aired = special.episode.airDate else { return nil }
        let specials = Set(tree.specials.map { String($0.id) })
        let dated = tree.airDates.filter { !specials.contains($0.key) }
        guard let before = dated.filter({ $0.value <= aired }).max(by: { $0.value < $1.value }),
            let after = dated.filter({ $0.value > aired }).min(by: { $0.value < $1.value }),
            let place = Self.after(ExternalRef(provider: .tmdb, value: before.key), in: tree)
        else { return nil }
        let earlier = tree.episodeTitles[before.key] ?? before.key
        let later = tree.episodeTitles[after.key] ?? after.key
        return SpecialSuggestion(placement: place, reason: "it aired between \(earlier) and \(later)")
    }

    /// An entry just after the one carrying a reference, in the container of the tree that holds it.
    private nonisolated static func after(_ ref: ExternalRef, in tree: TMDbTree) -> SpecialPlacement? {
        for container in tree.containers {
            for sequence in container.sequences {
                if let index = sequence.items.firstIndex(where: { $0.externalRefs.contains(ref) }) {
                    return .entry(in: container.id.value, sequence: sequence.id, position: index + 1)
                }
            }
        }
        return nil
    }

    /// For a short special whose title says what it is: an extra of the series of that type, or
    /// declined for a trailer.
    private nonisolated static func byItsTitle(_ special: Special, in tree: TMDbTree) -> SpecialSuggestion? {
        guard (special.episode.runtime ?? 0) < 30 else { return nil }
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

    // MARK: Creating

    /// How a draft from TMDb's making ended: made, which ends the draft; refused by the silo's findings
    /// on the parent's edit naming the top, or on the making, which keep it.
    public enum TMDbCreateOutcome: Hashable, Sendable {
        case created(SiloClient.ContainerCreateResult)
        case parentRefused(SiloClient.ContainerEditResult)
        case refused(SiloClient.ContainerCreateResult)
    }

    /// What the silo makes of the tree, asked as a dry run and storing nothing: the edit of the parent
    /// naming the top, for a tree beneath one, or else the making of the tree itself.
    public func check(_ tree: TMDbTree, of silo: Silo) async throws -> ContainerCheck {
        let making = tree.making
        guard let top = making.documents.first else { return .unreadable("the draft holds nothing") }
        if let parent = tree.creating.parent {
            let opened = try await open(container: parent, in: tree.library, of: silo)
            var naming = try ContainerDraft.change(opened.container, sidecar: opened.sidecar)
            guard let held = naming.value else {
                return .unreadable("the parent's sidecar does not read as a container")
            }
            naming.set(Self.naming(top, in: held, at: tree.creating))
            return try await check(naming, of: silo)
        }
        do {
            let result = try await withOperator(silo) {
                try await $0.create(
                    containers: making.documents.map(TMDbTree.text),
                    parent: nil,
                    in: tree.library,
                    attributions: making.attributions,
                    dryRun: true
                )
            }
            return .wouldWrite(Self.editResult(result))
        } catch SiloClientError.status(422, let body) {
            guard
                let result = try? SiloClient.decoder.decode(
                    SiloClient.ContainerCreateResult.self,
                    from: Data(body.utf8)
                )
            else { return .unreadable(Self.detail(body)) }
            return .refused(Self.editResult(result))
        } catch SiloClientError.status(400, let body) {
            return .unreadable(Self.detail(body))
        }
    }

    /// Makes the tree: the new breakouts at the top of the library, then the parent's edit naming the
    /// top, for a tree beneath one, then the tree with its attributions in one request, then the
    /// references the top declines, then the edits of containers libraries hold that placements make.
    /// Made, the draft ends; a refusal keeps it.
    public func create(_ tree: TMDbTree, of silo: Silo) async throws -> TMDbCreateOutcome {
        let making = tree.making
        guard let top = making.documents.first else { throw StoreRefused(reason: "the draft holds nothing") }
        for breakout in making.breakouts {
            _ = try await withOperator(silo) {
                try await $0.create(containers: [TMDbTree.text(breakout)], parent: nil, in: tree.library)
            }
        }
        if let parent = tree.creating.parent {
            let opened = try await open(container: parent, in: tree.library, of: silo)
            var naming = try ContainerDraft.change(opened.container, sidecar: opened.sidecar)
            guard let held = naming.value else {
                throw StoreRefused(reason: "the parent's sidecar does not read as a container")
            }
            let named = Self.naming(top, in: held, at: tree.creating)
            if named != held {
                naming.set(named)
                switch try await store(naming, of: silo) {
                case .stored: break
                case .refused(let result): return .parentRefused(result)
                case .landedFirst:
                    throw StoreRefused(reason: "the parent's sidecar changed as it was edited; try again")
                }
            }
        }
        let result: SiloClient.ContainerCreateResult
        do {
            result = try await withOperator(silo) {
                try await $0.create(
                    containers: making.documents.map(TMDbTree.text),
                    parent: tree.creating.parent,
                    in: tree.library,
                    attributions: making.attributions
                )
            }
        } catch SiloClientError.status(422, let body) {
            guard
                let refused = try? SiloClient.decoder.decode(
                    SiloClient.ContainerCreateResult.self,
                    from: Data(body.utf8)
                )
            else { throw StoreRefused(reason: Self.detail(body)) }
            return .refused(refused)
        } catch SiloClientError.status(let status, let body) where status == 400 || status == 404 {
            throw StoreRefused(
                reason: Self.detail(body).isEmpty ? "the library no longer holds the parent" : Self.detail(body)
            )
        }
        if !making.declined.isEmpty {
            try await decline(making.declined, in: top.id.value, of: tree.library, on: silo)
        }
        for edit in making.heldEdits { try await apply(edit, on: silo) }
        try tmdbDrafts.remove(tree.id, of: silo.id)
        return .created(result)
    }

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
    func apply(_ edit: TMDbTree.Making.HeldEdit, on silo: Silo) async throws {
        let opened = try await open(container: edit.container, in: edit.library, of: silo)
        var draft = try ContainerDraft.change(opened.container, sidecar: opened.sidecar)
        guard var container = draft.value else { return }
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
                TMDbTree.insert(
                    .leaf(Entry.Leaf(id: entryID, type: .episode, externalRefs: special.refs)),
                    into: &container,
                    sequence: nil,
                    at: nil
                )
            }
        }
        if let refer = edit.refer { TMDbTree.refer(to: refer, from: &container, asExtra: edit.asExtra) }
        draft.set(container)
        switch try await store(draft, of: silo) {
        case .stored: break
        case .refused(let result):
            throw StoreRefused(reason: result.findings.map(\.text).joined(separator: "; "))
        case .landedFirst:
            throw StoreRefused(reason: "\(edit.container) changed in \(edit.library) as it was edited; try again")
        }
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
