// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SmdKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Wikidata, read without a key: items' own statements through its API, in the order the item lists
/// them, and what points at an item — a series' seasons, a season's episodes and serials, a serial's
/// parts, a collection's films — and who people are through its query service, by SPARQL. Labels are
/// asked in the language the settings name, then its base language, then those Wikidata gives every
/// language and English.
public struct WikidataClient: WikidataSource {
    public let language: String
    let session: URLSession
    let api = URL(string: "https://www.wikidata.org/w/api.php")!
    let sparql = URL(string: "https://query.wikidata.org/sparql")!

    public init(language: String, session: URLSession = .shared) {
        self.language = language
        self.session = session
    }

    /// The languages labels are asked in, best first, as Wikidata spells them.
    var languages: [String] {
        let code = language.lowercased()
        let base = code.split(separator: "-").first.map(String.init) ?? code
        return [code, base, "mul", "en"].reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    public func search(_ text: String) async throws -> [Wikidata.SearchResult] {
        let language = languages[0]
        let asked = ["action": "wbsearchentities", "search": text, "language": language, "uselang": language]
        let found = try await ask(asked.merging(["type": "item", "limit": "50"]) { $1 }, SearchJSON.self).search
        guard !found.isEmpty else { return [] }
        let classified = try await classify(found.map(\.id))
        let results = found.compactMap { result -> Wikidata.SearchResult? in
            guard let known = classified[result.id] else { return nil }
            return Wikidata.SearchResult(
                id: result.id,
                kind: known.kind,
                title: result.label ?? result.match?.text ?? result.id,
                description: result.description,
                year: known.year
            )
        }
        // The most widely known first, and otherwise in the order Wikidata found them.
        let position = Dictionary(uniqueKeysWithValues: results.enumerated().map { ($1.id, $0) })
        return results.sorted {
            let left = classified[$0.id]?.links ?? 0
            let right = classified[$1.id]?.links ?? 0
            return left != right ? left > right : position[$0.id]! < position[$1.id]!
        }
    }

    /// What a search found that is of a kind searched for: its kind, how many Wikipedias link to it,
    /// and the earliest year it was shown.
    private struct Classified {
        var kind: Wikidata.Kind
        var links: Int
        var year: Int?
    }

    private func classify(_ ids: [String]) async throws -> [String: Classified] {
        let classes = Wikidata.Kind.searched.map { "wd:\($0.itemClass)" }.joined(separator: " ")
        let rows = try await select(
            "search",
            """
            SELECT ?item ?class ?links ?date WHERE {
              VALUES ?item { \(ids.map { "wd:\($0)" }.joined(separator: " ")) }
              VALUES ?class { \(classes) }
              ?item wdt:P31/wdt:P279* ?class .
              ?item wikibase:sitelinks ?links .
              OPTIONAL { ?item wdt:P577|wdt:P580 ?date }
            }
            """
        )
        let rank = { (kind: Wikidata.Kind) in Wikidata.Kind.searched.firstIndex(of: kind) ?? Int.max }
        var classified: [String: Classified] = [:]
        for row in rows {
            guard let item = row["item"],
                let kind = Wikidata.Kind.searched.first(where: { $0.itemClass == row["class"] })
            else { continue }
            var known = classified[item] ?? Classified(kind: kind, links: 0)
            // An item of two kinds is the one listed first: a series that is also a film series is a series.
            if rank(kind) < rank(known.kind) { known.kind = kind }
            known.links = row["links"].flatMap(Int.init) ?? 0
            if let year = row["date"].flatMap(Self.year) { known.year = min(known.year ?? year, year) }
            classified[item] = known
        }
        return classified
    }

    public func film(_ id: String) async throws -> Wikidata.Work {
        try await expect(id, is: .film)
        return try await works(entities([id])) { _ in .film }[0]
    }

    public func series(_ id: String) async throws -> Wikidata.Series {
        try await expect(id, is: .series)
        async let work = works(entities([id])) { _ in .series }
        let rows = try await select(
            "seasons",
            """
            SELECT ?item ?itemLabel ?ordinal ?date WHERE {
              ?item p:P179 ?statement . ?statement ps:P179 wd:\(id) .
              OPTIONAL { ?statement pq:P1545 ?ordinal }
              ?item wdt:P31/wdt:P279* wd:\(Wikidata.Kind.season.itemClass) .
              OPTIONAL { ?item wdt:P580|wdt:P577 ?date }
              SERVICE wikibase:label { bd:serviceParam wikibase:language "\(languages.joined(separator: ","))". }
            }
            """
        )
        var seasons: [String: (summary: Wikidata.SeasonSummary, first: String?)] = [:]
        for row in rows {
            guard let item = row["item"] else { continue }
            let title = row["itemLabel"].flatMap { $0 == item ? nil : $0 } ?? item
            var season = seasons[item] ?? (Wikidata.SeasonSummary(id: item, ordinal: nil, title: title), nil)
            season.summary.ordinal = season.summary.ordinal ?? row["ordinal"].flatMap(Int.init)
            if let date = row["date"], season.first.map({ date < $0 }) ?? true { season.first = date }
            seasons[item] = season
        }
        let ordered = seasons.values.sorted {
            Self.order($0.summary.ordinal, $0.first, $0.summary.id)
                < Self.order($1.summary.ordinal, $1.first, $1.summary.id)
        }
        return Wikidata.Series(work: try await work[0], seasons: ordered.map(\.summary))
    }

    public func season(_ id: String) async throws -> Wikidata.Season {
        try await expect(id, is: .season)
        let rows = try await select(
            "members",
            """
            SELECT ?item ?ordinal ?serial ?isSerial WHERE {
              ?item p:P4908 ?statement . ?statement ps:P4908 wd:\(id) .
              OPTIONAL { ?statement pq:P1545 ?ordinal }
              OPTIONAL { ?item wdt:P361 ?serial }
              BIND(EXISTS { ?item wdt:P31/wdt:P279* wd:\(Wikidata.Kind.serial.itemClass) } AS ?isSerial)
            }
            """
        )
        let numbered = Numbered(rows)
        let (members, ordinals) = (numbered.items, numbered.ordinals)
        var serials: Set<String> = []
        var partOf: [String: Set<String>] = [:]
        for row in rows {
            guard let item = row["item"] else { continue }
            if row["isSerial"] == "true" { serials.insert(item) }
            if let serial = row["serial"] { partOf[item, default: []].insert(serial) }
        }
        let items = try await entities([id] + members)
        let read = try await works(items) { $0.id == id ? .season : serials.contains($0.id) ? .serial : .episode }
        let season = read[0]
        let works = Dictionary(uniqueKeysWithValues: zip(members, read.dropFirst()))
        let ordinal = items[0].qualifier("P1545", of: "P179").flatMap(Int.init)

        func ordered(_ ids: [String]) -> [String] {
            let byDate = ids.contains(where: serials.contains) && ids.contains(where: { !serials.contains($0) })
            return ids.sorted {
                let left = works[$0]
                let right = works[$1]
                if byDate {
                    return Self.order(nil, left?.premiered?.description, $0)
                        < Self.order(nil, right?.premiered?.description, $1)
                }
                return Self.order(ordinals[$0], left?.premiered?.description, $0)
                    < Self.order(ordinals[$1], right?.premiered?.description, $1)
            }
        }
        let parts = members.filter { !serials.contains($0) && !(partOf[$0] ?? []).isDisjoint(with: serials) }
        let loose = members.filter { !serials.contains($0) && !parts.contains($0) }
        let held: [Wikidata.Member] = ordered(Array(serials) + loose).compactMap { item in
            guard let work = works[item] else { return nil }
            guard serials.contains(item) else { return .episode(work) }
            let own = parts.filter { partOf[$0]?.contains(item) == true }
            return .serial(Wikidata.Serial(work: work, parts: ordered(own).compactMap { works[$0] }))
        }
        return Wikidata.Season(work: season, ordinal: ordinal, members: held)
    }

    public func serial(_ id: String) async throws -> Wikidata.Serial {
        try await expect(id, is: .serial)
        let rows = try await select(
            "parts",
            """
            SELECT ?item ?ordinal WHERE {
              ?item wdt:P361 wd:\(id) .
              OPTIONAL { ?item p:P4908 ?statement . ?statement pq:P1545 ?ordinal }
            }
            """
        )
        let numbered = Numbered(rows)
        let (parts, ordinals) = (numbered.items, numbered.ordinals)
        let items = try await entities([id] + parts)
        // A part the serial lists, in the order it lists them, where its season numbers none.
        let listed = items[0].items("P527")
        let read = try await works(items) { $0.id == id ? .serial : .episode }
        let works = Dictionary(uniqueKeysWithValues: zip(parts, read.dropFirst()))
        let ordered = parts.sorted {
            Self.order(ordinals[$0] ?? listed.firstIndex(of: $0), works[$0]?.premiered?.description, $0)
                < Self.order(ordinals[$1] ?? listed.firstIndex(of: $1), works[$1]?.premiered?.description, $1)
        }
        return Wikidata.Serial(work: read[0], parts: ordered.compactMap { works[$0] })
    }

    public func collection(_ id: String) async throws -> Wikidata.Collection {
        try await expect(id, is: .collection)
        let rows = try await select(
            "films",
            """
            SELECT ?item ?ordinal WHERE {
              ?item p:P179 ?statement . ?statement ps:P179 wd:\(id) .
              OPTIONAL { ?statement pq:P1545 ?ordinal }
              ?item wdt:P31/wdt:P279* wd:\(Wikidata.Kind.film.itemClass) .
            }
            """
        )
        let numbered = Numbered(rows)
        let (films, ordinals) = (numbered.items, numbered.ordinals)
        let read = try await works(entities([id] + films)) { $0.id == id ? .collection : .film }
        let works = Dictionary(uniqueKeysWithValues: zip(films, read.dropFirst()))
        let ordered = films.sorted {
            Self.order(ordinals[$0], works[$0]?.premiered?.description, $0)
                < Self.order(ordinals[$1], works[$1]?.premiered?.description, $1)
        }
        return Wikidata.Collection(work: read[0], films: ordered.compactMap { works[$0] })
    }

    /// The key a list is ordered by: a number first, those with none after; then a first date, those
    /// with none after; then the id, so that the order is the same however Wikidata answers.
    static func order(_ ordinal: Int?, _ date: String?, _ id: String) -> Order {
        Order(ordinal: ordinal ?? Int.max, date: date ?? "~", id: id)
    }

    struct Order: Comparable {
        var ordinal: Int
        var date: String
        var id: String

        static func < (left: Order, right: Order) -> Bool {
            (left.ordinal, left.date) != (right.ordinal, right.date)
                ? (left.ordinal, left.date) < (right.ordinal, right.date)
                : (left.id.count, left.id) < (right.id.count, right.id)
        }
    }

    /// The items a query's rows name, in the order first named, and the least number each is given.
    struct Numbered {
        var items: [String] = []
        var ordinals: [String: Int] = [:]

        init(_ rows: [[String: String]]) {
            for row in rows {
                guard let item = row["item"] else { continue }
                if !items.contains(item) { items.append(item) }
                if let ordinal = row["ordinal"].flatMap(Int.init) {
                    ordinals[item] = min(ordinals[item] ?? ordinal, ordinal)
                }
            }
        }
    }

    static func year(_ date: String) -> Int? {
        Int(date.drop(while: { $0 == "+" }).prefix(4))
    }

    /// Refuses an item that is not of the kind it is read as.
    private func expect(_ id: String, is kind: Wikidata.Kind) async throws {
        let rows = try await select(
            "kind",
            "SELECT ?class WHERE { wd:\(id) wdt:P31/wdt:P279* ?class . VALUES ?class { wd:\(kind.itemClass) } }"
        )
        guard !rows.isEmpty else { throw Wikidata.Unavailable.notA(kind, id) }
    }
}
