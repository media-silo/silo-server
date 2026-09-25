// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloAdminKit
import Testing

/// The registry on disk: what the app wrote last run is what this run reads.
@Suite(.serialized)
struct SiloRegistryTests {
    private static func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("silo-admin-registry-\(UUID().uuidString)")
    }

    @Test func aRestartKeepsTheRegistry() throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("registry.json")
        let seen = Date(timeIntervalSince1970: 1_790_000_000)

        let first = SiloRegistry(file: file)
        try first.merge(RegisteredSilo(id: "s1", name: "Attic Silo", url: URL(string: "http://attic.local:8080")!, lastSeen: seen, hasStoredPasskey: true))
        try first.merge(RegisteredSilo(id: "s2", name: "Living Room Silo", url: URL(string: "http://living.local:9000")!, lastSeen: seen, hasStoredPasskey: false))
        try first.notePasskey(true, for: "s2")

        let reopened = SiloRegistry(file: file)
        #expect(reopened.all == [
            RegisteredSilo(id: "s1", name: "Attic Silo", url: URL(string: "http://attic.local:8080")!, lastSeen: seen, hasStoredPasskey: true),
            RegisteredSilo(id: "s2", name: "Living Room Silo", url: URL(string: "http://living.local:9000")!, lastSeen: seen, hasStoredPasskey: true),
        ])
    }
}
