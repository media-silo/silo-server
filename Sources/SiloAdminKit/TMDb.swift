// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SmdKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// TMDb as the console reads it: content alone, the outline and images of the records a container's
/// TMDb ids name, in the shapes the console uses, and nothing it does not. Facts are Wikidata's. The console reaches TMDb itself with a
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
            /// A season, by TMDb's own id for it: read only through its series, so never what a draft is
            /// read from, but what the season's outline and artwork are credited to.
            case season
            /// An episode, by TMDb's own id for it: read only within its season, so never what a draft
            /// is read from, but what the episode's outline is credited to.
            case episode
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
            case .season: .season
            case .episode: .episode
            }
        }

        /// The reference a container read from it carries.
        public var ref: ExternalRef { ExternalRef(provider: .tmdb, value: String(id)) }
    }

    public struct Movie: Hashable, Sendable {
        public var id: Int
        public var title: String
        public var overview: String?

        public init(id: Int, title: String, overview: String? = nil) {
            self.id = id
            self.title = title
            self.overview = overview
        }
    }

    /// A season as its series lists it: TMDb's id for it and its number there, which is what its own
    /// record is read by.
    public struct SeasonSummary: Hashable, Sendable, Codable {
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
        public var overview: String?
        /// Its episodes' overviews, by TMDb's id for each episode: an episode's content, which TMDb
        /// gives no route of its own by that id.
        public var episodes: [Int: String]
        /// Where TMDb holds each of its episodes' stills, by TMDb's id for the episode: what an episode's
        /// `thumb` is offered from.
        public var stills: [Int: EpisodeStills]

        public init(
            id: Int,
            number: Int,
            name: String,
            overview: String? = nil,
            episodes: [Int: String] = [:],
            stills: [Int: EpisodeStills] = [:]
        ) {
            self.id = id
            self.number = number
            self.name = name
            self.overview = overview
            self.episodes = episodes
            self.stills = stills
        }
    }

    public struct Series: Hashable, Sendable {
        public var id: Int
        public var name: String
        public var overview: String?
        public var seasons: [SeasonSummary]

        public init(id: Int, name: String, overview: String? = nil, seasons: [SeasonSummary] = []) {
            self.id = id
            self.name = name
            self.overview = overview
            self.seasons = seasons
        }
    }

    public struct Collection: Hashable, Sendable {
        public var id: Int
        public var name: String
        public var overview: String?

        public init(id: Int, name: String, overview: String? = nil) {
            self.id = id
            self.name = name
            self.overview = overview
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
    func movie(_ id: Int) async throws -> TMDb.Movie
    func series(_ id: Int) async throws -> TMDb.Series
    func season(_ number: Int, of series: Int) async throws -> TMDb.Season
    func collection(_ id: Int) async throws -> TMDb.Collection
    /// The images TMDb holds for a movie, a series or a collection; a season's are asked through its series.
    func images(of record: TMDb.Record) async throws -> TMDb.Images
    /// The images TMDb holds for a season of a series, by its number there: posters, and nothing else.
    func images(ofSeason number: Int, of series: Int) async throws -> TMDb.Images
    /// The images TMDb holds for an episode, by its number in its season and its season's in its series:
    /// stills, and nothing else.
    func images(ofEpisode number: Int, inSeason season: Int, of series: Int) async throws -> TMDb.Images
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

    public func movie(_ id: Int) async throws -> TMDb.Movie {
        let movie = try await get("movie/\(id)", as: MovieJSON.self)
        return TMDb.Movie(id: movie.id, title: movie.title, overview: movie.overview.flatMap(Self.nonEmpty))
    }

    public func series(_ id: Int) async throws -> TMDb.Series {
        let series = try await get("tv/\(id)", as: SeriesJSON.self)
        return TMDb.Series(
            id: series.id,
            name: series.name,
            overview: series.overview.flatMap(Self.nonEmpty),
            seasons: series.seasons.map { TMDb.SeasonSummary(id: $0.id, number: $0.season_number, name: $0.name) }
        )
    }

    public func season(_ number: Int, of series: Int) async throws -> TMDb.Season {
        let season = try await get("tv/\(series)/season/\(number)", as: SeasonJSON.self)
        return TMDb.Season(
            id: season.id,
            number: season.season_number,
            name: season.name,
            overview: season.overview.flatMap(Self.nonEmpty),
            episodes: Dictionary(
                (season.episodes ?? []).compactMap { episode in
                    episode.overview.flatMap(Self.nonEmpty).map { (episode.id, $0) }
                },
                uniquingKeysWith: { first, _ in first }
            ),
            stills: Dictionary(
                (season.episodes ?? []).compactMap { episode in
                    episode.episode_number.map { number in
                        (
                            episode.id,
                            TMDb.EpisodeStills(
                                series: series,
                                season: season.season_number,
                                episode: number,
                                still: episode.still_path.flatMap(Self.nonEmpty)
                            )
                        )
                    }
                },
                uniquingKeysWith: { first, _ in first }
            )
        )
    }

    public func collection(_ id: Int) async throws -> TMDb.Collection {
        let collection = try await get("collection/\(id)", as: CollectionJSON.self)
        return TMDb.Collection(
            id: collection.id,
            name: collection.name,
            overview: collection.overview.flatMap(Self.nonEmpty)
        )
    }

    public func images(of record: TMDb.Record) async throws -> TMDb.Images {
        let kind =
            switch record.kind {
            case .movie: "movie"
            case .series: "tv"
            case .collection: "collection"
            // TMDb serves a season's images only beneath its series, by its number there, and an
            // episode's beneath its season, by its number there.
            case .season, .episode: throw TMDb.Unavailable.answered(404)
            }
        return try await images(at: "\(kind)/\(record.id)/images")
    }

    public func images(ofSeason number: Int, of series: Int) async throws -> TMDb.Images {
        try await images(at: "tv/\(series)/season/\(number)/images")
    }

    public func images(ofEpisode number: Int, inSeason season: Int, of series: Int) async throws -> TMDb.Images {
        try await images(at: "tv/\(series)/season/\(season)/episode/\(number)/images")
    }

    private func images(at path: String) async throws -> TMDb.Images {
        // Images in any language, and those with none, which is what a backdrop usually is.
        let images = try await get(path, ["include_image_language": "\(language.prefix(2)),null"], as: ImagesJSON.self)
        return TMDb.Images(
            posters: (images.posters ?? []).map(\.file_path),
            backdrops: (images.backdrops ?? []).map(\.file_path),
            logos: (images.logos ?? []).map(\.file_path),
            stills: (images.stills ?? []).map(\.file_path),
            sizes: Dictionary(
                [images.posters, images.backdrops, images.logos, images.stills].flatMap { $0 ?? [] }
                    .compactMap(Self.sized),
                uniquingKeysWith: { first, _ in first }
            )
        )
    }

    /// An image's path and its size, when TMDb says its size.
    private static func sized(_ image: ImagesJSON.Image) -> (String, TMDb.Size)? {
        guard let width = image.width, let height = image.height else { return nil }
        return (image.file_path, TMDb.Size(width: width, height: height))
    }

    public func image(at path: String) async throws -> Data {
        let url = URL(string: "https://image.tmdb.org/t/p/original\(TMDb.raster(path))")!
        let (data, status) = try await answer(to: URLRequest(url: url))
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
        let (data, status) = try await answer(to: request)
        if status == 401 { throw TMDb.Unavailable.refused }
        guard (200..<300).contains(status) else { throw TMDb.Unavailable.answered(status) }
        return try JSONDecoder().decode(Answer.self, from: data)
    }

    /// How many times a request TMDb answers 429, too many at once, is asked again.
    public static let retries = 3

    /// TMDb's answer to a request, asked again after the wait TMDb's `Retry-After` names, or a second,
    /// while TMDb says too many are being asked at once.
    private func answer(to request: URLRequest) async throws -> (Data, Int) {
        var attempt = 0
        while true {
            let (data, response) = try await session.data(for: request)
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            guard status == 429, attempt < Self.retries else { return (data, status) }
            attempt += 1
            let wait = http?.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 1
            try await Task.sleep(for: .seconds(max(0, wait)))
        }
    }

    private static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // TMDb's own spellings, decoded as they come.
    // swiftlint:disable identifier_name nesting
    private struct Empty: Decodable {}
    private struct MovieJSON: Decodable {
        var id: Int
        var title: String
        var overview: String?
    }
    private struct SeriesJSON: Decodable {
        struct Season: Decodable {
            var id: Int
            var season_number: Int
            var name: String
        }
        var id: Int
        var name: String
        var overview: String?
        var seasons: [Season]
    }
    private struct SeasonJSON: Decodable {
        struct Episode: Decodable {
            var id: Int
            var overview: String?
            var episode_number: Int?
            var still_path: String?
        }
        var id: Int
        var season_number: Int
        var name: String
        var overview: String?
        var episodes: [Episode]?
    }
    private struct CollectionJSON: Decodable {
        var id: Int
        var name: String
        var overview: String?
    }
    private struct ImagesJSON: Decodable {
        struct Image: Decodable {
            var file_path: String
            var width: Int?
            var height: Int?
        }
        /// Absent for an episode, which has stills alone.
        var posters: [Image]?
        /// Absent for a season, which has posters alone.
        var backdrops: [Image]?
        var logos: [Image]?
        var stills: [Image]?
    }
    // swiftlint:enable identifier_name nesting
}
