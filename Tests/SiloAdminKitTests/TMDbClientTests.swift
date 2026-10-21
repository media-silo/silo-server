// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloAdminKit
import SiloClient
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

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.asked.withLock { $0.append(request) }
            let (status, body) = Self.handler.withLock { $0(request) }
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    /// A client whose every request is answered by path, the query aside.
    private static func client(_ answers: [String: String], status: Int = 200) -> TMDbClient {
        Stub.asked.withLock { $0 = [] }
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

    @Test func aSearchListsFilmsThenSeries() async throws {
        let client = Self.client([
            "search/movie":
                #"{"results":[{"id":348,"title":"Alien","release_date":"1979-05-25","overview":"In space.","poster_path":"/a.jpg"}]}"#,
            "search/tv": #"{"results":[{"id":121,"name":"Doctor Who","first_air_date":"1963-11-23"}]}"#,
        ])
        let found = try await client.search("who")
        #expect(
            found == [
                TMDb.SearchResult(
                    record: .init(.movie, 348),
                    title: "Alien",
                    year: 1979,
                    overview: "In space.",
                    posterPath: "/a.jpg"
                ),
                TMDb.SearchResult(record: .init(.series, 121), title: "Doctor Who", year: 1963),
            ]
        )
        #expect(Stub.asked.withLock { $0 }.allSatisfy { Self.query(of: $0)["query"] == "who" })
    }

    @Test func aFilmIsReadWithItsIDsAndItsCollection() async throws {
        let client = Self.client([
            "movie/348":
                #"{"id":348,"title":"Alien","release_date":"1979-05-25","overview":"  ","external_ids":{"imdb_id":"tt0078748","wikidata_id":"Q103569"},"belongs_to_collection":{"id":8091}}"#
        ])
        let movie = try await client.movie(348)
        #expect(
            movie
                == TMDb.Movie(
                    id: 348,
                    title: "Alien",
                    year: 1979,
                    overview: nil,
                    externalIDs: TMDb.ExternalIDs(imdb: "tt0078748", wikidata: "Q103569"),
                    collection: 8091
                ),
            "an overview of only spaces is none"
        )
        #expect(Self.query(of: Stub.asked.withLock { $0[0] })["append_to_response"] == "external_ids")
    }

    @Test func aSeriesIsReadWithItsSeasonsAndEpisodeGroups() async throws {
        let client = Self.client([
            "tv/121":
                #"{"id":121,"name":"Doctor Who","first_air_date":"1963-11-23","overview":"A time traveller.","seasons":[{"id":50,"season_number":0,"name":"Specials"},{"id":51,"season_number":1,"name":"Season 1"}],"external_ids":{"tvdb_id":76107},"episode_groups":{"results":[{"id":"g1","name":"Serials"}]}}"#,
            "tv/121/season/1":
                #"{"id":51,"season_number":1,"name":"Season 1","air_date":"1963-11-23","episodes":[{"id":1001,"season_number":1,"episode_number":1,"name":"An Unearthly Child","air_date":"1963-11-23","runtime":25}]}"#,
            "tv/episode_group/g1":
                #"{"id":"g1","name":"Serials","groups":[{"name":"The Daleks","order":2,"episodes":[{"id":1006,"season_number":1,"episode_number":6,"name":"The Dead Planet","order":0}]},{"name":"An Unearthly Child","order":1,"episodes":[{"id":1002,"season_number":1,"episode_number":2,"name":"The Cave of Skulls","order":1},{"id":1001,"season_number":1,"episode_number":1,"name":"An Unearthly Child","order":0}]}]}"#,
            "tv/121/season/1/episode/1/external_ids": #"{"imdb_id":"tt0562992","tvdb_id":183204}"#,
        ])
        let series = try await client.series(121)
        #expect(series.name == "Doctor Who" && series.year == 1963 && series.overview == "A time traveller.")
        #expect(series.seasons.map(\.number) == [0, 1])
        #expect(series.externalIDs.refs == [ExternalRef(provider: .tvdb, value: "76107")])
        #expect(series.episodeGroups == [TMDb.EpisodeGroupSummary(id: "g1", name: "Serials")])

        let season = try await client.season(1, of: 121)
        let first = TMDb.Episode(
            id: 1001,
            season: 1,
            number: 1,
            title: "An Unearthly Child",
            airDate: "1963-11-23",
            runtime: 25
        )
        #expect(season.id == 51 && season.year == 1963 && season.episodes == [first])

        let group = try await client.episodeGroup("g1")
        #expect(group.groups.map(\.name) == ["An Unearthly Child", "The Daleks"], "in TMDb's order")
        #expect(group.groups[0].episodes.map(\.id) == [1001, 1002])

        let ids = try await client.externalIDs(of: first, in: 121)
        #expect(ids == TMDb.ExternalIDs(imdb: "tt0562992", tvdb: "183204"))
    }

    @Test func aCollectionIsReadWithItsFilms() async throws {
        let client = Self.client([
            "collection/8091":
                #"{"id":8091,"name":"Alien Collection","overview":"Ripley.","parts":[{"id":348,"title":"Alien","release_date":"1979-05-25"},{"id":679,"title":"Aliens"}]}"#
        ])
        let collection = try await client.collection(8091)
        #expect(
            collection
                == TMDb.Collection(
                    id: 8091,
                    name: "Alien Collection",
                    overview: "Ripley.",
                    parts: [TMDb.Movie(id: 348, title: "Alien", year: 1979), TMDb.Movie(id: 679, title: "Aliens")]
                )
        )
    }

    @Test func anotherProvidersIDIsFoundAsFilmsAndEpisodes() async throws {
        let client = Self.client([
            "find/tt2779318":
                #"{"movie_results":[{"id":1000,"title":"The Day of the Doctor","release_date":"2013-11-23"}],"tv_episode_results":[{"id":5000,"season_number":0,"episode_number":1,"name":"The Day of the Doctor","show_id":57243}]}"#,
            "find/183204": #"{"movie_results":[],"tv_episode_results":[]}"#,
        ])
        let found = try await client.find(ExternalRef(provider: .imdb, value: "tt2779318"))
        let episode = TMDb.Episode(id: 5000, season: 0, number: 1, title: "The Day of the Doctor")
        #expect(
            found
                == TMDb.Found(
                    movies: [TMDb.Movie(id: 1000, title: "The Day of the Doctor", year: 2013)],
                    episodes: [(series: 57243, episode: episode)]
                )
        )
        #expect(found != TMDb.Found(movies: found.movies), "the episodes are compared too")
        #expect(Set([found, found]).count == 1)
        #expect(Self.query(of: Stub.asked.withLock { $0[0] })["external_source"] == "imdb_id")

        _ = try await client.find(ExternalRef(provider: .tvdb, value: "183204"))
        #expect(Self.query(of: Stub.asked.withLock { $0[1] })["external_source"] == "tvdb_id")
    }
}
