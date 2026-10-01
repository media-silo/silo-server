// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloKit
import Synchronization

/// Sources as the silo keeps them: one JSON file per source under `<state>/sources`, read once at
/// start and held in memory, every change written whole and atomically — the job store's shape, for
/// the job store's reasons. Registering by natural key is a find-or-add, so it is one step under the
/// lock: two producers registering one disc title at once get one source.
public final class SourceStore: Sendable {
    public let folder: URL
    private let sources: Mutex<[String: Source]>

    public init(folder: URL) throws {
        self.folder = folder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var loaded: [String: Source] = [:]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        for file in files where file.pathExtension == "json" {
            if let source = try? decoder.decode(Source.self, from: try Data(contentsOf: file)) {
                loaded[source.id] = source
            }
        }
        sources = Mutex(loaded)
    }

    /// In memory only, for tests.
    public init() {
        folder = URL(fileURLWithPath: "/dev/null")
        sources = Mutex([:])
    }

    /// Oldest first.
    public func all() -> [Source] {
        sources.withLock { Array($0.values) }.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    public func source(_ id: String) -> Source? {
        sources.withLock { $0[id] }
    }

    /// Registers a source, or finds the one its natural key already names. A match whose input spec
    /// differs is refused, since one of the two descriptions is wrong; a match whose spec agrees
    /// takes the copy given. `created` says which happened.
    public func register(_ input: InputSpec, key: NaturalKey?, copy: FileRef?) throws -> (source: Source, created: Bool) {
        try sources.withLock { sources -> (Source, Bool) in
            if let key, var existing = sources.values.first(where: { $0.key == key }) {
                guard existing.input == input else { throw SourceStoreError.keyDescribedOtherwise(key: key, source: existing.id) }
                if let copy {
                    existing.hold(copy)
                    sources[existing.id] = existing
                    try write(existing)
                }
                return (existing, false)
            }
            var source = Source(input: input, key: key)
            if let copy { source.hold(copy) }
            sources[source.id] = source
            try write(source)
            return (source, true)
        }
    }

    /// Changes one source under the lock; nil for a source the silo does not have.
    @discardableResult
    public func update(_ id: String, _ change: (inout Source) -> Void) throws -> Source? {
        try sources.withLock { sources -> Source? in
            guard var source = sources[id] else { return nil }
            change(&source)
            sources[id] = source
            try write(source)
            return source
        }
    }

    private func write(_ source: Source) throws {
        guard folder.path != "/dev/null" else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(source).write(to: folder.appendingPathComponent("\(source.id).json"), options: .atomic)
    }
}

public enum SourceStoreError: Error, Equatable, CustomStringConvertible {
    case keyDescribedOtherwise(key: NaturalKey, source: String)

    public var description: String {
        switch self {
        case .keyDescribedOtherwise(let key, let source):
            "source \(source) already has the natural key \(key), with a different input spec"
        }
    }
}
