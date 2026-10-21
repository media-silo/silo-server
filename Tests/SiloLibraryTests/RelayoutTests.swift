// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SmdKit
import SmdSidecar
import Testing

@testable import SiloLibrary

struct RelayoutTests {
    typealias Sandbox = PlacementTests.Sandbox

    /// A series, its season and its serial placed, as the layout names them.
    func placed() throws -> Sandbox {
        let sandbox = try Sandbox()
        try Placer.apply(
            try Placer.compute(
                PlacementRequest(
                    library: sandbox.library,
                    lineage: PlacementTests.lineage,
                    item: "part1",
                    presentation: Presentation(file: ""),
                    source: try sandbox.source("a.mkv")
                )
            )
        )
        return sandbox
    }

    /// Renames a child's folder by hand and records the new path in its parent's sidecar, as a person
    /// tidying a share might.
    func rename(_ child: ContainerID, in parent: URL, from: String, to: String) throws {
        try FileManager.default.moveItem(at: parent.appendingPathComponent(from), to: parent.appendingPathComponent(to))
        let url = parent.appendingPathComponent("container.smd")
        let existing = try Data(contentsOf: url)
        var sidecar = try SidecarFile.sidecar(from: existing)
        sidecar.children[child] = "\(to)/container.smd"
        try SidecarFile.data(for: sidecar, updating: existing).write(to: url)
    }

    @Test func aLibraryRenamedByHandIsLaidOutFromTheTopDown() throws {
        let sandbox = try placed()
        defer { sandbox.remove() }
        let series = sandbox.library.appendingPathComponent("Doctor Who (1963)")
        try rename(PlacementTests.season.id, in: series, from: "01 - Season 13", to: "Season 13")
        try rename(
            PlacementTests.serial.id,
            in: series.appendingPathComponent("Season 13"),
            from: "01 - Pyramids of Mars",
            to: "Pyramids of Mars"
        )
        let expected = [
            FolderMove(from: "Doctor Who (1963)/Season 13", to: "Doctor Who (1963)/01 - Season 13"),
            FolderMove(
                from: "Doctor Who (1963)/01 - Season 13/Pyramids of Mars",
                to: "Doctor Who (1963)/01 - Season 13/01 - Pyramids of Mars"
            ),
        ]

        let dry = Relayout.layOut(LibraryWalker.walk(sandbox.library), dryRun: true)
        #expect(dry.moves == expected)
        #expect(FileManager.default.fileExists(atPath: series.appendingPathComponent("Season 13").path))

        let laid = Relayout.layOut(LibraryWalker.walk(sandbox.library), dryRun: false)
        #expect(laid.moves == expected)
        #expect(laid.findings.isEmpty)
        let tree = LibraryWalker.walk(sandbox.library)
        #expect(tree.findings.isEmpty, "the walk warns of nothing")
        #expect(tree.roots[0].sidecar.children[PlacementTests.season.id] == "01 - Season 13/container.smd")
        #expect(
            tree.roots[0].children[0].children[0].relativeFolder
                == "Doctor Who (1963)/01 - Season 13/01 - Pyramids of Mars"
        )
        #expect(Relayout.layOut(tree, dryRun: false).moves.isEmpty)
    }

    /// A rename that changes only a name's case goes by way of another name, which a case-insensitive
    /// disk needs.
    @Test func aChangeOfCaseIsARename() throws {
        let sandbox = try placed()
        defer { sandbox.remove() }
        try FileManager.default.moveItem(
            at: sandbox.library.appendingPathComponent("Doctor Who (1963)"),
            to: sandbox.library.appendingPathComponent("doctor who (1963)")
        )
        let laid = Relayout.layOut(LibraryWalker.walk(sandbox.library), dryRun: false)
        #expect(laid.moves == [FolderMove(from: "doctor who (1963)", to: "Doctor Who (1963)")])
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: sandbox.library.path).filter { !$0.hasPrefix(".") }
                == ["Doctor Who (1963)"]
        )
    }

    /// A folder renamed whose parent's sidecar cannot take the new path is said, and the rest stands.
    @Test func aPathThatCannotBeRecordedIsAWarning() throws {
        let sandbox = try placed()
        defer { sandbox.remove() }
        let series = sandbox.library.appendingPathComponent("Doctor Who (1963)")
        try rename(PlacementTests.season.id, in: series, from: "01 - Season 13", to: "Season 13")
        let tree = LibraryWalker.walk(sandbox.library)
        try Data("<container".utf8).write(to: series.appendingPathComponent("container.smd"))

        let laid = Relayout.layOut(tree, dryRun: false)
        #expect(laid.moves.map(\.to) == ["Doctor Who (1963)/01 - Season 13"])
        #expect(laid.findings.map(\.path) == ["Doctor Who (1963)/container.smd"])
        #expect(laid.findings.first?.text.hasPrefix("the new paths of its children could not be recorded") == true)

        // One container laid out beneath a parent whose sidecar is as broken.
        let season = try #require(tree.roots.first?.children.first)
        var renamed = season
        renamed.relativeFolder = "Doctor Who (1963)/01 - Season 13"
        renamed.children = []
        var retitled = renamed.sidecar
        retitled.container.title = Title("Season Thirteen")!
        renamed.sidecar = retitled
        let one = Relayout.layOut(
            renamed,
            under: Relayout.Parent(container: PlacementTests.series, folder: "Doctor Who (1963)"),
            in: sandbox.library,
            dryRun: false
        )
        #expect(one.moves.map(\.to) == ["Doctor Who (1963)/01 - Season Thirteen"])
        #expect(one.paths[PlacementTests.season.id] == "01 - Season Thirteen/container.smd")
        #expect(one.findings.map(\.path) == ["Doctor Who (1963)/container.smd"])
    }
}
