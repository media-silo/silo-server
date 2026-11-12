// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import SiloKit
import SmdKit
import SmdSidecar

// MARK: - Differences from Wikidata and TMDb

/// What a review walk reads at each stop: a held container read against the providers, and each way it
/// differs, for the operator to take or leave.
extension ReviewWalk {
    /// One way a held container differs from what is read of it.
    public enum Difference: Hashable, Sendable, Identifiable, Codable {
        case title(String)
        case year(Int)
        /// TMDb's overview, attributed to the record it came from when it is taken.
        case outline(String, record: String)
        /// An outline read from TMDb on a day longer ago than TMDb's terms let it be kept: TMDb's overview
        /// read again, the same or changed, attributed anew when it is taken, or, nil, removed with its
        /// attribution, TMDb having none now.
        case staleOutline(String?, record: String, read: CalendarDate)
        /// When an episode was first shown, as Wikidata dates it.
        case premiered(CalendarDate)
        /// Who is in an episode, as Wikidata lists them, in place of the cast it holds.
        case cast([Person])
        /// Who directed and wrote an episode, as Wikidata lists them, in place of the directors and writers
        /// it holds; crew of any other job is kept.
        case crew([Person])
        /// A provider's id Wikidata holds that the sidecar lacks: for the container, or for one of its
        /// items.
        case reference(item: String?, ExternalRef)
        /// An episode nothing in the library carries, drafted as a container of its own beneath the
        /// container when taken, after the one it follows in Wikidata's order.
        case episode(Wikidata.Work, after: ExternalRef?)
        /// A child Wikidata lists that no container carries, a series' season or a season's serial,
        /// drafted from Wikidata beneath the container when taken.
        case child(Wikidata.Summary)
        /// A child Wikidata lists that the container holds beneath it: by its Wikidata id, or,
        /// `suggested`, a season carrying none that its title suggests is this one. Shown among the
        /// children, and a stop of the walk whatever is chosen, so never chosen itself.
        case heldChild(Wikidata.Summary, container: String, suggested: Bool)
        /// A season beneath a series of Wikidata's that carries no Wikidata id, so matches nothing there:
        /// the series' seasons, for the operator to say which it is, and the one its title suggests.
        case unmatchedSeason(series: String, seasons: [Wikidata.Summary], suggested: String?)
        /// Items both hold, at the same level, in Wikidata's order rather than the sidecar's.
        case order(sequence: String?, items: [String])
        /// An artwork kind the folder has no file for, the image TMDb offers first for it, and every
        /// image TMDb offers for it, best first.
        case artwork(kind: String, path: String, record: TMDb.Record, offered: [String]? = nil)
        /// An artwork kind the folder has, put from TMDb on a day longer ago than TMDb's terms let it be
        /// kept: the image TMDb offers first for it now, put again with a new attribution when it is
        /// taken, or, nil, the kind removed, TMDb having no image for it now.
        case staleArtwork(kind: String, path: String?, record: TMDb.Record, offered: [String], read: CalendarDate)
        /// A special of the series nothing covers, to be placed or declined as a draft's specials are.
        case special(Special)

        public var id: String {
            switch self {
            case .title: "title"
            case .year: "year"
            case .outline, .staleOutline: "outline"
            case .premiered: "premiered"
            case .cast: "cast"
            case .crew: "crew"
            case .reference(let item, let ref): "ref:\(item ?? ""):\(ref.provider):\(ref.value)"
            case .episode(let episode, _): "episode:\(episode.id)"
            case .child(let child): "child:\(child.id)"
            case .heldChild(_, let container, _): "held:\(container)"
            case .unmatchedSeason: "unmatched"
            case .order(let sequence, _): "order:\(sequence ?? "")"
            case .artwork(let kind, _, _, _), .staleArtwork(let kind, _, _, _, _): "artwork:\(kind)"
            case .special(let special): "special:\(special.id)"
            }
        }
    }

    /// A held container read against Wikidata and TMDb: what was read, the differences, what the library
    /// holds that Wikidata has nothing for, the specials it declines, and what each uncovered special is
    /// suggested for.
    public struct Comparison: Hashable, Sendable, Codable {
        public var library: String
        public var container: String
        public var title: String
        /// What was read, in words: the container's own item, or the one it was read through.
        public var reading: String
        /// Why no content was read from TMDb, when none was: no token, or what TMDb answered.
        public var noContent: String?
        public var differences: [Difference]
        /// Items the library holds that Wikidata has nothing for: shown, and never offered for removal.
        public var heldOnly: [String]
        public var declined: [Special]
        public var suggestions: [String: AdminConsole.SpecialSuggestion]
        /// Wikidata's title for each episode compared, by Wikidata id: shown, and stored nowhere.
        public var episodeTitles: [String: String]
        /// The episodes compared, by Wikidata id, in Wikidata's order: what places a container held
        /// beneath among the missing ones.
        public var episodeOrder: [String]
        /// The container as the reading found it, which its stop's edit is based on.
        public var opened: AdminConsole.OpenedContainer
        /// The containers held beneath it, in the order it holds them, read when its missing episodes are:
        /// shown among its children, each one its missing episodes may be added to.
        public var heldChildren: [HeldChild]?
        /// The episode containers held beneath it, by the Wikidata id of the episode each is: what a missing
        /// episode is placed after.
        public var episodeContainers: [String: String]?
        /// TMDb's overviews of the episodes of its season, by TMDb's id for each: a missing episode's
        /// outline, when it is drafted.
        public var episodeOutlines: [String: String]?
        /// Where TMDb holds the stills of the episodes of its season, by TMDb's id for each: a missing
        /// episode's `thumb`, when it is drafted.
        public var episodeStills: [String: TMDb.EpisodeStills]?

        init(library: String, container: String, title: String, opened: AdminConsole.OpenedContainer) {
            self.library = library
            self.container = container
            self.title = title
            reading = ""
            differences = []
            heldOnly = []
            declined = []
            suggestions = [:]
            episodeTitles = [:]
            episodeOrder = []
            self.opened = opened
        }
    }

    /// A container held beneath one read against Wikidata, as the children of the one read show it.
    public struct HeldChild: Hashable, Sendable, Codable, Identifiable {
        public var id: String
        public var title: String
        public var type: ContainerType
        public var typeLabel: String?
        /// The place in Wikidata's order, from 1, of the first of the episodes read it holds, which places it
        /// among the missing ones; nil when it holds none of them.
        public var position: Int?

        public init(id: String, title: String, type: ContainerType, typeLabel: String? = nil, position: Int? = nil) {
            self.id = id
            self.title = title
            self.type = type
            self.typeLabel = typeLabel
            self.position = position
        }
    }
}

/// How a container a library holds differs from what the console reads of it, each difference the
/// operator's to take or leave: its facts from Wikidata, and its content, an outline and artwork, from
/// TMDb. Nothing the library holds and Wikidata lacks is offered for removal: a cut, a feature or an extra
/// is the operator's own, so Wikidata's silence about one says nothing. The console reads only when the
/// operator opens a container's differences, and follows nothing. `Proposals/Wikidata.md`.
extension AdminConsole {
    /// Why a container cannot be read against Wikidata: it carries no Wikidata id, nothing above it does,
    /// and none of its items does.
    public struct NoReading: Error, Hashable {
        public var reason: String
    }

    /// What a reading asks of: the silo, Wikidata, and TMDb when there is a token for it.
    struct Sources: Sendable {
        var silo: Silo
        var wikidata: any WikidataSource
        var tmdb: (any TMDbSource)?
        var today: CalendarDate
    }

    /// The nearest container above another of a type, with the ids it carries.
    struct Above: Hashable, Sendable {
        var id: String
        var container: Container
        var wikidata: String? { container.externalRefs.first { $0.provider == .wikidata }?.value }
        var tmdb: String? { container.externalRefs.first { $0.provider == .tmdb }?.value }
    }

    /// Reads a held container against Wikidata, and its content against TMDb. A container with no
    /// Wikidata id of its own is read through the nearest container above it that has one, or, failing
    /// that, through the Wikidata ids its items carry; its differences are then about its entries.
    /// `progress` is told each step as the reading goes, with the comparison as far as it has got.
    public func compare(
        _ id: String,
        in library: String,
        of silo: Silo,
        from database: any ContainerDatabase,
        wikidata: any WikidataSource,
        tmdb: (any TMDbSource)?,
        identified: [String: String] = [:],
        today: CalendarDate = .today,
        progress: @escaping @Sendable (StepProgress, ReviewWalk.Comparison) async -> Void = { _, _ in }
    ) async throws -> ReviewWalk.Comparison {
        let opened = try await open(container: id, in: library, of: silo)
        let sidecar = try SidecarFile.sidecar(from: opened.sidecar)
        let container = sidecar.container
        var comparison = ReviewWalk.Comparison(
            library: library,
            container: id,
            title: container.displayTitle,
            opened: opened
        )
        let sources = Sources(silo: silo, wikidata: wikidata, tmdb: tmdb, today: today)
        if tmdb == nil { comparison.noContent = TMDb.Unavailable.noToken.reason }
        await progress(StepProgress("Reading Wikidata"), comparison)
        let own = container.externalRefs.first { $0.provider == .wikidata }?.value
        let seriesAbove = container.type == .season ? try await above(opened, ofType: .series, of: silo) : nil
        switch (container.type, own) {
        case (.movie, let item?), (.collection, let item?):
            let work =
                container.type == .movie ? try await wikidata.film(item) : try await wikidata.collection(item).work
            comparison.reading = "Wikidata's item \(item)"
            comparison.differences += Self.facts(of: container, from: work)
            await content(
                of: sidecar,
                opened: opened,
                tmdb: work.ref(.tmdb)?.value,
                into: &comparison,
                sources,
                progress
            )
        case (.series, let item?):
            try await compareSeries(
                item,
                sidecar: sidecar,
                opened: opened,
                into: &comparison,
                sources,
                database,
                progress
            )
        case (.season, let own) where own != nil || seriesAbove?.wikidata != nil:
            try await compareSeason(
                of: seriesAbove,
                sidecar: sidecar,
                opened: opened,
                identified: identified[id],
                into: &comparison,
                sources,
                progress
            )
        case (.serial, let item?):
            try await compareSerial(item, opened: opened, into: &comparison, sources, progress)
        case (.episode, _):
            try await compareEpisode(opened, identified: identified, into: &comparison, sources, progress)
        default:
            let through = try await compareThrough(
                opened,
                container: container,
                identified: identified,
                into: &comparison,
                sources
            )
            try await compareEpisodes(
                through,
                in: container,
                missing: false,
                into: &comparison,
                sources,
                progress
            )
        }
        return comparison
    }

    /// The facts Wikidata's item says otherwise: its title, its year where the type has one, and each
    /// provider's id it holds that the sidecar lacks.
    nonisolated static func facts(of container: Container, from work: Wikidata.Work) -> [ReviewWalk.Difference] {
        var differences: [ReviewWalk.Difference] = []
        if work.title != container.title.rawValue, work.title != work.id { differences.append(.title(work.title)) }
        if container.type.hasYear, let year = work.year, year != container.year { differences.append(.year(year)) }
        return differences + missing(work.refs, from: container.externalRefs, item: nil)
    }

    private nonisolated static func missing(
        _ refs: [ExternalRef],
        from held: [ExternalRef],
        item: String?
    ) -> [ReviewWalk.Difference] {
        refs.filter { !held.contains($0) }.map { .reference(item: item, $0) }
    }

    /// The artwork kinds the folder lacks that the images TMDb holds for a record have one for.
    nonisolated static func artwork(
        of record: TMDb.Record,
        held: [String],
        images: TMDb.Images
    ) -> [ReviewWalk.Difference] {
        TMDb.Images.kinds.compactMap { kind in
            let offered = images.offered(for: kind)
            guard !held.contains(kind), let path = offered.first else { return nil }
            return .artwork(kind: kind, path: path, record: record, offered: offered)
        }
    }

    /// A container's content read from TMDb, by the TMDb id its item holds or it carries, and its
    /// differences. Content is offered, not needed: a reading TMDb does not answer reads the facts alone,
    /// and says why there is no content.
    private func content(
        of sidecar: Sidecar,
        opened: OpenedContainer,
        tmdb id: String?,
        seasons: TMDbSeasons? = nil,
        into comparison: inout ReviewWalk.Comparison,
        _ sources: Sources,
        _ progress: @Sendable (StepProgress, ReviewWalk.Comparison) async -> Void
    ) async {
        guard let tmdb = sources.tmdb else { return }
        let container = sidecar.container
        let id = id ?? container.externalRefs.first { $0.provider == .tmdb }?.value
        await progress(StepProgress("Reading TMDb's outline and artwork"), comparison)
        do {
            guard let content = try await Self.content(of: container.type, tmdb: id, seasons: seasons, from: tmdb)
            else {
                return
            }
            comparison.differences += Self.differences(
                of: container,
                attributions: sidecar.attributions,
                artwork: opened.container.artwork,
                from: content,
                today: sources.today
            )
            if !content.episodes.isEmpty { comparison.episodeOutlines = content.episodes }
            if !content.stills.isEmpty { comparison.episodeStills = content.stills }
        } catch let unavailable as TMDb.Unavailable {
            comparison.noContent = unavailable.reason
        } catch {
            comparison.noContent = "TMDb could not be reached."
        }
    }

    /// Whether any container of the silo carries one of the references, itself or through an item: what
    /// covers an episode wherever it was filed, beneath the container, in a breakout or in a duplicate's
    /// home.
    private func covered(_ refs: [ExternalRef], of silo: Silo) async throws -> Bool {
        for ref in refs {
            let held = try await withOperator(silo) {
                try await $0.lookup(provider: ref.provider.rawValue, value: ref.value)
            }
            if !held.isEmpty { return true }
        }
        return false
    }

    /// One step of a reading, asking a question of each item at once, told to `progress` with the
    /// comparison as the step began; the answers there are, in the items' order.
    private func steps<Item: Sendable, Answer: Sendable>(
        _ step: String,
        _ items: [Item],
        _ comparison: ReviewWalk.Comparison,
        _ progress: @Sendable (StepProgress, ReviewWalk.Comparison) async -> Void,
        _ body: @escaping @Sendable (Item) async throws -> Answer?
    ) async throws -> [Answer] {
        await progress(StepProgress(step, of: items.count), comparison)
        return try await Self.concurrently(
            items,
            done: { await progress(StepProgress(step, done: $0, of: items.count), comparison) },
            body
        )
        .compactMap { $0 }
    }

    // swiftlint:disable:next function_parameter_count
    private func compareSeries(
        _ item: String,
        sidecar: Sidecar,
        opened: OpenedContainer,
        into comparison: inout ReviewWalk.Comparison,
        _ sources: Sources,
        _ database: any ContainerDatabase,
        _ progress: @Sendable (StepProgress, ReviewWalk.Comparison) async -> Void
    ) async throws {
        let container = sidecar.container
        let series = try await sources.wikidata.series(item)
        comparison.reading = "Wikidata's item \(item)"
        comparison.differences += Self.facts(of: container, from: series.work)
        let held = try await heldSeasons(
            beneath: container,
            among: series.seasons,
            in: comparison.library,
            of: sources.silo
        )
        let silo = sources.silo
        comparison.differences += try await steps(
            "Looking for Wikidata's seasons in the library",
            series.seasons,
            comparison,
            progress
        ) { season in
            if let (child, suggested) = held[season.id] {
                return ReviewWalk.Difference.heldChild(season, container: child, suggested: suggested)
            }
            let ref = ExternalRef(provider: .wikidata, value: season.id)
            return try await self.covered([ref], of: silo) ? nil : ReviewWalk.Difference.child(season)
        }
        await content(
            of: sidecar,
            opened: opened,
            tmdb: series.work.ref(.tmdb)?.value,
            into: &comparison,
            sources,
            progress
        )
        try await compareSpecials(series.specials, sidecar: sidecar, into: &comparison, sources, database, progress)
    }

    /// The series' specials nothing covers, listed as they are found and then with their suggestions,
    /// and the ones its sidecar declines.
    // swiftlint:disable:next function_parameter_count
    private func compareSpecials(
        _ specials: [Wikidata.Work],
        sidecar: Sidecar,
        into comparison: inout ReviewWalk.Comparison,
        _ sources: Sources,
        _ database: any ContainerDatabase,
        _ progress: @Sendable (StepProgress, ReviewWalk.Comparison) async -> Void
    ) async throws {
        guard !specials.isEmpty else { return }
        let silo = sources.silo
        for episode in specials { comparison.episodeTitles[episode.id] = episode.title }
        comparison.declined = specials.filter { sidecar.declined.contains($0.item) }.map { Special(episode: $0) }
        let held = comparison.differences
        let uncovered = try await steps(
            "Looking for the series' specials in the library",
            specials.filter { !sidecar.declined.contains($0.item) },
            comparison,
            progress
        ) { episode in
            // Covered by its Wikidata id: one sharing another id with an item a library holds is that
            // item's duplicate, to be placed as one.
            try await self.covered([episode.item], of: silo) ? nil : Special(episode: episode)
        }
        // Listed as they are while their suggestions are read.
        comparison.differences = held + uncovered.map(ReviewWalk.Difference.special)
        let listed = comparison
        // The suggestions a draft's specials get, read against the series as the library holds it.
        let pool = DraftTree(
            library: comparison.library,
            item: Wikidata.Item(.series, comparison.container),
            creating: ContainerDraft.Creating(),
            containers: [sidecar.container],
            top: sidecar.container.id,
            specials: uncovered
        )
        comparison.suggestions = try await suggest(
            for: pool,
            of: silo,
            from: database,
            progress: { await progress($0, listed) }
        )
    }

    /// The specials of the series a walk is beneath, read as a comparison of the series holding them
    /// alone: what sits beside every stop of a walk rooted below the series.
    public func specials(
        of series: String,
        in library: String,
        of silo: Silo,
        from database: any ContainerDatabase,
        wikidata: any WikidataSource,
        progress: @escaping @Sendable (StepProgress, ReviewWalk.Comparison) async -> Void = { _, _ in }
    ) async throws -> ReviewWalk.Comparison {
        let opened = try await open(container: series, in: library, of: silo)
        let sidecar = try SidecarFile.sidecar(from: opened.sidecar)
        var comparison = ReviewWalk.Comparison(
            library: library,
            container: series,
            title: sidecar.container.displayTitle,
            opened: opened
        )
        guard let item = sidecar.container.externalRefs.first(where: { $0.provider == .wikidata })?.value else {
            return comparison
        }
        comparison.reading = "Wikidata's item \(item)"
        let sources = Sources(silo: silo, wikidata: wikidata, tmdb: nil, today: .today)
        let read = try await wikidata.series(item)
        try await compareSpecials(read.specials, sidecar: sidecar, into: &comparison, sources, database, progress)
        return comparison
    }

    /// A season's facts and what it holds, read through the series above it, which lists its seasons. A
    /// season carrying no Wikidata id matches nothing there: the series' seasons are offered for the
    /// operator to say which it is, and, once said, it is read as that season and offered its id. A
    /// season Wikidata models as serials lists each serial as a child, held beneath it or missing, and
    /// its episodes as episodes.
    // swiftlint:disable:next function_parameter_count
    private func compareSeason(
        of series: Above?,
        sidecar: Sidecar,
        opened: OpenedContainer,
        identified: String?,
        into comparison: inout ReviewWalk.Comparison,
        _ sources: Sources,
        _ progress: @Sendable (StepProgress, ReviewWalk.Comparison) async -> Void
    ) async throws {
        let container = sidecar.container
        let own = container.externalRefs.first { $0.provider == .wikidata }?.value
        guard let item = own ?? identified else {
            guard let series, let item = series.wikidata else { return }
            let seasons = try await sources.wikidata.series(item).seasons
            comparison.differences = [
                .unmatchedSeason(
                    series: item,
                    seasons: seasons,
                    suggested: Self.suggestedSeason(of: container, among: seasons)?.id
                )
            ]
            return
        }
        let season = try await sources.wikidata.season(item)
        comparison.reading = "Wikidata's item \(item)"
        // The id it is said to be offered first, and not again among Wikidata's others.
        var carrying = container
        if own == nil {
            comparison.differences.append(.reference(item: nil, season.work.item))
            carrying.externalRefs.append(season.work.item)
        }
        comparison.differences += Self.facts(of: carrying, from: season.work)
        if let tmdb = sources.tmdb {
            let seasons = try? await Self.tmdbSeasons(of: series?.tmdb, from: tmdb)
            await content(
                of: sidecar,
                opened: opened,
                tmdb: season.work.ref(.tmdb)?.value,
                seasons: seasons,
                into: &comparison,
                sources,
                progress
            )
        }
        let serials = season.members.filter { if case .serial = $0 { true } else { false } }
        if !serials.isEmpty {
            let held = try await heldChildren(
                holding: serials.map(\.work.id),
                beneath: container,
                in: comparison.library,
                of: sources.silo
            )
            let silo = sources.silo
            comparison.differences += try await steps(
                "Looking for Wikidata's serials in the library",
                Array(serials.enumerated()),
                comparison,
                progress
            ) { index, serial in
                let summary = Wikidata.Summary(serial, ordinal: index + 1)
                if let child = held[serial.work.id] {
                    return ReviewWalk.Difference.heldChild(summary, container: child, suggested: false)
                }
                return try await self.covered([serial.work.item], of: silo) ? nil : ReviewWalk.Difference.child(summary)
            }
        }
        let episodes = season.members.compactMap { if case .episode(let work) = $0 { work } else { nil } }
        try await compareEpisodes(episodes, in: container, missing: true, into: &comparison, sources, progress)
    }

    /// A serial's facts and its parts, read from Wikidata's item for it, and TMDb's overviews of its
    /// season's episodes, which its missing parts are drafted with.
    private func compareSerial(
        _ item: String,
        opened: OpenedContainer,
        into comparison: inout ReviewWalk.Comparison,
        _ sources: Sources,
        _ progress: @Sendable (StepProgress, ReviewWalk.Comparison) async -> Void
    ) async throws {
        let container = try SidecarFile.sidecar(from: opened.sidecar).container
        let serial = try await sources.wikidata.serial(item)
        comparison.reading = "Wikidata's item \(item)"
        comparison.differences += Self.facts(of: container, from: serial.work)
        if let tmdb = sources.tmdb {
            let episodes = try? await tmdbEpisodes(of: opened, container, from: tmdb, of: sources.silo)
            comparison.episodeOutlines = episodes?.outlines
            comparison.episodeStills = episodes?.stills
        }
        try await compareEpisodes(serial.parts, in: container, missing: true, into: &comparison, sources, progress)
    }

    /// An episode's container read against Wikidata's item for the episode: its title, its references,
    /// its first date, cast and crew, and its outline and `thumb` against TMDb's, read through its
    /// season. One carrying no Wikidata id is read as the episode of what it is beneath that carries one
    /// of the other ids it carries, and offered Wikidata's id.
    private func compareEpisode(
        _ opened: OpenedContainer,
        identified: [String: String],
        into comparison: inout ReviewWalk.Comparison,
        _ sources: Sources,
        _ progress: @Sendable (StepProgress, ReviewWalk.Comparison) async -> Void
    ) async throws {
        let sidecar = try SidecarFile.sidecar(from: opened.sidecar)
        let container = sidecar.container
        var carrying = container
        let work: Wikidata.Work
        if let own = container.externalRefs.first(where: { $0.provider == .wikidata })?.value {
            guard let read = try await sources.wikidata.episodes([own]).first else {
                throw Wikidata.Unavailable.notThere(own)
            }
            work = read
            comparison.reading = "Wikidata's item \(own)"
        } else {
            let through = try await compareThrough(
                opened,
                container: container,
                identified: identified,
                into: &comparison,
                sources
            )
            guard let found = through.first(where: { Self.carries(container.externalRefs, $0) }) else {
                throw NoReading(
                    reason:
                        "\(container.displayTitle) carries no Wikidata id, and none of the ids Wikidata holds for the episodes it is read through"
                )
            }
            work = found
            comparison.differences.append(.reference(item: nil, found.item))
            carrying.externalRefs.append(found.item)
        }
        comparison.differences += Self.facts(of: carrying, from: work) + Self.credits(of: container, from: work)
        guard let tmdb = sources.tmdb, let id = work.ref(.tmdb)?.value, let record = Int(id) else { return }
        await progress(StepProgress("Reading TMDb's outline and still"), comparison)
        do {
            guard let episodes = try await tmdbEpisodes(of: opened, container, from: tmdb, of: sources.silo) else {
                return
            }
            comparison.differences += Self.differences(
                of: container,
                attributions: sidecar.attributions,
                artwork: opened.container.artwork,
                from: await episodes.content(of: record, from: tmdb),
                today: sources.today
            )
        } catch let unavailable as TMDb.Unavailable {
            comparison.noContent = unavailable.reason
        } catch {
            comparison.noContent = "TMDb could not be reached."
        }
    }

    /// The episodes a container with no Wikidata id of its own is read against: those of the season or
    /// serial above it, a series above it's specials, or, nothing above it carrying a Wikidata id, the
    /// items its entries' Wikidata ids name, as a breakout's are.
    private func compareThrough(
        _ opened: OpenedContainer,
        container: Container,
        identified: [String: String],
        into comparison: inout ReviewWalk.Comparison,
        _ sources: Sources
    ) async throws -> [Wikidata.Work] {
        var parent = opened.container.container.parent
        while let id = parent {
            let above = try await open(container: id, in: opened.container.library, of: sources.silo)
            let held = try SidecarFile.sidecar(from: above.sidecar).container
            let item = held.externalRefs.first { $0.provider == .wikidata }?.value
            switch (held.type, item ?? (held.type == .season ? identified[id] : nil)) {
            case (.season, let item?):
                let season = try await sources.wikidata.season(item)
                comparison.reading = "through \(held.displayTitle), Wikidata's item \(item)"
                return season.members.flatMap { member -> [Wikidata.Work] in
                    switch member {
                    case .episode(let work): [work]
                    case .serial(let serial): serial.parts
                    }
                }
            case (.season, nil):
                throw NoReading(
                    reason:
                        "\(held.displayTitle) above it carries no Wikidata id: say which of Wikidata's seasons it is when the walk reaches it, and this is read through it"
                )
            case (.serial, let item?):
                comparison.reading = "through \(held.displayTitle), Wikidata's item \(item)"
                return try await sources.wikidata.serial(item).parts
            case (.series, let item?):
                comparison.reading = "through \(held.displayTitle), Wikidata's item \(item)"
                return try await sources.wikidata.series(item).specials
            default:
                parent = above.container.container.parent
            }
        }
        // Nothing above it is Wikidata's: a breakout, whose entries are each an item of Wikidata's.
        let items = (container.sequences.flatMap(\.items) + container.extras).compactMap { entry in
            entry.externalRefs.first { $0.provider == .wikidata }?.value
        }
        guard !items.isEmpty else {
            throw NoReading(
                reason:
                    "\(container.displayTitle) carries no Wikidata id, nothing above it does, and none of its items does"
            )
        }
        comparison.reading = "through the Wikidata items its entries carry"
        return try await sources.wikidata.episodes(items)
    }

    /// Whether an entry is an episode: whether it carries any of the ids Wikidata holds for it.
    nonisolated static func carries(_ entry: Entry, _ episode: Wikidata.Work) -> Bool {
        carries(entry.externalRefs, episode)
    }

    /// Whether references are an episode's: whether they hold any of the ids Wikidata holds for it.
    nonisolated static func carries(_ refs: [ExternalRef], _ episode: Wikidata.Work) -> Bool {
        refs.contains(episode.item) || refs.contains { episode.refs.contains($0) }
    }

    /// The entries' differences from Wikidata's episodes: the other ids Wikidata holds for each one the
    /// container carries, items both hold in another order, and, when the container is read as itself,
    /// each episode nothing covers. An episode held as a container beneath it is that container's: offered
    /// its ids at its own stop, and in its place in the order. What the container holds that is none of
    /// the episodes is listed as held only.
    // swiftlint:disable:next function_parameter_count
    private func compareEpisodes(
        _ episodes: [Wikidata.Work],
        in container: Container,
        missing: Bool,
        into comparison: inout ReviewWalk.Comparison,
        _ sources: Sources,
        _ progress: @Sendable (StepProgress, ReviewWalk.Comparison) async -> Void
    ) async throws {
        for episode in episodes { comparison.episodeTitles[episode.id] = episode.title }
        comparison.episodeOrder = episodes.map(\.id)
        let entries = container.sequences.flatMap(\.items) + container.extras
        let library = comparison.library
        let silo = sources.silo
        let children = try await Self.concurrently(container.childContainerIDs) { child in
            let opened = try await self.open(container: child.value, in: library, of: silo)
            return (id: child.value, container: try SidecarFile.sidecar(from: opened.sidecar).container)
        }
        // An episode container carries its ids itself, and is what its parent's entry names.
        let own = Dictionary(
            children.filter { $0.container.type == .episode }.map { ($0.id, $0.container.externalRefs) },
            uniquingKeysWith: { first, _ in first }
        )
        @Sendable func refs(of entry: Entry) -> [ExternalRef] {
            entry.externalRefs + (entry.childContainer.flatMap { own[$0.value] } ?? [])
        }
        let beneath = children.flatMap { $0.container.sequences.flatMap(\.items) + $0.container.extras }
        let found: [[ReviewWalk.Difference]] = try await steps(
            "Looking for Wikidata's episodes in the library",
            Array(episodes.indices),
            comparison,
            progress
        ) { index in
            let episode = episodes[index]
            if let entry = entries.first(where: { Self.carries(refs(of: $0), episode) }) {
                guard entry.childContainer == nil, let item = entry.id?.value else { return nil }
                return Self.missing([episode.item] + episode.refs, from: entry.externalRefs, item: item)
            }
            // An item of a container beneath is offered its ids at that container's own stop.
            if beneath.contains(where: { Self.carries($0, episode) }) { return nil }
            guard missing, try await !self.covered([episode.item], of: silo) else { return nil }
            return [.episode(episode, after: index > 0 ? episodes[index - 1].item : nil)]
        }
        comparison.differences += Self.deduplicated(found.flatMap { $0 })
        var held: [String: String] = [:]
        for episode in episodes {
            if let child = own.first(where: { Self.carries($0.value, episode) })?.key { held[episode.id] = child }
        }
        comparison.episodeContainers = held.isEmpty ? nil : held
        if missing { comparison.heldChildren = children.map { Self.heldChild($0.id, $0.container, among: episodes) } }
        for sequence in container.sequences {
            let carried = sequence.items.filter { entry in episodes.contains { Self.carries(refs(of: entry), $0) } }
            let sorted = carried.sorted { lhs, rhs in
                (episodes.firstIndex { Self.carries(refs(of: lhs), $0) } ?? 0)
                    < (episodes.firstIndex { Self.carries(refs(of: rhs), $0) } ?? 0)
            }
            if sorted != carried {
                comparison.differences.append(.order(sequence: sequence.id, items: sorted.compactMap { $0.id?.value }))
            }
        }
        comparison.heldOnly = entries.compactMap { entry in
            guard entry.childContainer == nil, entry.reference == nil,
                !episodes.contains(where: { Self.carries(entry, $0) })
            else { return nil }
            return entry.title.map { "\(entry.id?.value ?? ""): \($0)" } ?? entry.id?.value
        }
    }

    /// A container held beneath one read, placed by the first of the episodes read that it is or holds.
    private nonisolated static func heldChild(
        _ id: String,
        _ container: Container,
        among episodes: [Wikidata.Work]
    ) -> ReviewWalk.HeldChild {
        let entries = container.sequences.flatMap(\.items) + container.extras
        let first = episodes.firstIndex { episode in
            carries(container.externalRefs, episode) || entries.contains { carries($0, episode) }
        }
        return ReviewWalk.HeldChild(
            id: id,
            title: container.displayTitle,
            type: container.type,
            typeLabel: container.typeLabel,
            position: first.map { $0 + 1 }
        )
    }

    /// The differences in the order found, each once: two episodes carried by one entry offer its ids once.
    private nonisolated static func deduplicated(_ differences: [ReviewWalk.Difference]) -> [ReviewWalk.Difference] {
        var seen: Set<String> = []
        return differences.filter { seen.insert($0.id).inserted }
    }

    /// The containers held beneath one that carry one of the Wikidata ids given, by that id.
    private func heldChildren(
        holding items: [String],
        beneath container: Container,
        in library: String,
        of silo: Silo
    ) async throws -> [String: String] {
        let found: [(String, String)?] = try await Self.concurrently(container.childContainerIDs) { child in
            let opened = try await self.open(container: child.value, in: library, of: silo)
            let held = try SidecarFile.sidecar(from: opened.sidecar).container
            let item = held.externalRefs.first { $0.provider == .wikidata && items.contains($0.value) }
            return item.map { ($0.value, child.value) }
        }
        return Dictionary(found.compactMap { $0 }) { first, _ in first }
    }

    /// The nearest container above one of a type.
    func above(_ opened: OpenedContainer, ofType type: ContainerType, of silo: Silo) async throws -> Above? {
        var parent = opened.container.container.parent
        while let id = parent {
            let above = try await open(container: id, in: opened.container.library, of: silo)
            let held = try SidecarFile.sidecar(from: above.sidecar).container
            if held.type == type { return Above(id: id, container: held) }
            parent = above.container.container.parent
        }
        return nil
    }

    /// Which of Wikidata's seasons a held season carrying no Wikidata id is suggested to be: the one
    /// Wikidata gives its title as a label, or the one whose number its title gives (`Season 13`,
    /// `Series 13`).
    nonisolated static func suggestedSeason(
        of season: Container,
        among seasons: [Wikidata.Summary]
    ) -> Wikidata.Summary? {
        let title = season.title.rawValue
        if let named = seasons.first(where: { $0.title.caseInsensitiveCompare(title) == .orderedSame }) { return named }
        guard let number = seasonNumber(in: title) else { return nil }
        return seasons.first { $0.ordinal == number }
    }

    /// The number a season's title gives it, as `Season 13` or `Series 13` does.
    nonisolated static func seasonNumber(in title: String) -> Int? {
        let words = title.split(separator: " ")
        guard words.count == 2, ["season", "series"].contains(words[0].lowercased()) else { return nil }
        return Int(words[1])
    }

    /// The seasons a series holds beneath it, by the season of Wikidata's each is or, carrying no
    /// Wikidata id, is suggested to be: the containers its walk stops at whatever is chosen, so the
    /// series offers none of them as missing.
    private func heldSeasons(
        beneath series: Container,
        among seasons: [Wikidata.Summary],
        in library: String,
        of silo: Silo
    ) async throws -> [String: (String, Bool)] {
        let matched: [(String, (String, Bool))?] = try await Self.concurrently(series.childContainerIDs) { child in
            let opened = try await self.open(container: child.value, in: library, of: silo)
            let held = try SidecarFile.sidecar(from: opened.sidecar).container
            guard held.type == .season else { return nil }
            if let own = held.externalRefs.first(where: { $0.provider == .wikidata })?.value,
                seasons.contains(where: { $0.id == own })
            {
                return (own, (child.value, false))
            }
            return Self.suggestedSeason(of: held, among: seasons).map { ($0.id, (child.value, true)) }
        }
        return Dictionary(matched.compactMap { $0 }) { first, _ in first }
    }

    // MARK: Taking

    nonisolated static func add(_ ref: ExternalRef, toItem item: String, in container: inout Container) {
        func adding(_ entry: Entry) -> Entry {
            guard entry.id?.value == item else { return entry }
            switch entry {
            case .leaf(var leaf):
                if !leaf.externalRefs.contains(ref) { leaf.externalRefs.append(ref) }
                return .leaf(leaf)
            case .child(var child):
                if !child.externalRefs.contains(ref) { child.externalRefs.append(ref) }
                return .child(child)
            case .ref: return entry
            }
        }
        for index in container.sequences.indices {
            container.sequences[index].items = container.sequences[index].items.map(adding)
        }
        container.extras = container.extras.map(adding)
    }

    /// What an entry goes after: the entry carrying a ref, or the one naming a container.
    enum Anchor {
        case ref(ExternalRef)
        case child(ContainerID)
    }

    /// An entry put after the one its anchor names, or last when nothing does.
    nonisolated static func insert(_ entry: Entry, after anchor: Anchor?, into container: inout Container) {
        if let anchor {
            for index in container.sequences.indices {
                let position = container.sequences[index].items.firstIndex { held in
                    switch anchor {
                    case .ref(let ref): held.externalRefs.contains(ref)
                    case .child(let id): held.childContainer == id
                    }
                }
                if let position {
                    container.sequences[index].items.insert(entry, at: position + 1)
                    return
                }
            }
        }
        DraftTree.insert(entry, into: &container, sequence: nil, at: nil)
    }

    /// A sequence's items carrying Wikidata's ids put in the order given, each in a place one of them
    /// held, the others where they stood.
    nonisolated static func reorder(_ sequence: String?, to items: [String], in container: inout Container) {
        guard let index = container.sequences.firstIndex(where: { $0.id == sequence }) else { return }
        var queue = items.compactMap { id in container.sequences[index].items.first { $0.id?.value == id } }
        let moving = Set(items)
        container.sequences[index].items = container.sequences[index].items.map { entry in
            guard let id = entry.id?.value, moving.contains(id), !queue.isEmpty else { return entry }
            return queue.removeFirst()
        }
    }
}
