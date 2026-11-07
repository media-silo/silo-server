// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SmdKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Statements read as works

extension WikidataClient {
    /// Items read as works, each of the kind given for it, with its credits, the people in them named
    /// and known by their ids.
    func works(_ items: [WikidataEntity], kind: (WikidataEntity) -> Wikidata.Kind) async throws -> [Wikidata.Work] {
        let credited = items.flatMap { item in
            Self.creditProperties.flatMap { item.statements($0) }.flatMap { claim in
                [claim.value?.item].compactMap { $0 } + (claim.qualifiers["P453"] ?? []).compactMap(\.item)
            }
        }
        let people = try await people(Array(Set(credited)))
        return items.map { $0.work(as: kind($0), people: people) }
    }

    static let creditProperties = ["P57", "P58", "P161"]

    /// Items' own statements, asked fifty at a time as the API allows, in the order asked.
    func entities(_ ids: [String]) async throws -> [WikidataEntity] {
        var read: [String: WikidataEntity] = [:]
        for start in stride(from: 0, to: ids.count, by: 50) {
            let batch = Array(ids[start..<min(start + 50, ids.count)])
            let asked = ["action": "wbgetentities", "ids": batch.joined(separator: "|")]
            let reading = ["props": "labels|descriptions|claims", "languages": languages.joined(separator: "|")]
            let answer = try await ask(asked.merging(reading) { $1 }, EntitiesJSON.self)
            for (id, entity) in answer.entities ?? [:] where entity.missing == nil {
                read[id] = WikidataEntity(entity, languages: languages)
            }
        }
        return try ids.map {
            guard let entity = read[$0] else { throw Wikidata.Unavailable.notThere($0) }
            return entity
        }
    }

    /// Who each person or character is: the label, and for a person the ids IMDb, TMDb and TVDB give them.
    func people(_ ids: [String]) async throws -> [String: Person] {
        var people: [String: Person] = [:]
        for start in stride(from: 0, to: ids.count, by: 100) {
            let batch = ids.sorted()[start..<min(start + 100, ids.count)]
            let rows = try await select(
                "people",
                """
                SELECT ?item ?itemLabel ?imdb ?tmdb ?tvdb WHERE {
                  VALUES ?item { \(batch.map { "wd:\($0)" }.joined(separator: " ")) }
                  OPTIONAL { ?item wdt:P345 ?imdb }
                  OPTIONAL { ?item wdt:P4985 ?tmdb }
                  OPTIONAL { ?item wdt:P7920 ?tvdb }
                  SERVICE wikibase:label { bd:serviceParam wikibase:language "\(languages.joined(separator: ","))". }
                }
                """
            )
            for row in rows {
                guard let item = row["item"] else { continue }
                var person = people[item] ?? Person(name: row["itemLabel"].flatMap { $0 == item ? nil : $0 }, refs: [])
                for (key, provider) in [("imdb", Provider.imdb), ("tmdb", .tmdb), ("tvdb", .tvdb)] {
                    if let value = row[key], !person.refs.contains(ExternalRef(provider: provider, value: value)) {
                        person.refs.append(ExternalRef(provider: provider, value: value))
                    }
                }
                people[item] = person
            }
        }
        return people
    }

    struct Person: Hashable, Sendable {
        var name: String?
        var refs: [ExternalRef]
    }
}

// MARK: - The wire

extension WikidataClient {
    /// How many times a request Wikidata answers 429, too many at once, is asked again.
    public static let retries = 3
    /// The longest wait, in seconds, the client keeps to before asking again. The query service may
    /// name minutes once a client has asked a lot, and a console waiting that long looks stuck, so a
    /// longer wait is answered as 429 for the operator to try later.
    public static let longestWait = 30.0

    /// The rows a SPARQL query answers, each variable's value as text: an item by its id alone. The
    /// query is marked with its name, so that what answers in tests can tell the queries apart.
    func select(_ name: String, _ query: String) async throws -> [[String: String]] {
        let answer = try await get(sparql, ["query": "#silo:\(name)\n\(query)", "format": "json"], SPARQLJSON.self)
        return answer.results.bindings.map { binding in
            binding.mapValues { value in
                value.type == "uri" ? String(value.value.split(separator: "/").last ?? "") : value.value
            }
        }
    }

    /// An answer of Wikidata's API to an action and its parameters.
    func ask<Answer: Decodable>(_ parameters: [String: String], _ type: Answer.Type) async throws -> Answer {
        try await get(api, parameters.merging(["format": "json"]) { $1 }, type)
    }

    private func get<Answer: Decodable>(
        _ url: URL,
        _ query: [String: String],
        _ type: Answer.Type
    ) async throws -> Answer {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.setValue(Wikidata.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, status) = try await answer(to: request)
        guard (200..<300).contains(status) else { throw Wikidata.Unavailable.answered(status) }
        return try JSONDecoder().decode(type, from: data)
    }

    /// Wikidata's answer to a request, asked again after the wait its `Retry-After` names, or a second,
    /// while it says too many are being asked at once and the wait is no longer than `longestWait`.
    private func answer(to request: URLRequest) async throws -> (Data, Int) {
        var attempt = 0
        while true {
            let (data, response) = try await session.data(for: request)
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            let wait = http?.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 1
            guard status == 429, attempt < Self.retries, wait <= Self.longestWait else { return (data, status) }
            attempt += 1
            try await Task.sleep(for: .seconds(max(0, wait)))
        }
    }

    // Wikidata's own spellings, decoded as they come.
    // swiftlint:disable nesting
    struct SearchJSON: Decodable {
        struct Result: Decodable {
            struct Match: Decodable { var text: String }
            var id: String
            var label: String?
            var description: String?
            var match: Match?
        }
        var search: [Result]
    }

    struct SPARQLJSON: Decodable {
        struct Value: Decodable {
            var type: String
            var value: String
        }
        struct Results: Decodable { var bindings: [[String: Value]] }
        var results: Results
    }
    // swiftlint:enable nesting
}
