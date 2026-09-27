// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloStore
import Testing

/// The identity's life: the ServerID minted into `silo.json` where none was and kept on every boot
/// after, and the name a setting in `settings.json` that a rename changes without touching the id.
struct ServerIdentityTests {
    @Test func identityIsMintedOnceAndKeptAcrossRestartsAndARename() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("silo-identity-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }

        let (first, report) = try SiloFile.open(in: folder)
        #expect(report.defaulted("serverID"))
        #expect(UUID(uuidString: first.serverID) != nil)
        #expect(first.serverID == first.serverID.lowercased())
        let (settings, _) = try SettingsStore.open(in: folder, defaultName: "Silo on first")
        #expect(settings.current.name == "Silo on first")

        let (again, againReport) = try SiloFile.open(in: folder)
        #expect(again.serverID == first.serverID)
        #expect(!againReport.defaulted("serverID"))
        let (reopened, _) = try SettingsStore.open(in: folder, defaultName: "Silo on elsewhere")
        #expect(reopened.current.name == "Silo on first", "the name is fixed at first boot, not the host's")

        try reopened.update { $0.name = "Living Room Silo" }
        let (rebooted, _) = try SiloFile.open(in: folder)
        let (renamed, _) = try SettingsStore.open(in: folder, defaultName: "Silo on first")
        #expect(rebooted.serverID == first.serverID, "a rename keeps the identity")
        #expect(renamed.current.name == "Living Room Silo", "a rename survives a restart")
    }
}
