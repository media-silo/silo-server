// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Crypto
import Foundation
import Synchronization

/// One step of a store, as its request carries it: a creation, an edit, a put of artwork or a removal
/// of it, each in the terms of the route that makes it alone. Its JSON is an object of one key, the
/// kind, holding the step; an object of no kind or of several is not a step.
public enum StoreStep: Hashable, Sendable {
    public struct Attribution: Codable, Hashable, Sendable {
        /// The container in a creation the attribution belongs to; absent in an edit's.
        public var container: String?
        public var subject: String
        public var provider: String
        public var value: String
        public var read: String

        public init(container: String? = nil, subject: String, provider: String, value: String, read: String) {
            self.container = container
            self.subject = subject
            self.provider = provider
            self.value = value
            self.read = read
        }
    }

    public struct Ref: Codable, Hashable, Sendable {
        public var provider: String
        public var value: String

        public init(provider: String, value: String) {
            self.provider = provider
            self.value = value
        }
    }

    public struct Create: Codable, Hashable, Sendable {
        public var documents: [String]
        public var parent: String?
        public var attributions: [Attribution]?

        public init(documents: [String], parent: String? = nil, attributions: [Attribution]? = nil) {
            self.documents = documents
            self.parent = parent
            self.attributions = attributions
        }
    }

    public struct Edit: Codable, Hashable, Sendable {
        public var container: String
        public var document: String
        public var basedOn: String
        public var attributions: [Attribution]?
        public var declined: [Ref]?

        public init(
            container: String,
            document: String,
            basedOn: String,
            attributions: [Attribution]? = nil,
            declined: [Ref]? = nil
        ) {
            self.container = container
            self.document = document
            self.basedOn = basedOn
            self.attributions = attributions
            self.declined = declined
        }
    }

    public struct Artwork: Codable, Hashable, Sendable {
        public var container: String
        public var kind: String
        /// The digest of the blob put; absent in a removal.
        public var image: String?
        public var provider: String?
        public var value: String?
        public var read: String?

        public init(
            container: String,
            kind: String,
            image: String? = nil,
            provider: String? = nil,
            value: String? = nil,
            read: String? = nil
        ) {
            self.container = container
            self.kind = kind
            self.image = image
            self.provider = provider
            self.value = value
            self.read = read
        }
    }

    case create(Create)
    case edit(Edit)
    case putArtwork(Artwork)
    case removeArtwork(Artwork)

}

extension StoreStep: Codable {
    private enum Kind: String, CodingKey {
        case create, edit, putArtwork, removeArtwork
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Kind.self)
        guard container.allKeys.count == 1, let kind = container.allKeys.first else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "a step is exactly one of a create, an edit, a put of artwork or a removal of it"
                )
            )
        }
        switch kind {
        case .create: self = .create(try container.decode(Create.self, forKey: kind))
        case .edit: self = .edit(try container.decode(Edit.self, forKey: kind))
        case .putArtwork: self = .putArtwork(try container.decode(Artwork.self, forKey: kind))
        case .removeArtwork: self = .removeArtwork(try container.decode(Artwork.self, forKey: kind))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Kind.self)
        switch self {
        case .create(let create): try container.encode(create, forKey: .create)
        case .edit(let edit): try container.encode(edit, forKey: .edit)
        case .putArtwork(let artwork): try container.encode(artwork, forKey: .putArtwork)
        case .removeArtwork(let artwork): try container.encode(artwork, forKey: .removeArtwork)
        }
    }
}

/// A store as the silo keeps it: the steps it was sent under its key, how many are made, and, once it
/// is refused, which step and why. The record carries nothing of the sender's prose; a step is said
/// by its index. Its JSON is flat, its state a name beside `step`, `reason` and `findings`.
public struct StoreRecord: Hashable, Sendable {
    public enum State: Hashable, Sendable {
        /// Making the step after those made.
        case underWay
        case made
        case refused(Refusal)
    }

    /// Why a store was refused: at which step, or at none when it was refused before any was tried,
    /// in the words of the check or of the step's route, with the route's findings when it gave them.
    public struct Refusal: Hashable, Sendable {
        public var step: Int?
        public var reason: String
        public var findings: [Finding]?

        public init(step: Int? = nil, reason: String, findings: [Finding]? = nil) {
            self.step = step
            self.reason = reason
            self.findings = findings
        }
    }

    public struct Finding: Codable, Hashable, Sendable {
        public var severity: String
        public var path: String?
        public var text: String

        public init(severity: String, path: String? = nil, text: String) {
            self.severity = severity
            self.path = path
            self.text = text
        }
    }

    public var library: String
    public var key: String
    public var steps: [StoreStep]
    public var state: State
    /// How many of the steps are made.
    public var made: Int
    public var updatedAt: Date

    public init(library: String, key: String, steps: [StoreStep], state: State = .underWay, made: Int = 0) {
        self.library = library
        self.key = key
        self.steps = steps
        self.state = state
        self.made = made
        self.updatedAt = Date()
    }

    /// The step under way, the first not made, or the one refused; nil for a store made, or refused
    /// before any step was tried.
    public var step: Int? {
        switch state {
        case .underWay: made < steps.count ? made : nil
        case .made: nil
        case .refused(let refusal): refusal.step
        }
    }

    public var refusal: Refusal? {
        if case .refused(let refusal) = state { refusal } else { nil }
    }
}

extension StoreRecord: Codable {
    private enum CodingKeys: String, CodingKey {
        case library, key, steps, state, made, step, reason, findings, updatedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        library = try container.decode(String.self, forKey: .library)
        key = try container.decode(String.self, forKey: .key)
        steps = try container.decode([StoreStep].self, forKey: .steps)
        made = try container.decode(Int.self, forKey: .made)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        switch try container.decode(String.self, forKey: .state) {
        case "underWay": state = .underWay
        case "made": state = .made
        case "refused":
            state = .refused(
                Refusal(
                    step: try container.decodeIfPresent(Int.self, forKey: .step),
                    reason: try container.decode(String.self, forKey: .reason),
                    findings: try container.decodeIfPresent([Finding].self, forKey: .findings)
                )
            )
        case let other:
            throw DecodingError.dataCorruptedError(
                forKey: .state,
                in: container,
                debugDescription: "\(other) is not a store's state"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(library, forKey: .library)
        try container.encode(key, forKey: .key)
        try container.encode(steps, forKey: .steps)
        try container.encode(made, forKey: .made)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(step, forKey: .step)
        switch state {
        case .underWay: try container.encode("underWay", forKey: .state)
        case .made: try container.encode("made", forKey: .state)
        case .refused(let refusal):
            try container.encode("refused", forKey: .state)
            try container.encode(refusal.reason, forKey: .reason)
            try container.encodeIfPresent(refusal.findings, forKey: .findings)
        }
    }
}

/// Stores as the silo keeps them: one JSON file per store under `<state>/stores`, read once at start
/// and held in memory, every change written whole and atomically, as jobs are. A record is kept for
/// thirty days after it was last written, and its key is then free. `Stores.md`, *A record kept*.
public final class StoreRecords: Sendable {
    public let folder: URL
    /// How long a record is kept after it was last written.
    public static let lifetime: TimeInterval = 30 * 24 * 60 * 60
    private let records: Mutex<[String: StoreRecord]>

    public init(folder: URL) throws {
        self.folder = folder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var loaded: [String: StoreRecord] = [:]
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
        for file in files where file.pathExtension == "json" {
            if let record = try? decoder.decode(StoreRecord.self, from: try Data(contentsOf: file)) {
                loaded[Self.name(record.library, record.key)] = record
            }
        }
        records = Mutex(loaded)
    }

    public func record(_ key: String, in library: String) -> StoreRecord? {
        records.withLock { $0[Self.name(library, key)] }
    }

    /// The record of the key, or, when the library has none under it, the new one, kept: found and
    /// added in one step, so that two requests with one key make one store.
    public func adding(_ record: StoreRecord) throws -> (record: StoreRecord, added: Bool) {
        try records.withLock { records in
            let name = Self.name(record.library, record.key)
            if let held = records[name] { return (held, false) }
            records[name] = record
            try write(record)
            return (record, true)
        }
    }

    /// Changes a record and writes it whole; nil when there is none.
    @discardableResult
    public func update(
        _ key: String,
        in library: String,
        _ change: (inout StoreRecord) -> Void
    ) throws -> StoreRecord? {
        try records.withLock { records in
            let name = Self.name(library, key)
            guard var record = records[name] else { return nil }
            change(&record)
            record.updatedAt = Date()
            records[name] = record
            try write(record)
            return record
        }
    }

    /// Every store still under way, as the silo finds them when it starts.
    public func underWay() -> [StoreRecord] {
        records.withLock { $0.values.filter { $0.state == .underWay }.sorted { $0.updatedAt < $1.updatedAt } }
    }

    /// The images the stores under way put, which no sweep of the blobs may remove.
    public func imagesUnderWay() -> Set<String> {
        Set(
            underWay().flatMap { record in
                record.steps.compactMap { step in
                    if case .putArtwork(let artwork) = step { artwork.image } else { nil }
                }
            }
        )
    }

    /// Removes every record that is not under way and was last written longer than a lifetime before
    /// `now`, freeing its key.
    public func sweep(now: Date = Date()) {
        records.withLock { records in
            let lapsed = records.filter { _, record in
                record.state != .underWay && now.timeIntervalSince(record.updatedAt) > Self.lifetime
            }
            for name in lapsed.keys {
                records[name] = nil
                try? FileManager.default.removeItem(at: folder.appendingPathComponent("\(name).json"))
            }
        }
    }

    private func write(_ record: StoreRecord) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(record).write(
            to: folder.appendingPathComponent("\(Self.name(record.library, record.key)).json"),
            options: .atomic
        )
    }

    /// A record's file name: the digest of its library and key, since a key is the sender's to choose.
    private static func name(_ library: String, _ key: String) -> String {
        SHA256.hash(data: Data("\(library)\n\(key)".utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
