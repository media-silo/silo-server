// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloLibrary
import SiloStore
import SmdKit
import SmdSidecar
import Testing
@testable import SiloApp

/// Each library's availability, on `Libraries` alone over a temporary folder and an in-memory index:
/// what the boot does with a folder that is missing, and what a request reaching for one that has
/// come back does.
struct LibrariesTests {
    struct Bench {
        let root: URL
        let present: LibraryConfig
        let late: LibraryConfig
        let index: Index
        let libraries: Libraries

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("silo-libraries-\(UUID().uuidString)")
            present = LibraryConfig(id: "main", root: root.appendingPathComponent("Library"))
            late = LibraryConfig(id: "films", root: root.appendingPathComponent("Films"))
            try FileManager.default.createDirectory(at: present.root, withIntermediateDirectories: true)
            try Self.place(Fixture.thirdMan, into: present.root, from: root)
            let config = SiloConfig(
                silo: SiloFile(serverID: "s1", host: "127.0.0.1", port: 0),
                settings: Settings(name: "Silo on test", libraries: [present, late]),
                stateDirectory: root.appendingPathComponent("State")
            )
            index = try Index(at: nil)
            libraries = Libraries(config: config, index: index)
        }

        static func place(_ film: Container, into library: URL, from root: URL) throws {
            let source = root.appendingPathComponent("\(UUID().uuidString).mkv")
            try Data("video".utf8).write(to: source)
            try Placer.apply(try Placer.compute(PlacementRequest(library: library, lineage: [film], item: "feature", presentation: Presentation(file: ""), source: source)))
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    @Test func aDriveLateToMountIsUnavailableAndTheRestAreServed() throws {
        let bench = try Bench()
        defer { bench.remove() }
        try bench.libraries.walkAll()
        #expect(bench.libraries.isAvailable("main"))
        #expect(!bench.libraries.isAvailable("films"), "missing at boot, and the boot went on")
        #expect(try bench.index.roots(in: "main").map(\.id) == [Fixture.thirdMan.id.value])

        // The drive mounts; the next request that reaches for the library walks it.
        try FileManager.default.createDirectory(at: bench.late.root, withIntermediateDirectories: true)
        try Bench.place(Fixture.brief, into: bench.late.root, from: bench.root)
        #expect(try bench.libraries.reach(bench.late))
        #expect(bench.libraries.isAvailable("films"))
        #expect(try bench.index.roots(in: "films").map(\.id) == [Fixture.brief.id.value])
    }

    @Test func aFolderThatGoesIsUnavailableAndItsIndexKept() throws {
        let bench = try Bench()
        defer { bench.remove() }
        try bench.libraries.walkAll()
        let aside = bench.root.appendingPathComponent("Library (unplugged)")
        try FileManager.default.moveItem(at: bench.present.root, to: aside)
        #expect(!bench.libraries.availability(of: bench.present))
        #expect(try bench.libraries.walk(bench.present) == nil, "a walk of a missing folder is not applied")
        #expect(try bench.index.roots(in: "main").count == 1, "and forgets nothing")

        // An empty mount point is a folder, not a missing one: it is unavailable all the same.
        try FileManager.default.createDirectory(at: bench.present.root, withIntermediateDirectories: true)
        #expect(!(try bench.libraries.reach(bench.present)))
        #expect(try bench.index.roots(in: "main").count == 1)

        try FileManager.default.removeItem(at: bench.present.root)
        try FileManager.default.moveItem(at: aside, to: bench.present.root)
        #expect(try bench.libraries.reach(bench.present))
    }
}
