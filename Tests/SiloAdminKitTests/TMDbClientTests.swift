// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloAdminKit
import SmdKit
import Synchronization
import Testing

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// TMDb's client against a stub answering as TMDb's API does, in its own spellings: each request asked
/// with the bearer token and the language, and each answer read as the console's types. Serial because
/// the handler is one static seam.
@Suite(.serialized)
struct TMDbClientTests {
    private final class Stub: URLProtocol, @unchecked Sendable {
        static let handler = Mutex<@Sendable (URLRequest) -> (Int, String)>({ _ in (404, "") })
        static let asked = Mutex<[URLRequest]>([])
        static let headers = Mutex<[String: String]>([:])

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.asked.withLock { $0.append(request) }
            let (status, body) = Self.handler.withLock { $0(request) }
            let headers = Self.headers.withLock { $0 }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    /// A client whose every request is answered by path, the query aside.
    private static func client(_ answers: [String: String], status: Int = 200) -> TMDbClient {
        Stub.asked.withLock { $0 = [] }
        Stub.headers.withLock { $0 = [:] }
        Stub.handler.withLock {
            $0 = { request in
                let path = request.url!.path.replacingOccurrences(of: "/3/", with: "")
                guard let body = answers[path] else { return (404, "") }
                return (status, body)
            }
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Stub.self]
        return TMDbClient(token: "read-token", language: "en-GB", session: URLSession(configuration: configuration))
    }

    private static func query(of request: URLRequest) -> [String: String] {
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }

    @Test func everyRequestCarriesTheTokenAndTheLanguage() async throws {
        let client = Self.client(["authentication": #"{"success":true}"#])
        try await client.authenticate()
        let request = try #require(Stub.asked.withLock { $0.first })
        #expect(request.url?.host == "api.themoviedb.org")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer read-token")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(Self.query(of: request)["language"] == "en-GB")
    }

    @Test func aRefusedTokenAndAnyOtherFailureAreSaid() async throws {
        await #expect(throws: TMDb.Unavailable.refused) {
            try await Self.client(["authentication": "{}"], status: 401).authenticate()
        }
        await #expect(throws: TMDb.Unavailable.answered(503)) {
            try await Self.client(["movie/348": "{}"], status: 503).movie(348)
        }
        #expect(TMDb.Unavailable.answered(503).reason == "TMDb answered 503.")
    }

    @Test func tooManyAtOnceIsAskedAgainAfterTMDbsWait() async throws {
        let client = Self.client([:])
        Stub.headers.withLock { $0 = ["Retry-After": "0"] }
        let answered = Mutex(0)
        Stub.handler.withLock {
            $0 = { _ in
                answered.withLock { $0 += 1 }
                return answered.withLock { $0 } < 3 ? (429, "") : (200, #"{"id":348,"title":"Alien"}"#)
            }
        }
        #expect(try await client.movie(348).title == "Alien")
        #expect(Stub.asked.withLock { $0.count } == 3, "asked again twice")

        Stub.handler.withLock { $0 = { _ in (429, "") } }
        Stub.asked.withLock { $0 = [] }
        await #expect(throws: TMDb.Unavailable.answered(429)) { try await client.movie(348) }
        #expect(Stub.asked.withLock { $0.count } == 1 + TMDbClient.retries, "then said")
    }

    @Test func aFilmsOutlineIsReadAndOneOfOnlySpacesIsNone() async throws {
        let client = Self.client(["movie/348": #"{"id":348,"title":"Alien","overview":"  "}"#])
        #expect(try await client.movie(348) == TMDb.Movie(id: 348, title: "Alien", overview: nil))
        #expect(Self.query(of: Stub.asked.withLock { $0[0] })["append_to_response"] == nil, "nothing beside it")
    }

    @Test func aSeriesIsReadWithItsSeasonsAndASeasonByItsNumber() async throws {
        let client = Self.client([
            "tv/121":
                #"{"id":121,"name":"Doctor Who","overview":"A time traveller.","seasons":[{"id":50,"season_number":0,"name":"Specials"},{"id":51,"season_number":1,"name":"Season 1"}]}"#,
            "tv/121/season/1":
                #"{"id":51,"season_number":1,"name":"Season 1","overview":"The first.","episodes":[{"id":5101,"episode_number":1,"overview":"Rose.","still_path":"/rose.jpg"},{"id":5102,"episode_number":2,"overview":" ","still_path":null},{"id":5103}]}"#,
        ])
        let series = try await client.series(121)
        #expect(series.name == "Doctor Who" && series.overview == "A time traveller.")
        #expect(series.seasons.map(\.id) == [50, 51] && series.seasons.map(\.number) == [0, 1])
        #expect(
            try await client.season(1, of: 121)
                == TMDb.Season(
                    id: 51,
                    number: 1,
                    name: "Season 1",
                    overview: "The first.",
                    episodes: [5101: "Rose."],
                    stills: [
                        5101: TMDb.EpisodeStills(series: 121, season: 1, episode: 1, still: "/rose.jpg"),
                        5102: TMDb.EpisodeStills(series: 121, season: 1, episode: 2),
                    ]
                )
        )
    }

    @Test func imagesAWalkKeptBeforeStillsAreReadWithNone() throws {
        let kept = Data(#"{"posters":["/p.jpg"],"backdrops":[],"logos":[]}"#.utf8)
        let images = try JSONDecoder().decode(TMDb.Images.self, from: kept)
        #expect(images == TMDb.Images(posters: ["/p.jpg"]))
        #expect(
            try JSONDecoder().decode(TMDb.Images.self, from: JSONEncoder().encode(TMDb.Images(stills: ["/s.jpg"])))
                .stills == ["/s.jpg"]
        )
    }

    @Test func aCollectionsOutlineIsRead() async throws {
        let client = Self.client(["collection/8091": #"{"id":8091,"name":"Alien Collection","overview":"Ripley."}"#])
        #expect(
            try await client.collection(8091)
                == TMDb.Collection(id: 8091, name: "Alien Collection", overview: "Ripley.")
        )
    }

    @Test func aRecordsImagesAreListedInTheLanguageOrNoneAndFetchedWhole() async throws {
        let images =
            #"{"posters":[{"file_path":"/poster.jpg","width":2000,"height":3000}],"backdrops":[{"file_path":"/backdrop.jpg"}]}"#
        let client = Self.client([
            "movie/348/images": images,
            "tv/121/images": #"{"posters":[],"backdrops":[],"logos":[{"file_path":"/logo.png"}]}"#,
            "collection/8091/images": images,
            "tv/121/season/1/images": #"{"posters":[{"file_path":"/season.jpg"}]}"#,
            "tv/121/season/1/episode/2/images": #"{"stills":[{"file_path":"/still.jpg"}]}"#,
            "/t/p/original/poster.jpg": "JPEG",
        ])
        #expect(
            try await client.images(of: TMDb.Record(.movie, 348))
                == TMDb.Images(
                    posters: ["/poster.jpg"],
                    backdrops: ["/backdrop.jpg"],
                    sizes: ["/poster.jpg": TMDb.Size(width: 2000, height: 3000)]
                ),
            "a record with no logos has none, and an image whose size TMDb does not say no size"
        )
        #expect(Self.query(of: Stub.asked.withLock { $0[0] })["include_image_language"] == "en,null")
        #expect(try await client.images(of: TMDb.Record(.series, 121)).offered(for: "logo") == ["/logo.png"])
        #expect(try await client.images(of: TMDb.Record(.collection, 8091)).offered(for: "fanart") == ["/backdrop.jpg"])
        #expect(TMDb.Images().offered(for: "banner") == [])
        #expect(
            try await client.images(ofSeason: 1, of: 121) == TMDb.Images(posters: ["/season.jpg"]),
            "a season's, beneath its series, are posters alone"
        )
        #expect(
            try await client.images(ofEpisode: 2, inSeason: 1, of: 121).offered(for: "thumb") == ["/still.jpg"],
            "an episode's, beneath its season, are stills alone"
        )
        await #expect(throws: TMDb.Unavailable.answered(404), "a season is asked for through its series") {
            try await client.images(of: TMDb.Record(.season, 901))
        }

        #expect(try await client.image(at: "/poster.jpg") == Data("JPEG".utf8))
        #expect(Stub.asked.withLock { $0.last?.url?.host } == "image.tmdb.org")
        await #expect(throws: TMDb.Unavailable.answered(404)) { try await client.image(at: "/gone.jpg") }
        _ = try? await client.image(at: "/logo.svg")
        #expect(
            Stub.asked.withLock { $0.last?.url?.path } == "/t/p/original/logo.png",
            "a logo TMDb holds as an SVG is fetched as TMDb's PNG of it"
        )
    }
}
