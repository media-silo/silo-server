// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import Synchronization

/// What the console remembers of a silo: the name it last used, the URL it last answered at,
/// when it was last seen, whether this Mac holds a passkey for it, and what the probe said
/// last time the silo answered. The passkey itself lives in the Keychain — the registry
/// carries the fact of it and nothing of the string.
public struct RegisteredSilo: Hashable, Sendable, Codable {
    public var id: String
    public var name: String
    public var url: URL
    public var lastSeen: Date
    public var hasStoredPasskey: Bool
    /// The verdict of the last probe to reach this silo — nil while none was made. Recorded
    /// only on contact, so an unreachable silo can render honest last-known access.
    public var lastKnownAccess: Bool?

    public init(id: String, name: String, url: URL, lastSeen: Date, hasStoredPasskey: Bool, lastKnownAccess: Bool? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.lastSeen = lastSeen
        self.hasStoredPasskey = hasStoredPasskey
        self.lastKnownAccess = lastKnownAccess
    }
}

/// The registry on disk: one JSON object keyed by `ServerID`, rewritten atomically whole — it
/// stays small by design, since a silo that neither registers nor answers is nothing to the
/// console. A `Sendable` class for the reason the stores are: read, amend, persist is one
/// section under one lock, and nothing inside it suspends.
public final class SiloRegistry: Sendable {
    public let file: URL
    private let entries: Mutex<[String: RegisteredSilo]>

    public init(file: URL) {
        self.file = file
        entries = Mutex(Self.read(file))
    }

    /// In memory only, for tests and for platforms where the app passes no file.
    public init() {
        file = URL(fileURLWithPath: "/dev/null")
        entries = Mutex([:])
    }

    /// Every entry, in id order for a stable rendering.
    public var all: [RegisteredSilo] {
        entries.withLock { $0.values.sorted { $0.id < $1.id } }
    }

    public func entry(for id: String) -> RegisteredSilo? {
        entries.withLock { $0[id] }
    }

    /// Merges fresh contact into the registry: creating the entry for a silo never seen, or
    /// refreshing name, address and last-seen for a known one. Only contact merges — a silo
    /// that did not answer keeps what it had.
    public func merge(_ entry: RegisteredSilo) throws {
        try entries.withLock { entries in
            entries[entry.id] = entry
            try Self.persist(entries, to: file)
        }
    }

    /// Records whether this Mac now holds a passkey for the silo, leaving the rest of the
    /// entry alone.
    public func notePasskey(_ stored: Bool, for id: String) throws {
        try entries.withLock { entries in
            guard var entry = entries[id] else { return }
            entry.hasStoredPasskey = stored
            entries[id] = entry
            try Self.persist(entries, to: file)
        }
    }

    /// Removes the entry outright, persisting the loss. The half of forgetting the console's
    /// engine owns; should the silo answer again, contact merges it back as never met.
    public func remove(_ id: String) throws {
        try entries.withLock { entries in
            guard entries.removeValue(forKey: id) != nil else { return }
            try Self.persist(entries, to: file)
        }
    }

    private static func persist(_ entries: [String: RegisteredSilo], to file: URL) throws {
        guard file.path != "/dev/null" else { return }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(entries).write(to: file, options: .atomic)
    }

    private static func read(_ file: URL) -> [String: RegisteredSilo] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: RegisteredSilo].self, from: Data(contentsOf: file))) ?? [:]
    }
}
