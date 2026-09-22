// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Crypto
import Foundation
import SiloKit
import Synchronization

/// Nodes as the silo keeps them: one JSON file per node under `<state>/nodes`, holding the record
/// and the hashes of the node's secret and token, never either itself.
///
/// A `Sendable` class rather than a struct or an actor, for the reason the job store gives:
/// minting a token and recording its hash is one step under one lock, the lock is non-copyable,
/// and nothing inside the section suspends. `Index` is the exception among the stores — a struct,
/// since its only state is a database handle that serialises itself.
public final class NodeStore: Sendable {
    public struct Stored: Hashable, Sendable, Codable {
        public var node: Node
        public var secretHash: String
        public var tokenHash: String?
        /// Whether the token minted at approval has been handed to the node; it is handed once.
        public var tokenDelivered: Bool

        public init(node: Node, secretHash: String, tokenHash: String? = nil, tokenDelivered: Bool = false) {
            self.node = node
            self.secretHash = secretHash
            self.tokenHash = tokenHash
            self.tokenDelivered = tokenDelivered
        }
    }

    public let folder: URL
    private let nodes: Mutex<[String: Stored]>

    public init(folder: URL) throws {
        self.folder = folder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var loaded: [String: Stored] = [:]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        for file in files where file.pathExtension == "json" {
            if let stored = try? decoder.decode(Stored.self, from: try Data(contentsOf: file)) {
                loaded[stored.node.id] = stored
            }
        }
        nodes = Mutex(loaded)
    }

    /// In memory only, for tests.
    public init() {
        folder = URL(fileURLWithPath: "/dev/null")
        nodes = Mutex([:])
    }

    public func all() -> [Stored] {
        nodes.withLock { Array($0.values) }.sorted { $0.node.registeredAt < $1.node.registeredAt }
    }

    public func stored(_ id: String) -> Stored? {
        nodes.withLock { $0[id] }
    }

    public func first(where predicate: (Stored) -> Bool) -> Stored? {
        nodes.withLock { $0.values.first(where: predicate) }
    }

    public func insert(_ stored: Stored) throws {
        try nodes.withLock { nodes in
            nodes[stored.node.id] = stored
            try write(stored)
        }
    }

    @discardableResult
    public func update(_ id: String, _ change: (inout Stored) throws -> Void) throws -> Stored? {
        try nodes.withLock { nodes -> Stored? in
            guard var stored = nodes[id] else { return nil }
            try change(&stored)
            nodes[id] = stored
            try write(stored)
            return stored
        }
    }

    public static func hash(_ secret: String) -> String {
        SHA256.hash(data: Data(secret.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func write(_ stored: Stored) throws {
        guard folder.path != "/dev/null" else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(stored).write(to: folder.appendingPathComponent("\(stored.node.id).json"), options: .atomic)
    }
}
