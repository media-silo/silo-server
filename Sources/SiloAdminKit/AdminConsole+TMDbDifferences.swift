// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import SiloClient
import SmdKit
import SmdSidecar

// MARK: - Differences from TMDb

/// How a container a library holds differs from TMDb's record of it, each difference the operator's to
/// take or leave. Nothing the library holds and TMDb lacks is offered for removal: TMDb models no cuts,
/// features or extras, so its silence about one says nothing. The console reads TMDb only when the
/// operator opens a container's differences, and follows nothing. `Tmdb.md`, *Differences*.
extension AdminConsole {
    /// One way a held container differs from TMDb's reading of it.
    public enum TMDbDifference: Hashable, Sendable, Identifiable, Codable {
        case title(String)
        case year(Int)
        /// TMDb's overview, attributed to the record it came from when it is taken.
        case outline(String, record: String)
        /// A provider's id TMDb holds that the sidecar lacks: for the container, or for one of its items.
        case reference(item: String?, ExternalRef)
        /// An episode no item of the library carries, to go after the one it follows at TMDb.
        case episode(TMDb.Episode, after: ExternalRef?)
        /// A season no container beneath the series carries, drafted from TMDb beneath it when taken.
        case season(TMDb.SeasonSummary)
        /// A season of TMDb's the series holds beneath it: by its TMDb id, or, `suggested`, a season carrying
        /// none that its title or episodes suggest is this one. Shown among the children, and a stop of the
        /// walk whatever is chosen, so never chosen itself.
        case heldSeason(TMDb.SeasonSummary, container: String, suggested: Bool)
        /// A season beneath a series of TMDb's that carries no TMDb id, so matches nothing there: TMDb's
        /// seasons, for the operator to say which it is, and the one its title or episodes suggest.
        case unmatchedSeason(series: Int, seasons: [TMDb.SeasonSummary], suggested: Int?)
        /// Items both hold, at the same level, in TMDb's order rather than the sidecar's.
        case order(sequence: String?, items: [String])
        /// An artwork kind the folder has no file for, and the image TMDb offers for it.
        case artwork(kind: String, path: String, record: TMDb.Record)
        /// A special of the series nothing covers, to be placed or declined as a draft's specials are.
        case special(Special)

        public var id: String {
            switch self {
            case .title: "title"
            case .year: "year"
            case .outline: "outline"
            case .reference(let item, let ref): "ref:\(item ?? ""):\(ref.provider):\(ref.value)"
            case .episode(let episode, _): "episode:\(episode.id)"
            case .season(let season): "season:\(season.id)"
            case .heldSeason(_, let container, _): "held:\(container)"
            case .unmatchedSeason: "unmatched"
            case .order(let sequence, _): "order:\(sequence ?? "")"
            case .artwork(let kind, _, _): "artwork:\(kind)"
            case .special(let special): "special:\(special.id)"
            }
        }
    }

    /// A held container read against TMDb: what was read, the differences, what the library holds that
    /// TMDb has nothing for, the specials it declines, and what each uncovered special is suggested for.
    public struct TMDbComparison: Hashable, Sendable, Codable {
        public var library: String
        public var container: String
        public var title: String
        /// What was read, in words: the container's own record, or the one it was read through.
        public var reading: String
        /// The series the episodes are TMDb's of, for their other ids.
        public var series: Int?
        public var differences: [TMDbDifference]
        /// Items the library holds that TMDb's record has nothing for: shown, and never offered for removal.
        public var heldOnly: [String]
        public var declined: [Special]
        public var suggestions: [Int: SpecialSuggestion]
        /// TMDb's title for each episode compared, by TMDb id: shown, and stored nowhere.
        public var episodeTitles: [String: String]
        /// How long each episode compared runs, in minutes, by TMDb id, for suggesting an omnibus.
        public var runtimes: [String: Int] = [:]
        /// The container as the reading found it, which its stop's edit is based on.
        public var opened: OpenedContainer
        /// The containers held beneath it, in the order it holds them, read when its missing episodes are:
        /// shown among its children, each one its missing episodes may be added to. Absent from a reading
        /// kept before they were read.
        public var heldChildren: [HeldChild]?
    }

    /// A container held beneath one read against TMDb, as the children of the one read show it.
    public struct HeldChild: Hashable, Sendable, Codable, Identifiable {
        public var id: String
        public var title: String
        public var type: ContainerType
        public var typeLabel: String?
        /// TMDb's number for the first of its episodes it holds, which places it among the missing ones;
        /// nil when it holds none of them.
        public var number: Int?

        public init(id: String, title: String, type: ContainerType, typeLabel: String? = nil, number: Int? = nil) {
            self.id = id
            self.title = title
            self.type = type
            self.typeLabel = typeLabel
            self.number = number
        }
    }

    /// Why a container cannot be read against TMDb: it carries no reference TMDb can be asked by,
    /// itself, above it, or through its items.
    public struct NoTMDbReading: Error, Hashable {
        public var reason: String
    }

    /// Reads a held container against TMDb. A container with no `tmdb` reference of its own is read
    /// through the nearest container above it that has one, or, failing that, through the series its
    /// items' other ids say they are episodes of at TMDb; its differences are then about its entries.
    /// `progress` is told each step as the reading goes, with the comparison as far as it has got.
    public func compare(
        _ id: String,
        in library: String,
        of silo: Silo,
        from database: any ContainerDatabase,
        tmdb: any TMDbSource,
        identified: [String: Int] = [:],
        progress: @escaping @Sendable (TMDbProgress, TMDbComparison) async -> Void = { _, _ in }
    ) async throws -> TMDbComparison {
        let opened = try await open(container: id, in: library, of: silo)
        let sidecar = try SidecarFile.sidecar(from: opened.sidecar)
        let container = sidecar.container
        var comparison = TMDbComparison(
            library: library,
            container: id,
            title: container.displayTitle,
            reading: "",
            differences: [],
            heldOnly: [],
            declined: [],
            suggestions: [:],
            episodeTitles: [:],
            opened: opened
        )
        await progress(TMDbProgress("Reading TMDb"), comparison)
        let own = container.externalRefs.first { $0.provider == .tmdb }.flatMap { Int($0.value) }
        let seriesOfSeason = container.type == .season ? try await seriesAbove(opened, of: silo) : nil
        switch (container.type, own) {
        case (.movie, let number?), (.collection, let number?):
            let record = TMDb.Record(container.type == .movie ? .movie : .collection, number)
            try await compareRecord(
                record,
                container: container,
                artwork: opened.container.artwork,
                into: &comparison,
                tmdb: tmdb,
                progress: progress
            )
        case (.series, let series?):
            try await compareSeries(
                series,
                sidecar: sidecar,
                opened: opened,
                into: &comparison,
                of: silo,
                database: database,
                tmdb: tmdb,
                progress: progress
            )
        case (.season, let own) where own != nil || seriesOfSeason != nil:
            try await compareSeason(
                of: seriesOfSeason,
                container: container,
                identified: identified[id],
                into: &comparison,
                of: silo,
                tmdb: tmdb,
                progress: progress
            )
        default:
            try await compareThrough(
                opened,
                container: container,
                identified: identified,
                into: &comparison,
                of: silo,
                tmdb: tmdb,
                progress: progress
            )
        }
        return comparison
    }

    /// A container with no record of its own: its entries, read against the episodes of what it is read
    /// through.
    private func compareThrough(
        _ opened: OpenedContainer,
        container: Container,
        identified: [String: Int],
        into comparison: inout TMDbComparison,
        of silo: Silo,
        tmdb: any TMDbSource,
        progress: @Sendable (TMDbProgress, TMDbComparison) async -> Void
    ) async throws {
        let (episodes, series, reading) = try await readingThrough(
            opened,
            container: container,
            identified: identified,
            of: silo,
            tmdb: tmdb
        )
        comparison.reading = reading
        comparison.series = series
        try await compareEpisodes(
            episodes,
            of: series,
            in: container,
            missing: false,
            into: &comparison,
            of: silo,
            tmdb: tmdb,
            progress: progress
        )
    }

    /// A movie's or a collection's fields, the ids TMDb holds that it lacks, and its artwork.
    private func compareRecord(
        _ record: TMDb.Record,
        container: Container,
        artwork held: [String],
        into comparison: inout TMDbComparison,
        tmdb: any TMDbSource,
        progress: @Sendable (TMDbProgress, TMDbComparison) async -> Void
    ) async throws {
        if record.kind == .movie {
            let movie = try await tmdb.movie(record.id)
            comparison.reading = "TMDb's movie \(record.id)"
            comparison.differences += Self.fields(
                of: container,
                title: movie.title,
                year: movie.year,
                overview: movie.overview,
                record: record.id
            )
            comparison.differences += Self.missing(movie.externalIDs.refs, from: container.externalRefs, item: nil)
        } else {
            let collection = try await tmdb.collection(record.id)
            comparison.reading = "TMDb's collection \(record.id)"
            comparison.differences += Self.fields(
                of: container,
                title: collection.name,
                year: nil,
                overview: collection.overview,
                record: record.id
            )
        }
        await progress(TMDbProgress("Reading TMDb's artwork"), comparison)
        comparison.differences += try await artwork(of: record, held: held, tmdb: tmdb)
    }

    /// A season's fields and its episodes, read through the series above it, which TMDb numbers it in. A
    /// season carrying no TMDb id matches nothing there: TMDb's seasons are offered for the operator to say
    /// which it is, and, once said, it is read as that season and offered its id.
    private func compareSeason(
        of series: Int?,
        container: Container,
        identified: Int?,
        into comparison: inout TMDbComparison,
        of silo: Silo,
        tmdb: any TMDbSource,
        progress: @Sendable (TMDbProgress, TMDbComparison) async -> Void
    ) async throws {
        guard let series else {
            throw NoTMDbReading(reason: "the season carries TMDb's id, but no series above it does")
        }
        let own = container.externalRefs.first { $0.provider == .tmdb }
        let seasons = try await tmdb.series(series).seasons
        guard let summary = Self.season(of: container, identified: identified, among: seasons) else {
            if let own { throw NoTMDbReading(reason: "TMDb's series \(series) has no season \(own.value)") }
            comparison.series = series
            comparison.differences = [
                .unmatchedSeason(
                    series: series,
                    seasons: seasons.filter { $0.number != 0 },
                    suggested: try await suggestedSeason(
                        of: container,
                        among: seasons,
                        series: series,
                        in: comparison.library,
                        of: silo,
                        tmdb: tmdb
                    )?.id
                )
            ]
            return
        }
        let record = try await tmdb.season(summary.number, of: series)
        comparison.reading = "\(record.name) of TMDb's series \(series)"
        comparison.series = series
        if own == nil {
            comparison.differences.append(
                .reference(item: nil, ExternalRef(provider: .tmdb, value: String(summary.id)))
            )
        }
        comparison.differences += Self.fields(
            of: container,
            title: record.name,
            year: record.year,
            overview: record.overview,
            record: summary.id
        )
        try await compareEpisodes(
            record.episodes,
            of: series,
            in: container,
            missing: true,
            into: &comparison,
            of: silo,
            tmdb: tmdb,
            progress: progress
        )
    }

    /// The fields TMDb's record says otherwise: its title, its year where the type has one, and its
    /// overview, which is attributed when taken.
    private nonisolated static func fields(
        of container: Container,
        title: String,
        year: Int?,
        overview: String?,
        record: Int
    ) -> [TMDbDifference] {
        var differences: [TMDbDifference] = []
        if title != container.title.rawValue { differences.append(.title(title)) }
        if container.type.hasYear, let year, year != container.year { differences.append(.year(year)) }
        if let overview, !overview.isEmpty, overview != container.outline {
            differences.append(.outline(overview, record: String(record)))
        }
        return differences
    }

    private nonisolated static func missing(
        _ refs: [ExternalRef],
        from held: [ExternalRef],
        item: String?
    ) -> [TMDbDifference] {
        refs.filter { !held.contains($0) }.map { .reference(item: item, $0) }
    }

    /// The artwork kinds the folder lacks that TMDb has an image for.
    private func artwork(of record: TMDb.Record, held: [String], tmdb: any TMDbSource) async throws -> [TMDbDifference]
    {
        let images = try await tmdb.images(of: record)
        return ["poster", "fanart", "logo"].compactMap { kind in
            guard !held.contains(kind), let path = images.offered(for: kind).first else { return nil }
            return .artwork(kind: kind, path: path, record: record)
        }
    }

    /// Whether any container of the silo carries a reference, itself or through an item: what covers a
    /// TMDb id wherever it was filed, beneath the container, in a breakout or in a duplicate's home.
    private func covered(_ ref: ExternalRef, of silo: Silo) async throws -> Bool {
        !(try await withOperator(silo) { try await $0.lookup(provider: ref.provider.rawValue, value: ref.value) })
            .isEmpty
    }

    /// One step of a reading, asking a question of each item at once, told to `progress` with the
    /// comparison as the step began; the answers there are, in the items' order.
    private func steps<Item: Sendable, Answer: Sendable>(
        _ step: String,
        _ items: [Item],
        _ comparison: TMDbComparison,
        _ progress: @Sendable (TMDbProgress, TMDbComparison) async -> Void,
        _ body: @escaping @Sendable (Item) async throws -> Answer?
    ) async throws -> [Answer] {
        await progress(TMDbProgress(step, of: items.count), comparison)
        return try await Self.concurrently(
            items,
            done: { await progress(TMDbProgress(step, done: $0, of: items.count), comparison) },
            body
        )
        .compactMap { $0 }
    }

    private func compareSeries(
        _ series: Int,
        sidecar: Sidecar,
        opened: OpenedContainer,
        into comparison: inout TMDbComparison,
        of silo: Silo,
        database: any ContainerDatabase,
        tmdb: any TMDbSource,
        progress: @Sendable (TMDbProgress, TMDbComparison) async -> Void
    ) async throws {
        let container = sidecar.container
        let record = try await tmdb.series(series)
        comparison.reading = "TMDb's series \(series)"
        comparison.series = series
        comparison.differences += Self.fields(
            of: container,
            title: record.name,
            year: record.year,
            overview: record.overview,
            record: series
        )
        comparison.differences += Self.missing(record.externalIDs.refs, from: container.externalRefs, item: nil)
        let seasons = record.seasons.filter { $0.number != 0 }
        let held = try await heldSeasons(
            beneath: container,
            among: seasons,
            series: series,
            in: comparison.library,
            of: silo,
            tmdb: tmdb
        )
        comparison.differences += try await steps(
            "Looking for TMDb's seasons in the library",
            seasons,
            comparison,
            progress
        ) { season in
            if let (child, suggested) = held[season.id] {
                return TMDbDifference.heldSeason(season, container: child, suggested: suggested)
            }
            let ref = ExternalRef(provider: .tmdb, value: String(season.id))
            return try await self.covered(ref, of: silo) ? nil : TMDbDifference.season(season)
        }
        await progress(TMDbProgress("Reading TMDb's artwork"), comparison)
        comparison.differences += try await artwork(
            of: TMDb.Record(.series, series),
            held: opened.container.artwork,
            tmdb: tmdb
        )
        guard record.seasons.contains(where: { $0.number == 0 }) else { return }
        try await compareSpecials(
            of: series,
            sidecar: sidecar,
            into: &comparison,
            of: silo,
            database: database,
            tmdb: tmdb,
            progress: progress
        )
    }

    /// The series' specials nothing covers, listed as they are found and then with their suggestions,
    /// and the ones its sidecar declines.
    private func compareSpecials(
        of series: Int,
        sidecar: Sidecar,
        into comparison: inout TMDbComparison,
        of silo: Silo,
        database: any ContainerDatabase,
        tmdb: any TMDbSource,
        progress: @Sendable (TMDbProgress, TMDbComparison) async -> Void
    ) async throws {
        await progress(TMDbProgress("Reading TMDb's specials"), comparison)
        let specials = try await tmdb.season(0, of: series).episodes
        for episode in specials { comparison.episodeTitles[String(episode.id)] = episode.title }
        comparison.declined = specials.filter { sidecar.declined.contains($0.ref) }.map { Special(episode: $0) }
        let held = comparison.differences
        let uncovered = try await steps(
            "Looking for TMDb's specials in the library",
            specials.filter { !sidecar.declined.contains($0.ref) },
            comparison,
            progress
        ) { episode in try await self.covered(episode.ref, of: silo) ? nil : Special(episode: episode) }
        // Listed as they are while their suggestions are read, which is most of a long series' reading.
        comparison.differences = held + uncovered.map(TMDbDifference.special)
        let listed = comparison
        // The suggestions a draft's specials get, read against the series as the library holds it.
        let pool = TMDbTree(
            library: comparison.library,
            record: TMDb.Record(.series, series),
            creating: ContainerDraft.Creating(),
            containers: [sidecar.container],
            top: sidecar.container.id,
            specials: uncovered
        )
        let (suggested, suggestions) = try await self.suggestions(
            for: pool,
            of: silo,
            from: database,
            tmdb: tmdb,
            progress: { await progress($0, listed) }
        )
        comparison.differences = held + suggested.specials.map(TMDbDifference.special)
        comparison.suggestions = suggestions
    }

    /// The specials of the series a walk is beneath, read as a comparison of the series holding them
    /// alone: what sits beside every stop of a walk rooted below the series.
    public func specials(
        of series: String,
        in library: String,
        of silo: Silo,
        from database: any ContainerDatabase,
        tmdb: any TMDbSource,
        progress: @escaping @Sendable (TMDbProgress, TMDbComparison) async -> Void = { _, _ in }
    ) async throws -> TMDbComparison {
        let opened = try await open(container: series, in: library, of: silo)
        let sidecar = try SidecarFile.sidecar(from: opened.sidecar)
        var comparison = TMDbComparison(
            library: library,
            container: series,
            title: sidecar.container.displayTitle,
            reading: "",
            differences: [],
            heldOnly: [],
            declined: [],
            suggestions: [:],
            episodeTitles: [:],
            opened: opened
        )
        let tmdbRef = sidecar.container.externalRefs.first { $0.provider == .tmdb }
        guard let number = tmdbRef.flatMap({ Int($0.value) }) else { return comparison }
        comparison.reading = "TMDb's series \(number)"
        comparison.series = number
        guard try await tmdb.series(number).seasons.contains(where: { $0.number == 0 }) else { return comparison }
        try await compareSpecials(
            of: number,
            sidecar: sidecar,
            into: &comparison,
            of: silo,
            database: database,
            tmdb: tmdb,
            progress: progress
        )
        return comparison
    }

    /// The entries' differences from TMDb's episodes: the other ids TMDb holds for each one the container
    /// carries, items both hold in another order, and, when the container has a record of its own, each
    /// episode nothing covers. What the container holds that is none of TMDb's episodes is listed as
    /// held only.
    private func compareEpisodes(
        _ episodes: [TMDb.Episode],
        of series: Int?,
        in container: Container,
        missing: Bool,
        into comparison: inout TMDbComparison,
        of silo: Silo,
        tmdb: any TMDbSource,
        progress: @Sendable (TMDbProgress, TMDbComparison) async -> Void
    ) async throws {
        let tmdbIDs = Set(episodes.map(\.ref))
        for episode in episodes {
            comparison.episodeTitles[String(episode.id)] = episode.title
            if let runtime = episode.runtime { comparison.runtimes[String(episode.id)] = runtime }
        }
        let entries = container.sequences.flatMap(\.items) + container.extras
        let byOtherIDs = try await episodesByOtherIDs(
            beneath: container,
            of: series,
            in: comparison.library,
            of: silo,
            tmdb: tmdb
        )
        let found: [[TMDbDifference]] = try await steps(
            "Reading TMDb's episodes",
            Array(episodes.indices),
            comparison,
            progress
        ) { index in
            let episode = episodes[index]
            if let entry = entries.first(where: { $0.externalRefs.contains(episode.ref) }) ?? byOtherIDs[episode.ref] {
                // An item of a container beneath is offered its ids at that container's own stop.
                guard let series, let item = entry.id?.value, entries.contains(entry) else { return nil }
                let ids = try await tmdb.externalIDs(of: episode, in: series)
                return Self.missing([episode.ref] + ids.refs, from: entry.externalRefs, item: item)
            }
            guard missing, try await !self.covered(episode.ref, of: silo) else { return nil }
            return [.episode(episode, after: index > 0 ? episodes[index - 1].ref : nil)]
        }
        comparison.differences += found.flatMap { $0 }
        if missing {
            comparison.heldChildren = try await heldChildren(
                of: container,
                episodes: episodes,
                byOtherIDs: byOtherIDs,
                in: comparison.library,
                of: silo
            )
        }
        for sequence in container.sequences {
            let carried = sequence.items.filter { $0.externalRefs.contains { tmdbIDs.contains($0) } }
            let order = episodes.map(\.ref)
            let sorted = carried.sorted { lhs, rhs in
                (order.firstIndex { lhs.externalRefs.contains($0) } ?? 0)
                    < (order.firstIndex { rhs.externalRefs.contains($0) } ?? 0)
            }
            if sorted != carried {
                comparison.differences.append(.order(sequence: sequence.id, items: sorted.compactMap { $0.id?.value }))
            }
        }
        let matched = Set(byOtherIDs.filter { tmdbIDs.contains($0.key) }.values)
        comparison.heldOnly = (container.sequences.flatMap(\.items) + container.extras).compactMap { entry in
            guard entry.childContainer == nil, entry.reference == nil, !matched.contains(entry),
                !entry.externalRefs.contains(where: { tmdbIDs.contains($0) })
            else { return nil }
            return entry.title.map { "\(entry.id?.value ?? ""): \($0)" } ?? entry.id?.value
        }
    }

    /// The containers held beneath one, each placed by the first of TMDb's episodes it holds, carrying
    /// TMDb's id or found by its other ids.
    private func heldChildren(
        of container: Container,
        episodes: [TMDb.Episode],
        byOtherIDs: [ExternalRef: Entry],
        in library: String,
        of silo: Silo
    ) async throws -> [HeldChild] {
        try await Self.concurrently(container.childContainerIDs) { child in
            let opened = try await self.open(container: child.value, in: library, of: silo)
            let held = try SidecarFile.sidecar(from: opened.sidecar).container
            let entries = held.sequences.flatMap(\.items) + held.extras
            let first = episodes.first { episode in
                entries.contains { $0.externalRefs.contains(episode.ref) }
                    || (byOtherIDs[episode.ref].map(entries.contains) ?? false)
            }
            return HeldChild(
                id: child.value,
                title: held.displayTitle,
                type: held.type,
                typeLabel: held.typeLabel,
                number: first?.number
            )
        }
    }

    /// The TMDb id of the nearest series above a container that carries one.
    private func seriesAbove(_ opened: OpenedContainer, of silo: Silo) async throws -> Int? {
        try await seriesContainerAbove(opened, of: silo)?.tmdb
    }

    /// The nearest series above a container that carries a TMDb id, and that id.
    func seriesContainerAbove(_ opened: OpenedContainer, of silo: Silo) async throws -> (id: String, tmdb: Int)? {
        var parent = opened.container.container.parent
        while let id = parent {
            let above = try await open(container: id, in: opened.container.library, of: silo)
            if above.container.container.type == ContainerType.series.rawValue,
                let tmdb = above.container.container.externalRefs.first(where: { $0.provider == "tmdb" }).flatMap({
                    Int($0.value)
                })
            {
                return (id, tmdb)
            }
            parent = above.container.container.parent
        }
        return nil
    }

    /// The episodes a container with no record of its own is read against: the season above it, or a
    /// series above it's specials, or the specials of the series its items' other ids lead to at TMDb.
    private func readingThrough(
        _ opened: OpenedContainer,
        container: Container,
        identified: [String: Int],
        of silo: Silo,
        tmdb: any TMDbSource
    ) async throws -> ([TMDb.Episode], Int, String) {
        var parent = opened.container.container.parent
        while let id = parent {
            let above = try await open(container: id, in: opened.container.library, of: silo)
            let held = try SidecarFile.sidecar(from: above.sidecar).container
            if held.type == .season, let series = try await seriesAbove(above, of: silo) {
                guard
                    let summary = Self.season(
                        of: held,
                        identified: identified[id],
                        among: try await tmdb.series(series).seasons
                    )
                else {
                    throw NoTMDbReading(
                        reason:
                            "\(held.displayTitle) above it carries no TMDb id: say which of TMDb's seasons it is when the walk reaches it, and this is read through it"
                    )
                }
                let season = try await tmdb.season(summary.number, of: series)
                return (
                    season.episodes, series,
                    "through \(held.displayTitle), \(season.name) of TMDb's series \(series)"
                )
            }
            if let own = held.externalRefs.first(where: { $0.provider == .tmdb }).flatMap({ Int($0.value) }) {
                if held.type == .series {
                    return (
                        try await tmdb.season(0, of: own).episodes, own,
                        "through \(held.displayTitle), TMDb's series \(own)"
                    )
                }
            }
            parent = above.container.container.parent
        }
        // Nothing above it is TMDb's: a breakout, whose entries are specials of a series TMDb finds by
        // their other ids.
        for entry in container.sequences.flatMap(\.items) + container.extras {
            for ref in entry.externalRefs where ref.provider == .imdb || ref.provider == .tvdb {
                guard let found = try await tmdb.find(ref).episodes.first else { continue }
                let season = try await tmdb.season(found.episode.season, of: found.series)
                return (
                    season.episodes, found.series,
                    "through TMDb's series \(found.series), which its entries are episodes of"
                )
            }
        }
        throw NoTMDbReading(
            reason:
                "\(container.displayTitle) carries no TMDb id, nothing above it does, and none of its items has an id TMDb can find"
        )
    }

    /// Which of TMDb's seasons a held season is: the one its own TMDb id names, or, carrying none, the one
    /// the operator said it is.
    nonisolated static func season(
        of season: Container,
        identified: Int?,
        among seasons: [TMDb.SeasonSummary]
    ) -> TMDb.SeasonSummary? {
        let own = season.externalRefs.first { $0.provider == .tmdb }.flatMap { Int($0.value) }
        guard let id = own ?? identified else { return nil }
        return seasons.first { $0.id == id }
    }

    /// Which of TMDb's seasons a held season carrying no TMDb id is suggested to be: the one TMDb gives its
    /// title as a name, the one whose number its title gives (`Season 13`, `Series 13`), or the one an
    /// episode beneath it is found in by its other ids.
    private func suggestedSeason(
        of season: Container,
        among seasons: [TMDb.SeasonSummary],
        series: Int,
        in library: String,
        of silo: Silo,
        tmdb: any TMDbSource
    ) async throws -> TMDb.SeasonSummary? {
        let title = season.title.rawValue
        if let named = seasons.first(where: { $0.name.caseInsensitiveCompare(title) == .orderedSame }) { return named }
        if let number = Self.seasonNumber(in: title), let numbered = seasons.first(where: { $0.number == number }) {
            return numbered
        }
        for entry in try await entries(beneath: season, in: library, of: silo) {
            for ref in entry.externalRefs where ref.provider == .imdb || ref.provider == .tvdb {
                guard let found = try await tmdb.find(ref).episodes.first(where: { $0.series == series }) else {
                    continue
                }
                return seasons.first { $0.number == found.episode.season }
            }
        }
        return nil
    }

    /// The number a season's title gives it, as `Season 13` or `Series 13` does.
    nonisolated static func seasonNumber(in title: String) -> Int? {
        let words = title.split(separator: " ")
        guard words.count == 2, ["season", "series"].contains(words[0].lowercased()) else { return nil }
        return Int(words[1])
    }

    /// The seasons a series holds beneath it, by the TMDb season each is or, carrying no TMDb id, is
    /// suggested to be: the containers its walk stops at whatever is chosen, so the series offers none of
    /// them as missing.
    private func heldSeasons(
        beneath series: Container,
        among seasons: [TMDb.SeasonSummary],
        series tmdbSeries: Int,
        in library: String,
        of silo: Silo,
        tmdb: any TMDbSource
    ) async throws -> [Int: (String, Bool)] {
        let matched: [(Int, (String, Bool))?] = try await Self.concurrently(series.childContainerIDs) { child in
            let opened = try await self.open(container: child.value, in: library, of: silo)
            let held = try SidecarFile.sidecar(from: opened.sidecar).container
            guard held.type == .season else { return nil }
            if let season = Self.season(of: held, identified: nil, among: seasons) {
                return (season.id, (child.value, false))
            }
            let suggested = try await self.suggestedSeason(
                of: held,
                among: seasons,
                series: tmdbSeries,
                in: library,
                of: silo,
                tmdb: tmdb
            )
            return suggested.map { ($0.id, (child.value, true)) }
        }
        return Dictionary(matched.compactMap { $0 }) { first, _ in first }
    }

    /// A container's own entries, and those of the containers it holds, one level down.
    private func entries(beneath container: Container, in library: String, of silo: Silo) async throws -> [Entry] {
        var entries: [Entry] = []
        for entry in container.sequences.flatMap(\.items) + container.extras {
            guard let child = entry.childContainer else {
                entries.append(entry)
                continue
            }
            let opened = try await open(container: child.value, in: library, of: silo)
            let held = try SidecarFile.sidecar(from: opened.sidecar).container
            entries += held.sequences.flatMap(\.items) + held.extras
        }
        return entries
    }

    /// The items here and in the containers beneath that carry no TMDb id, by the TMDb episode their other
    /// ids are found to be: what an episode of TMDb's is matched to when no item carries its id.
    private func episodesByOtherIDs(
        beneath container: Container,
        of series: Int?,
        in library: String,
        of silo: Silo,
        tmdb: any TMDbSource
    ) async throws -> [ExternalRef: Entry] {
        guard let series else { return [:] }
        let unmatched = try await entries(beneath: container, in: library, of: silo).filter { entry in
            entry.childContainer == nil && !entry.externalRefs.contains { $0.provider == .tmdb }
                && entry.externalRefs.contains { $0.provider == .imdb || $0.provider == .tvdb }
        }
        let found: [(ExternalRef, Entry)?] = try await Self.concurrently(unmatched) { entry in
            for ref in entry.externalRefs where ref.provider == .imdb || ref.provider == .tvdb {
                if let episode = try await tmdb.find(ref).episodes.first(where: { $0.series == series })?.episode {
                    return (episode.ref, entry)
                }
            }
            return nil
        }
        return Dictionary(found.compactMap { $0 }) { first, _ in first }
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

    /// An episode as the leaf a container gains for it.
    nonisolated static func leaf(_ episode: TMDb.Episode, in container: Container) -> Entry {
        Entry.leaf(
            Entry.Leaf(
                id: TMDbTree.itemID(for: episode.title, in: container),
                type: .episode,
                externalRefs: [episode.ref]
            )
        )
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
        TMDbTree.insert(entry, into: &container, sequence: nil, at: nil)
    }

    /// A sequence's items carrying TMDb's ids put in the order given, each in a place one of them held,
    /// the others where they stood.
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
