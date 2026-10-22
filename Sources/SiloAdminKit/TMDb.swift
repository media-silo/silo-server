// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SmdKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// TMDb as the console reads it: the records a draft is read from and a difference is read against,
/// in the shapes the console uses, and nothing it does not. The console reaches TMDb itself with a
/// token kept on this Mac; the silo is never given it. `Tmdb.md`.
public enum TMDb {
    /// What the notice in the settings says, as TMDb's terms ask.
    public static let notice = "This product uses the TMDB API but is not endorsed or certified by TMDB."
    /// The keychain account the token is kept under, beside the passkeys and never a silo's id.
    public static let tokenAccount = "tmdb:read-access-token"

    /// A record a draft can be read from, as TMDb numbers it: a movie, a series and a collection each
    /// have numbers of their own, so the kind is part of what names one.
    public struct Record: Hashable, Sendable, Codable {
        public enum Kind: String, Hashable, Sendable, Codable {
            case movie, series, collection
        }

        public var kind: Kind
        public var id: Int

        public init(_ kind: Kind, _ id: Int) {
            self.kind = kind
            self.id = id
        }

        /// The container type a record of this kind is read as.
        public var containerType: ContainerType {
            switch kind {
            case .movie: .movie
            case .series: .series
            case .collection: .collection
            }
        }

        /// The reference a container read from it carries.
        public var ref: ExternalRef { ExternalRef(provider: .tmdb, value: String(id)) }
    }

    public struct SearchResult: Hashable, Sendable {
        public var record: Record
        public var title: String
        public var year: Int?
        public var overview: String?
        public var posterPath: String?

        public init(record: Record, title: String, year: Int? = nil, overview: String? = nil, posterPath: String? = nil)
        {
            self.record = record
            self.title = title
            self.year = year
            self.overview = overview
            self.posterPath = posterPath
        }
    }

    /// The ids other providers give a record, as TMDb holds them.
    public struct ExternalIDs: Hashable, Sendable {
        public var imdb: String?
        public var tvdb: String?
        public var wikidata: String?

        public init(imdb: String? = nil, tvdb: String? = nil, wikidata: String? = nil) {
            self.imdb = imdb
            self.tvdb = tvdb
            self.wikidata = wikidata
        }

        /// The references a container or an entry carries for them, in the order a picker lists them.
        public var refs: [ExternalRef] {
            [(Provider.tvdb, tvdb), (.imdb, imdb), (.wikidata, wikidata)].compactMap { provider, value in
                guard let value, !value.isEmpty else { return nil }
                return ExternalRef(provider: provider, value: value)
            }
        }
    }

    public struct Movie: Hashable, Sendable {
        public var id: Int
        public var title: String
        public var year: Int?
        public var overview: String?
        public var externalIDs: ExternalIDs
        /// The collection it is in, at TMDb.
        public var collection: Int?

        public init(
            id: Int,
            title: String,
            year: Int? = nil,
            overview: String? = nil,
            externalIDs: ExternalIDs = .init(),
            collection: Int? = nil
        ) {
            self.id = id
            self.title = title
            self.year = year
            self.overview = overview
            self.externalIDs = externalIDs
            self.collection = collection
        }
    }

    public struct Episode: Hashable, Sendable, Codable {
        public var id: Int
        public var season: Int
        public var number: Int
        public var title: String
        /// As TMDb writes it, `yyyy-mm-dd`, which sorts as it reads.
        public var airDate: String?
        /// In minutes.
        public var runtime: Int?

        public init(id: Int, season: Int, number: Int, title: String, airDate: String? = nil, runtime: Int? = nil) {
            self.id = id
            self.season = season
            self.number = number
            self.title = title
            self.airDate = airDate
            self.runtime = runtime
        }

        public var ref: ExternalRef { ExternalRef(provider: .tmdb, value: String(id)) }
    }

    public struct SeasonSummary: Hashable, Sendable {
        public var id: Int
        public var number: Int
        public var name: String

        public init(id: Int, number: Int, name: String) {
            self.id = id
            self.number = number
            self.name = name
        }
    }

    public struct Season: Hashable, Sendable {
        public var id: Int
        public var number: Int
        public var name: String
        public var year: Int?
        public var overview: String?
        public var episodes: [Episode]

        public init(id: Int, number: Int, name: String, year: Int? = nil, overview: String? = nil, episodes: [Episode])
        {
            self.id = id
            self.number = number
            self.name = name
            self.year = year
            self.overview = overview
            self.episodes = episodes
        }
    }

    public struct EpisodeGroupSummary: Hashable, Sendable {
        public var id: String
        public var name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    public struct Series: Hashable, Sendable {
        public var id: Int
        public var name: String
        public var year: Int?
        public var overview: String?
        public var seasons: [SeasonSummary]
        public var externalIDs: ExternalIDs
        public var episodeGroups: [EpisodeGroupSummary]

        public init(
            id: Int,
            name: String,
            year: Int? = nil,
            overview: String? = nil,
            seasons: [SeasonSummary],
            externalIDs: ExternalIDs = .init(),
            episodeGroups: [EpisodeGroupSummary] = []
        ) {
            self.id = id
            self.name = name
            self.year = year
            self.overview = overview
            self.seasons = seasons
            self.externalIDs = externalIDs
            self.episodeGroups = episodeGroups
        }
    }

    /// A series' episodes arranged by a contributor: groups in order, each with its episodes in order.
    public struct EpisodeGroup: Hashable, Sendable {
        public struct Group: Hashable, Sendable {
            public var name: String
            public var episodes: [Episode]

            public init(name: String, episodes: [Episode]) {
                self.name = name
                self.episodes = episodes
            }
        }

        public var id: String
        public var name: String
        public var groups: [Group]

        public init(id: String, name: String, groups: [Group]) {
            self.id = id
            self.name = name
            self.groups = groups
        }
    }

    public struct Collection: Hashable, Sendable {
        public var id: Int
        public var name: String
        public var overview: String?
        public var parts: [Movie]

        public init(id: Int, name: String, overview: String? = nil, parts: [Movie]) {
            self.id = id
            self.name = name
            self.overview = overview
            self.parts = parts
        }
    }

    /// What TMDb's lookup by another provider's id found: movies, and episodes with the series each is in.
    public struct Found: Hashable, Sendable {
        public var movies: [Movie]
        public var episodes: [(series: Int, episode: Episode)]

        public init(movies: [Movie] = [], episodes: [(series: Int, episode: Episode)] = []) {
            self.movies = movies
            self.episodes = episodes
        }

        public static func == (lhs: Found, rhs: Found) -> Bool {
            lhs.movies == rhs.movies
                && lhs.episodes.map { "\($0.series)/\($0.episode.id)" }
                    == rhs.episodes.map { "\($0.series)/\($0.episode.id)" }
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(movies)
            for (series, episode) in episodes {
                hasher.combine(series)
                hasher.combine(episode.id)
            }
        }
    }

    /// The images TMDb holds for a record, by their paths there, best first: what the artwork kinds
    /// `poster`, `fanart` and `logo` are offered from.
    public struct Images: Hashable, Sendable {
        public var posters: [String]
        public var backdrops: [String]
        public var logos: [String]

        public init(posters: [String] = [], backdrops: [String] = [], logos: [String] = []) {
            self.posters = posters
            self.backdrops = backdrops
            self.logos = logos
        }

        /// The images offered for an artwork kind.
        public func offered(for kind: String) -> [String] {
            switch kind {
            case "poster": posters
            case "fanart": backdrops
            case "logo": logos
            default: []
            }
        }
    }

    /// Why TMDb could not be asked: no token, or one it refuses.
    public enum Unavailable: Error, Hashable, Sendable {
        case noToken
        case refused
        case answered(Int)

        public var reason: String {
            switch self {
            case .noToken: "No TMDb token is given in this Mac's settings."
            case .refused: "TMDb refused the token in this Mac's settings."
            case .answered(let status): "TMDb answered \(status)."
            }
        }
    }
}

/// Where the console reads TMDb from: the API itself, or in tests the answers it would give. Every call
/// is one TMDb answers in one request, and none of them writes.
public protocol TMDbSource: Sendable {
    /// Throws `TMDb.Unavailable.refused` when TMDb does not accept the token.
    func authenticate() async throws
    func search(_ query: String) async throws -> [TMDb.SearchResult]
    func movie(_ id: Int) async throws -> TMDb.Movie
    func series(_ id: Int) async throws -> TMDb.Series
    func season(_ number: Int, of series: Int) async throws -> TMDb.Season
    func episodeGroup(_ id: String) async throws -> TMDb.EpisodeGroup
    func collection(_ id: Int) async throws -> TMDb.Collection
    func externalIDs(of episode: TMDb.Episode, in series: Int) async throws -> TMDb.ExternalIDs
    /// What TMDb holds under another provider's id: `imdb` or `tvdb`.
    func find(_ ref: ExternalRef) async throws -> TMDb.Found
    /// The images TMDb holds for a movie, a series or a collection.
    func images(of record: TMDb.Record) async throws -> TMDb.Images
    /// An image's bytes, by its path at TMDb.
    func image(at path: String) async throws -> Data
}

/// TMDb's API, version 3, read with a read access token in the language the settings name.
public struct TMDbClient: TMDbSource {
    public let token: String
    public let language: String
    private let session: URLSession
    private let base = URL(string: "https://api.themoviedb.org/3/")!

    public init(token: String, language: String, session: URLSession = .shared) {
        self.token = token
        self.language = language
        self.session = session
    }

    public func authenticate() async throws {
        _ = try await get("authentication", as: Empty.self)
    }

    public func search(_ query: String) async throws -> [TMDb.SearchResult] {
        async let movies = get("search/movie", ["query": query], as: Page<SearchedMovie>.self)
        async let series = get("search/tv", ["query": query], as: Page<SearchedSeries>.self)
        let found = try await (movies, series)
        return found.0.results.map {
            TMDb.SearchResult(
                record: .init(.movie, $0.id),
                title: $0.title,
                year: Self.year($0.release_date),
                overview: $0.overview,
                posterPath: $0.poster_path
            )
        }
            + found.1.results.map {
                TMDb.SearchResult(
                    record: .init(.series, $0.id),
                    title: $0.name,
                    year: Self.year($0.first_air_date),
                    overview: $0.overview,
                    posterPath: $0.poster_path
                )
            }
    }

    public func movie(_ id: Int) async throws -> TMDb.Movie {
        let movie = try await get("movie/\(id)", ["append_to_response": "external_ids"], as: MovieJSON.self)
        return TMDb.Movie(
            id: movie.id,
            title: movie.title,
            year: Self.year(movie.release_date),
            overview: movie.overview.flatMap(Self.nonEmpty),
            externalIDs: movie.external_ids?.value ?? .init(),
            collection: movie.belongs_to_collection?.id
        )
    }

    public func series(_ id: Int) async throws -> TMDb.Series {
        let series = try await get(
            "tv/\(id)",
            ["append_to_response": "external_ids,episode_groups"],
            as: SeriesJSON.self
        )
        return TMDb.Series(
            id: series.id,
            name: series.name,
            year: Self.year(series.first_air_date),
            overview: series.overview.flatMap(Self.nonEmpty),
            seasons: series.seasons.map { TMDb.SeasonSummary(id: $0.id, number: $0.season_number, name: $0.name) },
            externalIDs: series.external_ids?.value ?? .init(),
            episodeGroups: (series.episode_groups?.results ?? []).map { .init(id: $0.id, name: $0.name) }
        )
    }

    public func season(_ number: Int, of series: Int) async throws -> TMDb.Season {
        let season = try await get("tv/\(series)/season/\(number)", as: SeasonJSON.self)
        return TMDb.Season(
            id: season.id,
            number: season.season_number,
            name: season.name,
            year: Self.year(season.air_date),
            overview: season.overview.flatMap(Self.nonEmpty),
            episodes: season.episodes.map(\.value)
        )
    }

    public func episodeGroup(_ id: String) async throws -> TMDb.EpisodeGroup {
        let group = try await get("tv/episode_group/\(id)", as: EpisodeGroupJSON.self)
        return TMDb.EpisodeGroup(
            id: group.id,
            name: group.name,
            groups: group.groups.sorted { $0.order < $1.order }.map { part in
                TMDb.EpisodeGroup.Group(
                    name: part.name,
                    episodes: part.episodes.sorted { ($0.order ?? 0) < ($1.order ?? 0) }.map(\.value)
                )
            }
        )
    }

    public func collection(_ id: Int) async throws -> TMDb.Collection {
        let collection = try await get("collection/\(id)", as: CollectionJSON.self)
        return TMDb.Collection(
            id: collection.id,
            name: collection.name,
            overview: collection.overview.flatMap(Self.nonEmpty),
            parts: collection.parts.map {
                TMDb.Movie(id: $0.id, title: $0.title, year: Self.year($0.release_date))
            }
        )
    }

    public func externalIDs(of episode: TMDb.Episode, in series: Int) async throws -> TMDb.ExternalIDs {
        try await get(
            "tv/\(series)/season/\(episode.season)/episode/\(episode.number)/external_ids",
            as: ExternalIDsJSON.self
        ).value
    }

    public func find(_ ref: ExternalRef) async throws -> TMDb.Found {
        let source =
            switch ref.provider {
            case .imdb: "imdb_id"
            case .tvdb: "tvdb_id"
            default: "\(ref.provider)_id"
            }
        let found = try await get("find/\(ref.value)", ["external_source": source], as: FindJSON.self)
        return TMDb.Found(
            movies: found.movie_results.map {
                TMDb.Movie(id: $0.id, title: $0.title, year: Self.year($0.release_date))
            },
            episodes: found.tv_episode_results.map { ($0.show_id ?? 0, $0.value) }
        )
    }

    public func images(of record: TMDb.Record) async throws -> TMDb.Images {
        let kind =
            switch record.kind {
            case .movie: "movie"
            case .series: "tv"
            case .collection: "collection"
            }
        // Images in any language, and those with none, which is what a backdrop usually is.
        let images = try await get(
            "\(kind)/\(record.id)/images",
            ["include_image_language": "\(language.prefix(2)),null"],
            as: ImagesJSON.self
        )
        return TMDb.Images(
            posters: images.posters.map(\.file_path),
            backdrops: images.backdrops.map(\.file_path),
            logos: (images.logos ?? []).map(\.file_path)
        )
    }

    public func image(at path: String) async throws -> Data {
        let url = URL(string: "https://image.tmdb.org/t/p/original\(path)")!
        let (data, response) = try await session.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw TMDb.Unavailable.answered(status) }
        return data
    }

    // MARK: The wire

    private func get<Answer: Decodable>(
        _ path: String,
        _ query: [String: String] = [:],
        as: Answer.Type
    ) async throws -> Answer {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems =
            [URLQueryItem(name: "language", value: language)]
            + query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw TMDb.Unavailable.refused }
        guard (200..<300).contains(status) else { throw TMDb.Unavailable.answered(status) }
        return try JSONDecoder().decode(Answer.self, from: data)
    }

    static func year(_ date: String?) -> Int? {
        date.flatMap { Int($0.prefix(4)) }
    }

    private static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // TMDb's own spellings, decoded as they come.
    // swiftlint:disable identifier_name nesting
    private struct Empty: Decodable {}
    private struct Page<Result: Decodable>: Decodable { var results: [Result] }
    private struct SearchedMovie: Decodable {
        var id: Int
        var title: String
        var release_date: String?
        var overview: String?
        var poster_path: String?
    }
    private struct SearchedSeries: Decodable {
        var id: Int
        var name: String
        var first_air_date: String?
        var overview: String?
        var poster_path: String?
    }
    private struct ExternalIDsJSON: Decodable {
        var imdb_id: String?
        var tvdb_id: Int?
        var wikidata_id: String?
        var value: TMDb.ExternalIDs {
            TMDb.ExternalIDs(imdb: imdb_id, tvdb: tvdb_id.map(String.init), wikidata: wikidata_id)
        }
    }
    private struct MovieJSON: Decodable {
        struct Collection: Decodable { var id: Int }
        var id: Int
        var title: String
        var release_date: String?
        var overview: String?
        var external_ids: ExternalIDsJSON?
        var belongs_to_collection: Collection?
    }
    private struct SeriesJSON: Decodable {
        struct Season: Decodable {
            var id: Int
            var season_number: Int
            var name: String
        }
        struct Groups: Decodable {
            struct Group: Decodable {
                var id: String
                var name: String
            }
            var results: [Group]
        }
        var id: Int
        var name: String
        var first_air_date: String?
        var overview: String?
        var seasons: [Season]
        var external_ids: ExternalIDsJSON?
        var episode_groups: Groups?
    }
    private struct EpisodeJSON: Decodable {
        var id: Int
        var season_number: Int
        var episode_number: Int
        var name: String
        var air_date: String?
        var runtime: Int?
        var order: Int?
        var show_id: Int?
        var value: TMDb.Episode {
            TMDb.Episode(
                id: id,
                season: season_number,
                number: episode_number,
                title: name,
                airDate: air_date,
                runtime: runtime
            )
        }
    }
    private struct SeasonJSON: Decodable {
        var id: Int
        var season_number: Int
        var name: String
        var air_date: String?
        var overview: String?
        var episodes: [EpisodeJSON]
    }
    private struct EpisodeGroupJSON: Decodable {
        struct Group: Decodable {
            var name: String
            var order: Int
            var episodes: [EpisodeJSON]
        }
        var id: String
        var name: String
        var groups: [Group]
    }
    private struct CollectionJSON: Decodable {
        struct Part: Decodable {
            var id: Int
            var title: String
            var release_date: String?
        }
        var id: Int
        var name: String
        var overview: String?
        var parts: [Part]
    }
    private struct ImagesJSON: Decodable {
        struct Image: Decodable { var file_path: String }
        var posters: [Image]
        var backdrops: [Image]
        var logos: [Image]?
    }
    private struct FindJSON: Decodable {
        struct FoundMovie: Decodable {
            var id: Int
            var title: String
            var release_date: String?
        }
        var movie_results: [FoundMovie]
        var tv_episode_results: [EpisodeJSON]
    }
    // swiftlint:enable identifier_name nesting
}
