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

/// Wikidata's client against Wikidata's own answers, recorded in `Wikidata/` beside this file, one per
/// request: an item's statements cut to the ones the client reads, and the query service's rows as
/// they came. With `WIKIDATA_RECORD=1` in the environment the same tests ask Wikidata itself and record
/// what it answers, so that the answers can be read again when Wikidata or a query changes. Serial
/// because the handler is one static seam.
@Suite(.serialized)
struct WikidataClientTests {
    private final class Stub: URLProtocol, @unchecked Sendable {
        static let handler = Mutex<@Sendable (URLRequest) -> (Int, Data)>({ _ in (404, Data()) })
        static let asked = Mutex<[URLRequest]>([])
        static let headers = Mutex<[String: String]>([:])

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.asked.withLock { $0.append(request) }
            let (status, body) = Self.handler.withLock { $0(request) }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: Self.headers.withLock { $0 }
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    /// Asks Wikidata itself, and records each answer as the fixture its request is answered from.
    private final class Recorder: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let request = self.request
            // The loading system calls back on its own terms; the protocol object is only ever told
            // what came, once.
            nonisolated(unsafe) let this = self
            Task {
                do {
                    let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
                    let kept = try Fixtures.pruned(data, for: request)
                    if (response as? HTTPURLResponse)?.statusCode == 200 {
                        try kept.write(to: Fixtures.url(for: request))
                    }
                    this.client?.urlProtocol(this, didReceive: response, cacheStoragePolicy: .notAllowed)
                    this.client?.urlProtocol(this, didLoad: kept)
                    this.client?.urlProtocolDidFinishLoading(this)
                } catch {
                    this.client?.urlProtocol(this, didFailWithError: error)
                }
            }
        }

        override func stopLoading() {}
    }

    /// The recorded answers, each named for its request: a search by its text, an item's statements by
    /// the items asked, and a query by its name and the first item it names.
    enum Fixtures {
        static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
            "Wikidata"
        )
        static let recording = ProcessInfo.processInfo.environment["WIKIDATA_RECORD"] == "1"

        /// The statements the client reads, and the qualifiers on them it reads; the rest of an item is
        /// cut from what is recorded.
        static let properties: Set<String> = [
            "P57", "P58", "P161", "P179", "P345", "P361", "P527", "P577", "P580", "P4835", "P4908", "P4947",
            "P4983", "P7043", "P11805", "P12558", "P12559",
        ]
        static let qualifiers: Set<String> = ["P453", "P4633", "P1545"]

        static func query(of request: URLRequest) -> [String: String] {
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        }

        static func name(of request: URLRequest) -> String {
            let query = query(of: request)
            if let sparql = query["query"] {
                let name = sparql.split(separator: "\n").first.map { $0.replacingOccurrences(of: "#silo:", with: "") }
                let ids = sparql.matches(of: /wd:(Q[0-9]+)/).map { String($0.output.1) }
                return "sparql-\(name ?? "query")-\(ids.first ?? "none")-\(ids.count)"
            }
            if query["action"] == "wbgetentities" {
                let ids = (query["ids"] ?? "").split(separator: "|")
                return "entities-\(ids.first ?? "")-\(ids.count)-\(ids.last ?? "")"
            }
            let text = (query["search"] ?? "").lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
            return "\(query["action"] ?? "api")-\(String(text))"
        }

        static func url(for request: URLRequest) -> URL {
            folder.appendingPathComponent(name(of: request) + ".json")
        }

        /// An answer as it is recorded: an item's statements cut to the ones the client reads, without
        /// their references, and anything else as it came.
        static func pruned(_ data: Data, for request: URLRequest) throws -> Data {
            guard query(of: request)["action"] == "wbgetentities",
                var answer = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let entities = answer["entities"] as? [String: [String: Any]]
            else { return data }
            answer["entities"] = entities.mapValues { entity -> [String: Any] in
                var kept = entity.filter { ["id", "missing", "labels", "descriptions"].contains($0.key) }
                let claims = entity["claims"] as? [String: [[String: Any]]] ?? [:]
                kept["claims"] = claims.filter { properties.contains($0.key) }.mapValues { statements in
                    statements.map { statement -> [String: Any] in
                        var cut: [String: Any] = ["rank": statement["rank"] ?? "normal"]
                        if let snak = statement["mainsnak"] as? [String: Any] {
                            cut["mainsnak"] = snak.filter { $0.key == "datavalue" }
                        }
                        if let qualifiers = statement["qualifiers"] as? [String: [[String: Any]]] {
                            let read = qualifiers.filter { self.qualifiers.contains($0.key) }
                                .mapValues { $0.map { $0.filter { $0.key == "datavalue" } } }
                            if !read.isEmpty { cut["qualifiers"] = read }
                        }
                        return cut
                    }
                }
                return kept
            }
            return try JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys, .prettyPrinted])
        }
    }

    /// A client answered from the recorded answers, or recording them.
    private static func recorded() -> WikidataClient {
        Stub.asked.withLock { $0 = [] }
        Stub.headers.withLock { $0 = [:] }
        Stub.handler.withLock {
            $0 = { request in
                guard let data = try? Data(contentsOf: Fixtures.url(for: request)) else {
                    return (404, Data("no recorded answer \(Fixtures.name(of: request))".utf8))
                }
                return (200, data)
            }
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Fixtures.recording ? Recorder.self : Stub.self]
        return WikidataClient(language: "en-GB", session: URLSession(configuration: configuration))
    }

    /// A client whose every request is answered by `answer`.
    private static func client(
        status: Int = 200,
        language: String = "en-GB",
        _ answer: @escaping @Sendable (URLRequest) -> String
    ) -> WikidataClient {
        Stub.asked.withLock { $0 = [] }
        Stub.headers.withLock { $0 = [:] }
        Stub.handler.withLock { $0 = { (status, Data(answer($0).utf8)) } }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Stub.self]
        return WikidataClient(language: language, session: URLSession(configuration: configuration))
    }

    private static let hasKind = #"{"results":{"bindings":[{"class":{"type":"uri","value":"x"}}]}}"#
    private static let noRows = #"{"results":{"bindings":[]}}"#

    @Test func everyRequestNamesSiloAdminAndAsksInTheSettingsLanguage() async throws {
        let client = Self.client { request in
            if Fixtures.query(of: request)["query"] != nil { return Self.hasKind }
            return #"{"entities":{"Q1":{"id":"Q1","labels":{"en":{"value":"Alien"}},"claims":{}}}}"#
        }
        let film = try await client.film("Q1")
        #expect(film.title == "Alien")
        let asked = Stub.asked.withLock { $0 }
        #expect(asked.count == 2, "its kind, then its statements; it credits no one to ask after")
        for request in asked {
            #expect(request.value(forHTTPHeaderField: "User-Agent") == Wikidata.userAgent)
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil, "Wikidata needs no key")
        }
        #expect(asked.map { $0.url?.host } == ["query.wikidata.org", "www.wikidata.org"])
        #expect(Fixtures.query(of: asked[1])["languages"] == "en-gb|en|mul")
    }

    @Test func tooManyAtOnceIsAskedAgainAfterAWaitThatIsNotTooLong() async throws {
        let client = Self.client(status: 429) { _ in "" }
        Stub.headers.withLock { $0 = ["Retry-After": "0"] }
        await #expect(throws: Wikidata.Unavailable.answered(429)) { try await client.film("Q1") }
        #expect(Stub.asked.withLock { $0.count } == WikidataClient.retries + 1)

        let busy = Self.client(status: 429) { _ in "" }
        Stub.headers.withLock { $0 = ["Retry-After": "600"] }
        await #expect(throws: Wikidata.Unavailable.answered(429)) { try await busy.film("Q1") }
        #expect(Stub.asked.withLock { $0.count } == 1, "a wait of ten minutes is not waited")
    }

    @Test func anItemOfAnotherKindOrNoneIsRefused() async throws {
        await #expect(throws: Wikidata.Unavailable.notA(.film, "Q60462338")) {
            try await Self.client { _ in Self.noRows }.film("Q60462338")
        }
        let missing = Self.client { request in
            Fixtures.query(of: request)["query"] != nil
                ? Self.hasKind : #"{"entities":{"Q9":{"id":"Q9","missing":""}}}"#
        }
        await #expect(throws: Wikidata.Unavailable.notThere("Q9")) { try await missing.film("Q9") }
        #expect(Wikidata.Unavailable.notA(.film, "Q60462338").reason == "Wikidata's Q60462338 is not a film.")
        #expect(Wikidata.Unavailable.notThere("Q9").reason == "Wikidata holds no item Q9.")
        #expect(Wikidata.Unavailable.answered(503).reason == "Wikidata answered 503.")
        #expect(
            Wikidata.Unavailable.refused("maxlag", "Waiting for a database server.").reason
                == "Wikidata refused the request: Waiting for a database server."
        )
    }

    /// A day where Wikidata knows the day and the earliest year where it knows only the year; a
    /// deprecated statement read as none, and a preferred one in place of the rest; and credits read
    /// in the order their editors numbered them, then as the item lists them, with the character played.
    @Test func anItemsStatementsAreReadAsWikidataMeansThem() async throws {
        let entity = """
            {"entities":{"Q1":{"id":"Q1","labels":{"en":{"value":"A film"},"en-gb":{"value":"A British film"}},
            "descriptions":[],"claims":{
              "P577":[
                {"rank":"normal","mainsnak":{"datavalue":{"type":"time","value":{"time":"+1979-05-25T00:00:00Z","precision":11}}}},
                {"rank":"normal","mainsnak":{"datavalue":{"type":"time","value":{"time":"+1978-00-00T00:00:00Z","precision":9}}}},
                {"rank":"deprecated","mainsnak":{"datavalue":{"type":"time","value":{"time":"+1970-01-01T00:00:00Z","precision":11}}}}
              ],
              "P4947":[
                {"rank":"normal","mainsnak":{"datavalue":{"type":"string","value":"1"}}},
                {"rank":"preferred","mainsnak":{"datavalue":{"type":"string","value":"348"}}}
              ],
              "P161":[
                {"rank":"normal","mainsnak":{"datavalue":{"type":"wikibase-entityid","value":{"id":"Q10"}}}},
                {"rank":"normal","mainsnak":{"datavalue":{"type":"wikibase-entityid","value":{"id":"Q20"}}},
                 "qualifiers":{"P4633":[{"datavalue":{"type":"string","value":"Ripley"}}],
                   "P1545":[{"datavalue":{"type":"string","value":"1"}}]}}
              ]
            }}}}
            """
        let people = """
            {"results":{"bindings":[
              {"item":{"type":"uri","value":"http://www.wikidata.org/entity/Q20"},"itemLabel":{"type":"literal","value":"Sigourney Weaver"},
               "tmdb":{"type":"literal","value":"10205"}},
              {"item":{"type":"uri","value":"http://www.wikidata.org/entity/Q10"},"itemLabel":{"type":"literal","value":"Q10"}}
            ]}}
            """
        let client = Self.client { request in
            let query = Fixtures.query(of: request)["query"] ?? ""
            return query.hasPrefix("#silo:kind") ? Self.hasKind : query.hasPrefix("#silo:people") ? people : entity
        }
        let film = try await client.film("Q1")
        let asked = Stub.asked.withLock { $0 }.compactMap { Fixtures.query(of: $0)["query"] }
        #expect(
            asked.last?.contains(#"wikibase:language "en-gb,en,mul""#) == true,
            "people named in the same languages"
        )
        #expect(film.title == "A British film", "in the settings' language before its base language")
        #expect(film.description == nil)
        #expect(film.premiered == CalendarDate("1979-05-25"))
        #expect(film.year == 1978)
        #expect(
            film.refs == [ExternalRef(provider: .wikidata, value: "Q1"), ExternalRef(provider: .tmdb, value: "348")]
        )
        #expect(
            film.cast == [
                Wikidata.Credit(
                    person: "Q20",
                    name: "Sigourney Weaver",
                    character: "Ripley",
                    refs: [
                        ExternalRef(provider: .wikidata, value: "Q20"), ExternalRef(provider: .tmdb, value: "10205"),
                    ]
                ),
                Wikidata.Credit(person: "Q10", name: "Q10", refs: [ExternalRef(provider: .wikidata, value: "Q10")]),
            ]
        )
    }

    @Test func aSearchFindsFilmsSeriesAndCollectionsTheMostKnownFirst() async throws {
        let found = try await Self.recorded().search("Alien")
        #expect(
            found.first
                == Wikidata.SearchResult(
                    id: "Q103569",
                    kind: .film,
                    title: "Alien",
                    description: "1979 film by Ridley Scott",
                    year: 1979
                )
        )
        #expect(found.contains { $0.id == "Q1990792" && $0.kind == .collection })
        #expect(!found.contains { $0.id == "Q15613717" }, "a video game is none of them")
    }

    @Test func aSearchInALanguageWikidataRefusesIsAskedInTheNext() async throws {
        let refused = #"{"error":{"code":"badvalue","info":"Unrecognized value for parameter \"language\": en-au."}}"#
        let client = Self.client(language: "en-AU") { request in
            let query = Fixtures.query(of: request)
            if query["query"] != nil {
                return #"{"results":{"bindings":[{"item":{"type":"uri","value":"x/Q34316"},"#
                    + #""class":{"type":"uri","value":"x/\#(Wikidata.Kind.series.itemClass)"},"#
                    + #""links":{"type":"literal","value":"90"}}]}}"#
            }
            return query["language"] == "en-au" ? refused : #"{"search":[{"id":"Q34316","label":"Doctor Who"}]}"#
        }
        let found = try await client.search("Doctor Who")
        #expect(found.map(\.title) == ["Doctor Who"])
        let searched = Stub.asked.withLock { $0 }.compactMap { Fixtures.query(of: $0)["language"] }
        #expect(searched == ["en-au", "en"])

        let everywhere = Self.client(language: "en-AU") { _ in refused }
        await #expect(
            throws: Wikidata.Unavailable.refused("badvalue", "Unrecognized value for parameter \"language\": en-au.")
        ) {
            try await everywhere.search("Doctor Who")
        }
        let tried = Stub.asked.withLock { $0 }.compactMap { Fixtures.query(of: $0)["language"] }
        #expect(tried == ["en-au", "en", "mul"], "refused in every language, the last refusal is thrown")

        let refusing = Self.client { _ in #"{"error":{"code":"maxlag","info":"Waiting for a database server."}}"# }
        await #expect(throws: Wikidata.Unavailable.refused("maxlag", "Waiting for a database server.")) {
            try await refusing.search("Doctor Who")
        }
    }

    @Test func aFilmIsReadWithItsCreditsAndItsIDs() async throws {
        let alien = try await Self.recorded().film("Q103569")
        #expect(alien.title == "Alien")
        #expect(alien.premiered == CalendarDate("1979-05-25"))
        #expect(alien.ref(.imdb) == ExternalRef(provider: .imdb, value: "tt0078748"))
        #expect(alien.ref(.tmdb) == ExternalRef(provider: .tmdb, value: "348"))
        #expect(alien.directors.map(\.name) == ["Ridley Scott"])
        #expect(alien.directors.first?.refs.contains(ExternalRef(provider: .tmdb, value: "578")) == true)
        #expect(alien.screenwriters.map(\.name).contains("Dan O'Bannon"))
        #expect(alien.cast.first?.name == "Yaphet Kotto", "in the order the item lists them, which is not the billing")
        let ripley = try #require(alien.cast.first { $0.name == "Sigourney Weaver" })
        #expect(ripley.character == "Ellen Ripley")
        #expect(ripley.refs.contains(ExternalRef(provider: .imdb, value: "nm0000244")))
    }

    @Test func aSeriesIsReadWithItsSeasonsInOrder() async throws {
        let andor = try await Self.recorded().series("Q60462338")
        #expect(andor.work.title == "Andor")
        #expect(andor.work.ref(.tmdb) == ExternalRef(provider: .tmdb, value: "83867"))
        #expect(andor.seasons.map(\.id) == ["Q119129258", "Q126908011"])
        #expect(andor.seasons.map(\.ordinal) == [1, 2])
        #expect(andor.seasons.first?.title == "Andor, season 1")
        #expect(andor.specials.isEmpty, "every episode of Andor's is in a season")
    }

    /// *Doctor Who*'s specials are the episodes Wikidata files beneath the series and in no season, by
    /// the date each first aired, one it does not date last.
    @Test func aSeriesSpecialsAreItsEpisodesInNoSeason() async throws {
        let client = Self.recorded()
        let doctorWho = try await client.series("Q34316")
        #expect(
            doctorWho.specials.map(\.title) == [
                "The End of Time – Part Two", "The Night of the Doctor", "The Last Day", "Legend of the Sea Devils",
                "The Power of the Doctor", "The Giggle", "Destination: Skaro",
            ]
        )
        let giggle = try #require(doctorWho.specials.first { $0.title == "The Giggle" })
        #expect(giggle.premiered == CalendarDate("2023-12-09"))
        #expect(giggle.ref(.tmdb) == ExternalRef(provider: .tmdb, value: "4930545"))
        #expect(giggle.partOf.contains("Q34316"), "and whatever other series Wikidata files it in")
        #expect(try await client.episodes([giggle.id]) == [giggle], "read again as an episode alone")
    }

    @Test func aSeasonIsReadAsItsEpisodesInOrder() async throws {
        let season = try await Self.recorded().season("Q119129258")
        #expect(season.ordinal == 1)
        #expect(season.work.ref(.tmdb) == ExternalRef(provider: .tmdb, value: "112257"))
        let episodes = season.members.map(\.work)
        #expect(episodes.count == 12)
        #expect(season.members.allSatisfy { if case .episode = $0 { true } else { false } })
        let kassa = try #require(episodes.first)
        #expect(kassa.title == "Kassa")
        #expect(kassa.premiered == CalendarDate("2022-09-21"))
        #expect(
            kassa.refs == [
                ExternalRef(provider: .wikidata, value: "Q118877501"), ExternalRef(provider: .imdb, value: "tt9419264"),
                ExternalRef(provider: .tmdb, value: "2625077"), ExternalRef(provider: .tvdb, value: "9197800"),
            ]
        )
        #expect(kassa.directors.map(\.name) == ["Toby Haynes"])
        #expect(kassa.screenwriters.map(\.name) == ["Tony Gilroy"])
        #expect(episodes.last?.title == "Rix Road")
    }

    /// *Doctor Who*'s thirteenth season numbers its six serials and its twenty-six parts with the
    /// same ordinal: each part is placed in the serial it is part of, in its season's order.
    @Test func aSeasonIsReadAsItsSerialsWithTheirParts() async throws {
        let season = try await Self.recorded().season("Q1611030")
        let serials = season.members.compactMap { member -> Wikidata.Serial? in
            if case .serial(let serial) = member { return serial }
            return nil
        }
        #expect(serials.count == season.members.count)
        #expect(
            serials.map(\.work.title) == [
                "Terror of the Zygons", "Planet of Evil", "Pyramids of Mars", "The Android Invasion",
                "The Brain of Morbius", "The Seeds of Doom",
            ]
        )
        let pyramids = serials[2]
        #expect(
            pyramids.parts.map(\.title) == [
                "Pyramids of Mars I", "Pyramids of Mars II", "Pyramids of Mars III", "Pyramids of Mars IV",
            ]
        )
        #expect(pyramids.parts.first?.premiered == CalendarDate("1975-10-25"))
        #expect(pyramids.work.premiered == CalendarDate("1975-10-25"), "the earliest of its dates")
        #expect(serials.map(\.parts.count) == [4, 4, 4, 4, 4, 6])
    }

    @Test func aSerialIsReadWithItsPartsInOrder() async throws {
        let pyramids = try await Self.recorded().serial("Q4997878")
        #expect(pyramids.work.title == "Pyramids of Mars")
        #expect(pyramids.parts.map(\.id) == ["Q22342193", "Q22342194", "Q22342195", "Q22342196"])
    }

    @Test func aCollectionIsReadWithItsFilmsInTheOrderTheyCameOut() async throws {
        let alien = try await Self.recorded().collection("Q1990792")
        #expect(alien.work.ref(.tmdb) == ExternalRef(provider: .tmdb, value: "8091"))
        #expect(alien.films.prefix(4).map(\.id) == ["Q103569", "Q104814", "Q108543", "Q458314"])
        #expect(alien.films.first?.title == "Alien")
    }
}
