// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import SmdKit

/// An item's own statements as Wikidata's API answers them, in the order the item lists them, with its
/// label and description in the first of the client's languages that has one.
struct WikidataEntity: Hashable, Sendable {
    var id: String
    var label: String?
    var description: String?
    var claims: [String: [Claim]]

    struct Claim: Hashable, Sendable {
        var value: Value?
        var rank: String
        var qualifiers: [String: [Value]]
    }

    enum Value: Hashable, Sendable {
        case item(String)
        case string(String)
        /// A point in time, as Wikidata writes it, `+1979-05-25T00:00:00Z`, and its precision: 11
        /// for a day, 10 for a month, 9 for a year.
        case time(String, precision: Int)
        case other

        var item: String? {
            if case .item(let id) = self { return id }
            return nil
        }

        var string: String? {
            if case .string(let text) = self { return text }
            return nil
        }
    }

    init(id: String, label: String? = nil, description: String? = nil, claims: [String: [Claim]] = [:]) {
        self.id = id
        self.label = label
        self.description = description
        self.claims = claims
    }

    init(_ json: WikidataClient.EntityJSON, languages: [String]) {
        self.id = json.id ?? ""
        self.label = languages.lazy.compactMap { json.labels[$0]?.value }.first
        self.description = languages.lazy.compactMap { json.descriptions[$0]?.value }.first
        self.claims = json.claims.mapValues { claims in
            claims.map { claim in
                Claim(
                    value: claim.mainsnak.datavalue.map(Value.init),
                    rank: claim.rank,
                    qualifiers: (claim.qualifiers ?? [:]).mapValues { $0.compactMap(\.datavalue).map(Value.init) }
                )
            }
        }
    }

    /// A property's statements as Wikidata's truthy ones are: the preferred where there are any,
    /// and otherwise every one not deprecated, in the order the item lists them.
    func statements(_ property: String) -> [Claim] {
        let all = (claims[property] ?? []).filter { $0.rank != "deprecated" }
        let preferred = all.filter { $0.rank == "preferred" }
        return preferred.isEmpty ? all : preferred
    }

    /// Every statement of a property not deprecated, in the order the item lists them: for credits,
    /// where a preferred one marks a lead rather than the only one.
    func listed(_ property: String) -> [Claim] {
        (claims[property] ?? []).filter { $0.rank != "deprecated" }
    }

    func items(_ property: String) -> [String] {
        statements(property).compactMap { $0.value?.item }
    }

    func strings(_ property: String) -> [String] {
        statements(property).compactMap { $0.value?.string }
    }

    /// A qualifier's first value on a property's first statement that has one, as text.
    func qualifier(_ qualifier: String, of property: String) -> String? {
        for claim in statements(property) {
            for value in claim.qualifiers[qualifier] ?? [] {
                if let text = value.string { return text }
            }
        }
        return nil
    }

    /// The earliest of the item's dates of first publication, or of starting for a season: to the
    /// day where Wikidata knows the day, and the earliest year it knows at all.
    var firstDate: (day: CalendarDate?, year: Int?) {
        var day: CalendarDate?
        var year: Int?
        for property in ["P577", "P580"] {
            for claim in statements(property) {
                guard case .time(let time, let precision)? = claim.value, time.hasPrefix("+") else { continue }
                let text = time.dropFirst()
                if let known = Int(text.prefix(4)) { year = min(year ?? known, known) }
                if precision >= 11, let date = CalendarDate(String(text.prefix(10))) {
                    day = day.map { min($0, date) } ?? date
                }
            }
            if year != nil { break }
        }
        return (day, year)
    }

    /// The properties naming the ids providers give an item of a kind, in the order its references
    /// are listed.
    static func idProperties(of kind: Wikidata.Kind) -> [(property: String, provider: Provider)] {
        switch kind {
        case .film: [("P345", .imdb), ("P4947", .tmdb)]
        case .collection: [("P11805", .tmdb)]
        case .series: [("P345", .imdb), ("P4983", .tmdb), ("P4835", .tvdb)]
        case .season: [("P12558", .tmdb)]
        case .serial: [("P345", .imdb)]
        case .episode: [("P345", .imdb), ("P12559", .tmdb), ("P7043", .tvdb)]
        }
    }

    /// The item read as a work of a kind, its credits named from `people`.
    func work(as kind: Wikidata.Kind, people: [String: WikidataClient.Person]) -> Wikidata.Work {
        let date = firstDate
        let refs =
            [ExternalRef(provider: .wikidata, value: id)]
            + Self.idProperties(of: kind).flatMap { property, provider in
                strings(property).prefix(1).map { ExternalRef(provider: provider, value: $0) }
            }
        func credits(_ property: String) -> [Wikidata.Credit] {
            // The order the item lists them in, which is its editors' rather than a billing, unless
            // they numbered them.
            let numbered = listed(property).enumerated().sorted {
                let left = $0.element.qualifiers["P1545"]?.first?.string.flatMap(Int.init) ?? Int.max
                let right = $1.element.qualifiers["P1545"]?.first?.string.flatMap(Int.init) ?? Int.max
                return (left, $0.offset) < (right, $1.offset)
            }
            return numbered.map(\.element).compactMap { claim in
                guard let person = claim.value?.item else { return nil }
                let known = people[person]
                let character =
                    (claim.qualifiers["P453"] ?? []).compactMap(\.item).compactMap { people[$0]?.name }.first
                    ?? (claim.qualifiers["P4633"] ?? []).compactMap(\.string).first
                return Wikidata.Credit(
                    person: person,
                    name: known?.name ?? person,
                    character: character,
                    refs: [ExternalRef(provider: .wikidata, value: person)] + (known?.refs ?? [])
                )
            }
        }
        return Wikidata.Work(
            id: id,
            title: label ?? id,
            description: description,
            premiered: date.day,
            year: date.year,
            refs: refs,
            directors: credits("P57"),
            screenwriters: credits("P58"),
            cast: credits("P161"),
            partOf: items("P179")
        )
    }
}

// MARK: - Wikidata's own spellings

// swiftlint:disable nesting
extension WikidataClient {
    struct EntitiesJSON: Decodable {
        var entities: [String: EntityJSON]?
    }

    /// An entity as `wbgetentities` answers it. An entity with no labels, descriptions or claims has
    /// them as an empty list rather than an empty object, so each is read as either.
    struct EntityJSON: Decodable {
        var id: String?
        var missing: String?
        var labels: [String: Text]
        var descriptions: [String: Text]
        var claims: [String: [ClaimJSON]]

        struct Text: Decodable { var value: String }

        enum CodingKeys: String, CodingKey { case id, missing, labels, descriptions, claims }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(String.self, forKey: .id)
            missing = try container.decodeIfPresent(String.self, forKey: .missing)
            labels = (try? container.decode([String: Text].self, forKey: .labels)) ?? [:]
            descriptions = (try? container.decode([String: Text].self, forKey: .descriptions)) ?? [:]
            claims = (try? container.decode([String: [ClaimJSON]].self, forKey: .claims)) ?? [:]
        }
    }

    struct ClaimJSON: Decodable {
        var mainsnak: SnakJSON
        var rank: String
        var qualifiers: [String: [SnakJSON]]?
    }

    struct SnakJSON: Decodable {
        var datavalue: DataValueJSON?
    }

    /// A snak's value: an item's id, a string or an external id, a time and its precision, or
    /// something the console does not read.
    struct DataValueJSON: Decodable {
        var read: WikidataEntity.Value

        enum CodingKeys: String, CodingKey { case type, value }
        struct ItemJSON: Decodable { var id: String }
        struct TimeJSON: Decodable {
            var time: String
            var precision: Int
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(String.self, forKey: .type) {
            case "wikibase-entityid":
                read = .item(try container.decode(ItemJSON.self, forKey: .value).id)
            case "string":
                read = .string(try container.decode(String.self, forKey: .value))
            case "time":
                let time = try container.decode(TimeJSON.self, forKey: .value)
                read = .time(time.time, precision: time.precision)
            default:
                read = .other
            }
        }
    }
}

// swiftlint:enable nesting

extension WikidataEntity.Value {
    init(_ json: WikidataClient.DataValueJSON) {
        self = json.read
    }
}
