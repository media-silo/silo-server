// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import Synchronization

/// The drafts this Mac keeps, by the `ServerID` of the silo each is for: one JSON object rewritten
/// atomically whole on every change, as the registry is. A draft outlives the app here, and ends only
/// when it is stored or discarded, or its silo forgotten. A `Sendable` class for the registry's
/// reason: read, amend, persist is one section under one lock.
public final class DraftStore: Sendable {
    public let file: URL
    private let entries: Mutex<[String: [Draft]]>

    public init(file: URL) {
        self.file = file
        entries = Mutex(Self.read(file))
    }

    /// In memory only, for tests and for platforms where the app passes no file.
    public init() {
        file = URL(fileURLWithPath: "/dev/null")
        entries = Mutex([:])
    }

    /// A silo's drafts, by ruleset, then most recently edited first.
    public func drafts(of silo: String) -> [Draft] {
        entries.withLock { $0[silo] ?? [] }.sorted { ($0.ruleset, $1.edited) < ($1.ruleset, $0.edited) }
    }

    public func draft(_ id: Draft.ID, of silo: String) -> Draft? {
        entries.withLock { $0[silo]?.first { $0.id == id } }
    }

    /// Keeps the draft, replacing the one with its id.
    public func save(_ draft: Draft, for silo: String) throws {
        try entries.withLock { entries in
            var drafts = entries[silo] ?? []
            if let index = drafts.firstIndex(where: { $0.id == draft.id }) {
                drafts[index] = draft
            } else {
                drafts.append(draft)
            }
            entries[silo] = drafts
            try Self.persist(entries, to: file)
        }
    }

    public func remove(_ id: Draft.ID, of silo: String) throws {
        try entries.withLock { entries in
            guard let index = entries[silo]?.firstIndex(where: { $0.id == id }) else { return }
            entries[silo]?.remove(at: index)
            if entries[silo]?.isEmpty == true { entries[silo] = nil }
            try Self.persist(entries, to: file)
        }
    }

    /// Every draft for the silo, gone: forgetting's share.
    public func removeAll(of silo: String) throws {
        try entries.withLock { entries in
            guard entries.removeValue(forKey: silo) != nil else { return }
            try Self.persist(entries, to: file)
        }
    }

    private static func persist(_ entries: [String: [Draft]], to file: URL) throws {
        guard file.path != "/dev/null" else { return }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(entries).write(to: file, options: .atomic)
    }

    private static func read(_ file: URL) -> [String: [Draft]] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: [Draft]].self, from: Data(contentsOf: file))) ?? [:]
    }
}
