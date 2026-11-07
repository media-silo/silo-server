// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import SmdKit
import SmdSidecar

// MARK: - Content from TMDb

/// What the console reads from TMDb: content alone, an outline and images, through the TMDb ids a
/// container or its Wikidata item carries. Facts are Wikidata's, so nothing TMDb holds is taken as one,
/// and a walk with no TMDb token reads every fact and no content. `Proposals/Wikidata.md`.
extension AdminConsole {
    /// The content TMDb holds for a container: the record it is read from, which what is taken from it
    /// is credited to, its overview, and its images, best first.
    public struct Content: Hashable, Sendable {
        public var record: TMDb.Record
        public var overview: String?
        public var images: TMDb.Images

        public init(record: TMDb.Record, overview: String? = nil, images: TMDb.Images = TMDb.Images()) {
            self.record = record
            self.overview = overview
            self.images = images
        }
    }

    /// A TMDb series and its seasons, by TMDb's id for each season: what a season's content is read
    /// through, since TMDb holds a season beneath its series by its number there.
    public struct TMDbSeasons: Hashable, Sendable {
        public var series: Int
        public var numbers: [Int: Int]

        public init(series: Int, numbers: [Int: Int]) {
            self.series = series
            self.numbers = numbers
        }
    }

    /// The seasons TMDb lists for a series, by the series' TMDb id.
    nonisolated static func tmdbSeasons(of series: String?, from tmdb: any TMDbSource) async throws -> TMDbSeasons? {
        guard let id = series.flatMap(Int.init) else { return nil }
        let seasons = try await tmdb.series(id).seasons
        return TMDbSeasons(series: id, numbers: Dictionary(seasons.map { ($0.id, $0.number) }) { first, _ in first })
    }

    /// The content of the TMDb record a container of a type is read from, by the TMDb id of its item: a
    /// film's, a collection's or a series' own, and a season's through its series. Nil for a type TMDb
    /// gives no record of its own here, as a serial or an episode, or for an id it does not list. The
    /// images are offered, not needed: they are none when TMDb will not say.
    nonisolated static func content(
        of type: ContainerType,
        tmdb id: String?,
        seasons: TMDbSeasons? = nil,
        from tmdb: any TMDbSource
    ) async throws -> Content? {
        guard let id = id.flatMap(Int.init) else { return nil }
        switch type {
        case .movie:
            let record = TMDb.Record(.movie, id)
            async let images = try? tmdb.images(of: record)
            return Content(record: record, overview: try await tmdb.movie(id).overview, images: await images ?? .init())
        case .collection:
            let record = TMDb.Record(.collection, id)
            async let images = try? tmdb.images(of: record)
            return Content(
                record: record,
                overview: try await tmdb.collection(id).overview,
                images: await images ?? .init()
            )
        case .series:
            let record = TMDb.Record(.series, id)
            async let images = try? tmdb.images(of: record)
            return Content(
                record: record,
                overview: try await tmdb.series(id).overview,
                images: await images ?? .init()
            )
        case .season:
            guard let seasons, let number = seasons.numbers[id] else { return nil }
            async let images = try? tmdb.images(ofSeason: number, of: seasons.series)
            return Content(
                record: TMDb.Record(.season, id),
                overview: try await tmdb.season(number, of: seasons.series).overview,
                images: await images ?? .init()
            )
        default:
            return nil
        }
    }

    /// Whether an attribution has been kept longer than its provider's terms let its content be kept.
    nonisolated static func isStale(_ attribution: Attribution, today: CalendarDate) -> Bool {
        guard let months = attribution.provider.keepsContentForMonths else { return false }
        return attribution.read.adding(months: months) < today
    }

    /// How a held container's content differs from TMDb's: an outline TMDb words otherwise, and each
    /// artwork kind the folder lacks and TMDb has an image for. An outline or an image TMDb's terms no
    /// longer let it keep is offered to be read again, the same or changed, or removed when TMDb no
    /// longer has one.
    nonisolated static func differences(
        of container: Container,
        attributions: [Attribution],
        artwork held: [String],
        from content: Content,
        today: CalendarDate
    ) -> [ReviewWalk.Difference] {
        var differences: [ReviewWalk.Difference] = []
        let record = String(content.record.id)
        let overview = content.overview.flatMap { $0.isEmpty ? nil : $0 }
        if let outline = attributions.first(where: { $0.subject == .outline && $0.provider == .tmdb }),
            isStale(outline, today: today)
        {
            differences.append(.staleOutline(overview, record: record, read: outline.read))
        } else if let overview, overview != container.outline {
            differences.append(.outline(overview, record: record))
        }
        for kind in ["poster", "fanart", "logo"] {
            let offered = content.images.offered(for: kind)
            if held.contains(kind) {
                guard
                    let attribution = attributions.first(where: { $0.subject == .artwork(kind) && $0.provider == .tmdb }
                    ),
                    isStale(attribution, today: today)
                else { continue }
                differences.append(
                    .staleArtwork(
                        kind: kind,
                        path: offered.first,
                        record: content.record,
                        offered: offered,
                        read: attribution.read
                    )
                )
            } else if let path = offered.first {
                differences.append(.artwork(kind: kind, path: path, record: content.record, offered: offered))
            }
        }
        return differences
    }
}
