// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloStore
import Testing

/// The identity file's life: minted where none was, kept on every boot after, the name seeded at
/// the mint and at the mint only.
struct ServerIdentityTests {
    @Test func identityIsMintedOnceAndKeptAcrossRestartsAndARename() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("silo-identity-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }

        let first = try loadServerIdentity(from: folder, named: "Silo on first")
        #expect(UUID(uuidString: first.id) != nil)
        #expect(first.id == first.id.lowercased())
        #expect(first.name == "Silo on first")
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("server.json").path))

        let again = try loadServerIdentity(from: folder, named: "Silo on elsewhere")
        #expect(again == first, "the file is the source of truth; the seed is the mint's alone")

        var renamed = first
        renamed.name = "Living Room Silo"
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(renamed).write(to: folder.appendingPathComponent("server.json"), options: .atomic)

        let rebooted = try loadServerIdentity(from: folder, named: "Silo on first")
        #expect(rebooted.id == first.id)
        #expect(rebooted.name == "Living Room Silo", "a rename in the file survives a restart")
    }
}
