// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import Synchronization

/// Records as the silo keeps most of its state: one JSON file each in a folder, read once at start
/// and held in memory, every change written whole and atomically, every read-modify-write under one
/// lock. A change reaches memory only once its file is written, and a removal only once its file is
/// gone, so a write that fails leaves the record as it was in both, and what the folder answers is
/// always what a restart would read. The shape the job and source stores already have, shared here by the stores that are
/// nothing more than it. It is the class — the one instance that owns the `Mutex`, which cannot be
/// copied — so the stores built on it need not be: they are structs, and a copy of one holds the
/// same folder.
final class RecordFolder<Record: Codable & Sendable>: Sendable {
    let folder: URL
    private let id: @Sendable (Record) -> String
    private let records: Mutex<[String: Record]>

    init(folder: URL, id: @escaping @Sendable (Record) -> String) throws {
        self.folder = folder
        self.id = id
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var loaded: [String: Record] = [:]
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
        for file in files where file.pathExtension == "json" {
            if let record = try? decoder.decode(Record.self, from: try Data(contentsOf: file)) {
                loaded[id(record)] = record
            }
        }
        records = Mutex(loaded)
    }

    /// In memory only, for tests.
    init(id: @escaping @Sendable (Record) -> String) {
        folder = URL(fileURLWithPath: "/dev/null")
        self.id = id
        records = Mutex([:])
    }

    var all: [Record] { records.withLock { Array($0.values) } }

    func record(_ key: String) -> Record? { records.withLock { $0[key] } }

    func insert(_ inserted: [Record]) throws {
        try records.withLock { records in
            for record in inserted {
                try write(record)
                records[id(record)] = record
            }
        }
    }

    /// Inserts each record the folder holds no match of, under one lock, so that two copies of one
    /// request at once insert one record. Answers, for each record given, the record held — the
    /// match found, or the record inserted — and whether it was inserted.
    func insert(
        _ inserted: [Record],
        unlessHeld matches: (_ held: Record, _ given: Record) -> Bool
    ) throws -> [(record: Record, inserted: Bool)] {
        try records.withLock { records in
            try inserted.map { record in
                if let held = records.values.first(where: { matches($0, record) }) { return (held, false) }
                try write(record)
                records[id(record)] = record
                return (record, true)
            }
        }
    }

    /// Changes one record under the lock. The change may throw, and then nothing is written; nil for
    /// a record the folder does not hold.
    func update<Failure: Error>(_ key: String, _ change: (inout Record) throws(Failure) -> Void) throws -> Record? {
        try records.withLock { records -> Record? in
            guard var record = records[key] else { return nil }
            try change(&record)
            try write(record)
            records[key] = record
            return record
        }
    }

    /// Removes one record, when the predicate allows it, under the lock. Answers the record, or nil
    /// when the folder does not hold it; throws what the predicate throws.
    func remove<Failure: Error>(_ key: String, if allowed: (Record) throws(Failure) -> Void) throws -> Record? {
        try records.withLock { records -> Record? in
            guard let record = records[key] else { return nil }
            try allowed(record)
            if folder.path != "/dev/null" { try removeFile(at: folder.appendingPathComponent("\(key).json")) }
            records[key] = nil
            return record
        }
    }

    private func write(_ record: Record) throws {
        guard folder.path != "/dev/null" else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: folder.appendingPathComponent("\(id(record)).json"), options: .atomic)
    }
}

/// Deletes a record's file. One that is not there is already gone, which is what a removal wants;
/// any other failure is thrown, so the caller keeps the record it could not remove.
func removeFile(at url: URL) throws {
    do {
        try FileManager.default.removeItem(at: url)
    } catch CocoaError.fileNoSuchFile {
        return
    }
}
