// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloKit
import SmdSidecar
import Testing
@testable import SiloStore

struct RulesLayerFileTests {
    @Test func aLayerIsReadWithTheDigestThatFindsItAgain() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("silo-layer-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("rules"), withIntermediateDirectories: true)
        let document = Data(#"<rules><audio><copy/></audio></rules>"#.utf8)
        try document.write(to: folder.appendingPathComponent("rules/4.xml"))

        let layer = try RulesLayerFile.read(.container("0000000000000003"), SidecarRules(activeVersion: 4), in: folder)
        #expect(layer.version == 4)
        #expect(layer.rules == [Rule(scope: .audio, action: .copy)])
        #expect(layer.digest == RulesLayerFile.digest(of: document))
        #expect(layer.digest.hasPrefix("sha256:") && layer.digest.count == "sha256:".count + 64)

        let missing = #expect(throws: RulesLayerError.self) { try RulesLayerFile.read(.container("0000000000000003"), SidecarRules(activeVersion: 5), in: folder) }
        #expect(missing?.description == "the rules of container 0000000000000003: rules version 5 is not there")
    }

    @Test func aLibrarysRulesetIsKeptInTheSettingsFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("silo-settings-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"name": "Silo", "libraries": [{"id": "films", "path": "/films", "ruleset": "household"}, {"id": "tv", "path": "/tv"}], "embeddedNode": false, "advertise": true}"#.utf8)
            .write(to: folder.appendingPathComponent(SettingsStore.fileName))
        let (store, _) = try SettingsStore.open(in: folder, defaultName: "Silo")
        #expect(store.current.libraries.map(\.ruleset) == ["household", nil])

        try store.update { $0.libraries[1].ruleset = "restoration"; $0.libraries[0].ruleset = nil }
        let (reopened, _) = try SettingsStore.open(in: folder, defaultName: "Silo")
        #expect(reopened.current.libraries.map(\.ruleset) == [nil, "restoration"], "written through, and a cleared one left out")
        let text = try String(contentsOf: folder.appendingPathComponent(SettingsStore.fileName), encoding: .utf8)
        #expect(text.components(separatedBy: "ruleset").count == 2)

        try Data(#"{"name": "Silo", "libraries": [{"id": "films", "path": "/films", "ruleset": 7}], "embeddedNode": false, "advertise": true}"#.utf8)
            .write(to: folder.appendingPathComponent(SettingsStore.fileName))
        #expect(throws: ConfigurationFileError.self) { try SettingsStore.open(in: folder, defaultName: "Silo") }
    }
}
