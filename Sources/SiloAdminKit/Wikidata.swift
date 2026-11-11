// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import SmdKit

/// Wikidata, read for facts: what a work is called, when it was first shown, who made it and appeared
/// in it, what it holds and in what order, and the ids other providers know it by. Its statements are
/// CC0, so what is read here needs no attribution and may go to smddb.
public enum Wikidata {
    /// The User-Agent every request carries, naming SiloAdmin and where it is kept, as Wikimedia's
    /// policy asks of a client.
    public static let userAgent = "SiloAdmin/1.0 (https://github.com/media-silo/silo-server)"

    /// What an item is, as far as the console reads it: told by the classes it is an instance of.
    public enum Kind: String, Hashable, Sendable, Codable, CaseIterable {
        case film
        case collection
        case series
        case season
        case serial
        case episode

        /// The class an item of the kind is an instance of, or of a subclass of: a film, a film series,
        /// a television series, a television series season, a part of a television season, as a
        /// *Doctor Who* serial is, and a television series episode.
        public var itemClass: String {
            switch self {
            case .film: "Q11424"
            case .collection: "Q24856"
            case .series: "Q5398426"
            case .season: "Q3464665"
            case .serial: "Q93992677"
            case .episode: "Q21191270"
            }
        }

        /// The kinds a search offers: the ones a library's top-level container is drafted from.
        public static let searched: [Kind] = [.film, .series, .collection]

        /// The container type an item of the kind is read as.
        public var containerType: ContainerType {
            switch self {
            case .film: .movie
            case .collection: .collection
            case .series: .series
            case .season: .season
            case .serial: .serial
            case .episode: .episode
            }
        }
    }

    /// An item a draft is read from: its id, and the kind it is read as.
    public struct Item: Hashable, Sendable, Codable {
        public var kind: Kind
        public var id: String

        public init(_ kind: Kind, _ id: String) {
            self.kind = kind
            self.id = id
        }

        /// The reference a container read from it carries.
        public var ref: ExternalRef { ExternalRef(provider: .wikidata, value: id) }
    }

    /// An item a search found: its id, kind, label and Wikidata's description of it, which tells apart
    /// items that share a label, and the year it was first shown.
    public struct SearchResult: Hashable, Sendable {
        public var id: String
        public var kind: Kind
        public var title: String
        public var description: String?
        public var year: Int?

        public init(id: String, kind: Kind, title: String, description: String? = nil, year: Int? = nil) {
            self.id = id
            self.kind = kind
            self.title = title
            self.description = description
            self.year = year
        }
    }

    /// A person credited for a work: who, as Wikidata names them, the character played, for a member of
    /// the cast, and the ids providers know the person by. Credits are in the order the item lists
    /// them, which is the order its editors gave them rather than a billing, unless they numbered them.
    public struct Credit: Hashable, Sendable, Codable {
        public var person: String
        public var name: String
        public var character: String?
        public var refs: [ExternalRef]

        public init(person: String, name: String, character: String? = nil, refs: [ExternalRef] = []) {
            self.person = person
            self.name = name
            self.character = character
            self.refs = refs
        }
    }

    /// A film, a series, a season, a serial or an episode, as its own statements say it: its label,
    /// its first date, to the day when Wikidata knows the day and to the year when it knows only the
    /// year, its credits, and its references — Wikidata's own first, then IMDb's, TMDb's and TVDB's.
    public struct Work: Hashable, Sendable, Codable {
        public var id: String
        public var title: String
        public var description: String?
        public var premiered: CalendarDate?
        public var year: Int?
        public var refs: [ExternalRef]
        public var directors: [Credit]
        public var screenwriters: [Credit]
        public var cast: [Credit]
        /// The items it is part of the series of: a film's collection, an episode's series.
        public var partOf: [String]

        public init(
            id: String,
            title: String,
            description: String? = nil,
            premiered: CalendarDate? = nil,
            year: Int? = nil,
            refs: [ExternalRef] = [],
            directors: [Credit] = [],
            screenwriters: [Credit] = [],
            cast: [Credit] = [],
            partOf: [String] = []
        ) {
            self.id = id
            self.title = title
            self.description = description
            self.premiered = premiered
            self.year = year
            self.refs = refs
            self.directors = directors
            self.screenwriters = screenwriters
            self.cast = cast
            self.partOf = partOf
        }

        /// The reference a provider gives the work, if it gives one.
        public func ref(_ provider: Provider) -> ExternalRef? {
            refs.first { $0.provider == provider }
        }

        /// Wikidata's own reference for it.
        public var item: ExternalRef { ExternalRef(provider: .wikidata, value: id) }
    }

    /// One of the items a work holds, as the work lists them: a series' season, or a season's serial;
    /// its kind, the number the work gives it, if any, and its label.
    public struct Summary: Hashable, Sendable, Codable {
        public var id: String
        public var kind: Kind
        public var ordinal: Int?
        public var title: String

        public init(id: String, kind: Kind = .season, ordinal: Int?, title: String) {
            self.id = id
            self.kind = kind
            self.ordinal = ordinal
            self.title = title
        }

        /// What a season's member is, as one of the children the season lists.
        public init(_ member: Member, ordinal: Int? = nil) {
            switch member {
            case .episode(let work): self.init(id: work.id, kind: .episode, ordinal: ordinal, title: work.title)
            case .serial(let serial):
                self.init(id: serial.work.id, kind: .serial, ordinal: ordinal, title: serial.work.title)
            }
        }
    }

    /// A series and its seasons in order: by the number the series gives each, then by first date,
    /// and those it numbers not after the rest, by first date. Its specials are the episodes Wikidata
    /// files beneath the series and in no season, by first date: a special that aired in a season is
    /// one of that season's episodes.
    public struct Series: Hashable, Sendable {
        public var work: Work
        public var seasons: [Summary]
        public var specials: [Work]

        public init(work: Work, seasons: [Summary], specials: [Work] = []) {
            self.work = work
            self.seasons = seasons
            self.specials = specials
        }
    }

    /// A serial and its parts, in the order of the numbers its season gives them.
    public struct Serial: Hashable, Sendable {
        public var work: Work
        public var parts: [Work]

        public init(work: Work, parts: [Work]) {
            self.work = work
            self.parts = parts
        }
    }

    /// What a season holds, in order: its episodes, or its serials with their parts. A season numbers
    /// its serials and its episodes with the same ordinal, so which is which is told by each item's
    /// class and by the serial each part is part of.
    public enum Member: Hashable, Sendable {
        case episode(Work)
        case serial(Serial)

        public var work: Work {
            switch self {
            case .episode(let work): work
            case .serial(let serial): serial.work
            }
        }
    }

    /// A season, the number its series gives it, and what it holds.
    public struct Season: Hashable, Sendable {
        public var work: Work
        public var ordinal: Int?
        public var members: [Member]

        public init(work: Work, ordinal: Int?, members: [Member]) {
            self.work = work
            self.ordinal = ordinal
            self.members = members
        }
    }

    /// A film series and its films, in the order of the numbers it gives them, then by first date.
    public struct Collection: Hashable, Sendable {
        public var work: Work
        public var films: [Work]

        public init(work: Work, films: [Work]) {
            self.work = work
            self.films = films
        }
    }

    /// Why Wikidata could not be read: an answer other than success, a request its API refuses, with
    /// the code and the reason it gives, or an item that is not there or is not of the kind asked for.
    public enum Unavailable: Error, Hashable, Sendable {
        case answered(Int)
        case refused(String, String)
        case notThere(String)
        case notA(Kind, String)

        public var reason: String {
            switch self {
            case .answered(let status): "Wikidata answered \(status)."
            case .refused(_, let info): "Wikidata refused the request: \(info)"
            case .notThere(let id): "Wikidata holds no item \(id)."
            case .notA(let kind, let id): "Wikidata's \(id) is not a \(kind.rawValue)."
            }
        }
    }
}

/// Where the console reads Wikidata from: the client, or in tests what answers in its place.
public protocol WikidataSource: Sendable {
    /// The films, series and collections whose labels match the text, the most widely known first.
    func search(_ text: String) async throws -> [Wikidata.SearchResult]
    func film(_ id: String) async throws -> Wikidata.Work
    func series(_ id: String) async throws -> Wikidata.Series
    func season(_ id: String) async throws -> Wikidata.Season
    func serial(_ id: String) async throws -> Wikidata.Serial
    func collection(_ id: String) async throws -> Wikidata.Collection
    /// Items read as episodes, in the order asked, each whatever it is an instance of.
    func episodes(_ ids: [String]) async throws -> [Wikidata.Work]
}
