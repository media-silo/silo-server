// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation

/// Who this silo is: the id it minted once and the name it answers to, kept in `server.json` in
/// the state directory. The file is minted on the first boot that misses it — the name seeded
/// then, and only then — and loaded on every boot after; no route re-mints it, and the operator
/// changing the state directory's contents is the supported way to make a new server.
public struct ServerIdentity: Hashable, Sendable, Codable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Loads `server.json` from `folder`, or mints a fresh identity — a lower-cased UUID and the
/// given name — and writes it atomically when one is not there. The seed is consulted at the
/// mint and at the mint only: once the file exists it is the source of truth for the name.
public func loadServerIdentity(from folder: URL, named name: String) throws -> ServerIdentity {
    let file = folder.appendingPathComponent("server.json")
    guard let identity = try? JSONDecoder().decode(ServerIdentity.self, from: Data(contentsOf: file)) else {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let minted = ServerIdentity(id: UUID().uuidString.lowercased(), name: name)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(minted).write(to: file, options: .atomic)
        return minted
    }
    return identity
}
