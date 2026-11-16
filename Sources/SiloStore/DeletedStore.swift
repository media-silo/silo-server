// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import Synchronization

/// What the silo has deleted in the last thirty days — each library it removed, recipe it discarded
/// and trial it deleted, by id and when — kept in one file, `deleted.json` in the state directory,
/// written whole and atomically. A delete sent again because its answer was lost is answered as made
/// when this holds its id, while an id the silo never had is still refused.
public final class DeletedStore: Sendable {
    /// What was deleted.
    public enum Kind: String, Hashable, Sendable, Codable {
        case library, recipe, trial
    }

    struct Entry: Hashable, Sendable, Codable {
        var kind: Kind
        var id: String
        var when: Date
    }

    /// How long an entry is kept: a delete sent again after this is refused as an id never held.
    public static let kept: TimeInterval = 30 * 24 * 60 * 60

    public let file: URL
    private let entries: Mutex<[Entry]>

    public init(file: URL) throws {
        self.file = file
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let read = (try? Data(contentsOf: file)).flatMap { try? decoder.decode([Entry].self, from: $0) } ?? []
        entries = Mutex(Self.current(read))
    }

    /// In memory only, for tests.
    public init() {
        file = URL(fileURLWithPath: "/dev/null")
        entries = Mutex([])
    }

    /// Records a delete made, as of now, keeping only the entries still within thirty days.
    public func record(_ kind: Kind, _ id: String) throws {
        try entries.withLock { entries in
            var kept = Self.current(entries).filter { !($0.kind == kind && $0.id == id) }
            kept.append(Entry(kind: kind, id: id, when: .now))
            try write(kept)
            entries = kept
        }
    }

    /// Whether the silo deleted the id, of that kind, within the last thirty days.
    public func holds(_ kind: Kind, _ id: String) -> Bool {
        entries.withLock { Self.current($0).contains { $0.kind == kind && $0.id == id } }
    }

    /// Takes an id off the record: a library added under it again, whose removal is now the new one's.
    public func forget(_ kind: Kind, _ id: String) throws {
        try entries.withLock { entries in
            guard entries.contains(where: { $0.kind == kind && $0.id == id }) else { return }
            let kept = Self.current(entries).filter { !($0.kind == kind && $0.id == id) }
            try write(kept)
            entries = kept
        }
    }

    private static func current(_ entries: [Entry]) -> [Entry] {
        let since = Date.now.addingTimeInterval(-kept)
        return entries.filter { $0.when > since }
    }

    private func write(_ entries: [Entry]) throws {
        guard file.path != "/dev/null" else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(entries).write(to: file, options: .atomic)
    }
}
