// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import Testing
@testable import SiloStore

/// The two files' startup treatment: created, filled, never rewritten when complete, never repaired
/// when malformed, unknown keys reported and kept.
struct ConfigurationFileTests {
    private func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("silo-files-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func write(_ text: String, _ name: String, in folder: URL) throws {
        try Data(text.utf8).write(to: folder.appendingPathComponent(name))
    }

    private func read(_ name: String, in folder: URL) throws -> Data {
        try Data(contentsOf: folder.appendingPathComponent(name))
    }

    @Test func aFreshDirectoryGetsBothFilesAtTheirDefaults() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let (silo, siloReport) = try SiloFile.open(in: folder)
        #expect(siloReport.created)
        #expect(UUID(uuidString: silo.serverID) != nil)
        #expect(silo.host == "0.0.0.0")
        #expect(silo.port == 8742)

        let (settings, settingsReport) = try SettingsStore.open(in: folder, defaultName: "Silo on cupboard")
        #expect(settingsReport.created)
        #expect(settings.current == Settings(name: "Silo on cupboard", libraries: [], embeddedNode: false, advertise: true))

        let onDisk = try JSONDecoder().decode([String: JSONValue].self, from: read("silo.json", in: folder))
        #expect(onDisk == ["serverID": .string(silo.serverID), "host": .string("0.0.0.0"), "port": .integer(8742)])
    }

    @Test func aGapIsFilledAndACompleteFileIsNotRewritten() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try write(#"{"serverID": "abc", "port": 9000}"#, "silo.json", in: folder)

        let (silo, report) = try SiloFile.open(in: folder)
        #expect(silo == SiloFile(serverID: "abc", host: "0.0.0.0", port: 9000))
        #expect(report.filled == ["host"])
        #expect(!report.defaulted("serverID"), "the ServerID was read, not minted")

        let filled = try read("silo.json", in: folder)
        let (_, again) = try SiloFile.open(in: folder)
        #expect(again == ConfigurationFileReport())
        #expect(try read("silo.json", in: folder) == filled, "a complete file is never rewritten")
    }

    @Test func aMalformedFileStopsTheBootAndSurvivesIt() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let broken = #"{"serverID": "abc", "port": 9000"#
        try write(broken, "silo.json", in: folder)
        try write(broken, "settings.json", in: folder)

        #expect(throws: ConfigurationFileError.self) { try SiloFile.open(in: folder) }
        #expect(throws: ConfigurationFileError.self) { try SettingsStore.open(in: folder, defaultName: "x") }
        #expect(String(decoding: try read("silo.json", in: folder), as: UTF8.self) == broken, "left byte for byte as it was")
        #expect(String(decoding: try read("settings.json", in: folder), as: UTF8.self) == broken)
    }

    @Test func aValueOfTheWrongKindIsRefusedByName() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try write(#"{"serverID": "abc", "host": "0.0.0.0", "port": "eighty"}"#, "silo.json", in: folder)
        #expect(throws: ConfigurationFileError(file: folder.appendingPathComponent("silo.json"), reason: #""port" must be a whole number"#)) {
            try SiloFile.open(in: folder)
        }
        try write(#"{"name": "x", "libraries": [{"id": "films"}], "embeddedNode": false, "advertise": true}"#, "settings.json", in: folder)
        #expect(throws: ConfigurationFileError.self) { try SettingsStore.open(in: folder, defaultName: "x") }
    }

    @Test func anUnknownKeyIsReportedAndKeptThroughWrites() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try write(#"{"serverID": "abc", "host": "0.0.0.0", "port": 8742, "prot": 9000}"#, "silo.json", in: folder)
        let (silo, report) = try SiloFile.open(in: folder)
        #expect(report.unknown == ["prot"])
        #expect(silo.port == 8742, "the typo does not move the port")
        #expect(try JSONDecoder().decode([String: JSONValue].self, from: read("silo.json", in: folder))["prot"] == .integer(9000))

        try write(#"{"name": "Study", "future": {"nested": [true, 1.5, null]}}"#, "settings.json", in: folder)
        let (settings, settingsReport) = try SettingsStore.open(in: folder, defaultName: "x")
        #expect(settingsReport.unknown == ["future"])
        #expect(settingsReport.filled == ["advertise", "embeddedNode", "libraries"])
        try settings.update { $0.embeddedNode = true }
        let onDisk = try JSONDecoder().decode([String: JSONValue].self, from: read("settings.json", in: folder))
        #expect(onDisk["future"] == .object(["nested": .array([.bool(true), .number(1.5), .null])]), "kept exactly through a write")
        #expect(onDisk["embeddedNode"] == .bool(true))
    }

    @Test func settingsAreWrittenWholeAndReadBack() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (settings, _) = try SettingsStore.open(in: folder, defaultName: "Study")
        let films = LibraryConfig(id: "films", root: URL(fileURLWithPath: "/Volumes/Media/Films", isDirectory: true))
        let changed = try settings.update {
            $0.name = "Living Room Silo"
            $0.libraries = [films]
            $0.advertise = false
        }
        #expect(changed == settings.current)
        #expect(String(decoding: try read("settings.json", in: folder), as: UTF8.self).contains(#""path" : "/Volumes/Media/Films""#), "paths are left readable")
        let (reopened, report) = try SettingsStore.open(in: folder, defaultName: "ignored")
        #expect(report == ConfigurationFileReport())
        #expect(reopened.current == Settings(name: "Living Room Silo", libraries: [films], embeddedNode: false, advertise: false))
    }

    @Test func existingStateIsRecognised() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(!stateDirectoryHoldsState(folder))
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("jobs"), withIntermediateDirectories: true)
        #expect(!stateDirectoryHoldsState(folder), "an empty folder is not state")
        try write("{}", "jobs/j1.json", in: folder)
        #expect(stateDirectoryHoldsState(folder))
        try FileManager.default.removeItem(at: folder.appendingPathComponent("jobs"))
        try write("{}", "operator-credential.json", in: folder)
        #expect(stateDirectoryHoldsState(folder))
    }
}
