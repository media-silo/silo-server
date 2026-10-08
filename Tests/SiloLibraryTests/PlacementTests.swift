// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SmdKit
import SmdSidecar
import Testing
@testable import SiloLibrary

struct PlacementTests {
    static let series: Container = {
        var series = Container(id: ContainerID("0000000000000001")!, type: .series, title: Title("Doctor Who")!, year: 1963, yearInTitle: true)
        series.sequences = [Sequence(id: "seasons", items: [.child(Entry.Child(id: ItemID("s13")!, container: season.id))])]
        return series
    }()
    static let season: Container = {
        var season = Container(id: ContainerID("0000000000000002")!, type: .season, title: Title("Season 13")!)
        season.sequences = [Sequence(id: "stories", items: [.child(Entry.Child(id: ItemID("pyramids")!, container: serial.id))])]
        return season
    }()
    static let serial: Container = {
        var serial = Container(id: ContainerID("0000000000000003")!, type: .serial, typeLabel: "Story", title: Title("Pyramids of Mars")!)
        serial.alternatives = [Alternative(id: "broadcast", sequence: "parts", title: "Broadcast version"), Alternative(id: "se", sequence: "parts", title: "Updated special effects")]
        serial.defaultAlternative = "broadcast"
        serial.features = [Feature(id: "commentary1", type: .commentary, title: "Commentary")]
        serial.sequences = [Sequence(id: "parts", items: [.leaf(Entry.Leaf(id: ItemID("part1")!, type: .episode, title: "Part One")), .leaf(Entry.Leaf(id: ItemID("part2")!, type: .episode, title: "Part Two"))])]
        serial.extras = [.leaf(Entry.Leaf(id: ItemID("now-and-then")!, type: .featurette, title: "Now and Then: Pyramids"))]
        return serial
    }()
    static let lineage = [series, season, serial]

    struct Sandbox {
        let root: URL
        let library: URL
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("silo-library-\(UUID().uuidString)")
            library = root.appendingPathComponent("Library")
            try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        }
        func source(_ name: String) throws -> URL {
            let url = root.appendingPathComponent(name)
            try Data("not really video".utf8).write(to: url)
            return url
        }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    @Test func theFirstPlacementMakesTheTree() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let source = try sandbox.source("t00.mkv")
        let request = PlacementRequest(
            library: sandbox.library, lineage: Self.lineage, item: "part1",
            presentation: Presentation(file: "", source: PresentationSource(binding: "5b0e7c1a-3d2f-4e8a-9c41-7f0d2e6a91d2", segments: [.init(key: SmdSidecar.NaturalKey(scheme: "discTitle", value: "3F1A/00004.mpls"))]), tracks: [TrackMapping(feature: "commentary1", audio: 3)], chapters: [Chapter(index: 1, title: "Opening")]),
            source: source
        )
        let placement = try Placer.compute(request)
        #expect(placement.isApplicable)
        #expect(placement.describe(relativeTo: sandbox.library) == [
            "create   Doctor Who (1963)/",
            "create   Doctor Who (1963)/Season 13/",
            "create   Doctor Who (1963)/Season 13/Pyramids of Mars/",
            "place    \(source.path) -> Doctor Who (1963)/Season 13/Pyramids of Mars/Part One.mkv",
            "write    Doctor Who (1963)/container.smd",
            "write    Doctor Who (1963)/Season 13/container.smd",
            "write    Doctor Who (1963)/Season 13/Pyramids of Mars/container.smd",
        ])
        #expect(placement.presentation.file == "Part One.mkv")

        try Placer.apply(placement)
        #expect(!FileManager.default.fileExists(atPath: source.path), "moved, not copied")
        let tree = LibraryWalker.walk(sandbox.library)
        #expect(tree.findings.isEmpty)
        #expect(tree.roots.count == 1)
        #expect(tree.roots[0].sidecar.container == Self.series)
        #expect(tree.roots[0].sidecar.children == [Self.season.id: "Season 13/container.smd"])
        #expect(tree.roots[0].children[0].children[0].relativeFolder == "Doctor Who (1963)/Season 13/Pyramids of Mars")
        let serial = try #require(tree.node(for: Self.serial.id))
        #expect(serial.sidecar.presentations == ["part1": [placement.presentation]])
        #expect(Validator.check(tree).isEmpty)
    }

    @Test func aSecondPlacementUpdatesOnlyWhatChanged() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        try Placer.apply(try Placer.compute(PlacementRequest(library: sandbox.library, lineage: Self.lineage, item: "part1", presentation: Presentation(file: ""), source: try sandbox.source("a.mkv"))))

        // A person edits the serial's sidecar by hand; the next placement must leave the edit.
        let serialSidecar = sandbox.library.appendingPathComponent("Doctor Who (1963)/Season 13/Pyramids of Mars/container.smd")
        var text = String(decoding: try Data(contentsOf: serialSidecar), as: UTF8.self)
        text = text.replacingOccurrences(of: "<title>Pyramids of Mars</title>", with: "<!-- mine -->\n    <title>Pyramids of Mars</title>")
        try Data(text.utf8).write(to: serialSidecar)

        let mobile = try Placer.compute(PlacementRequest(
            library: sandbox.library, lineage: Self.lineage, item: "part1",
            presentation: Presentation(profile: "mobile", file: "", tracks: [TrackMapping(feature: "commentary1", audio: 2)]),
            source: try sandbox.source("b.mkv")
        ))
        #expect(mobile.folders.isEmpty)
        #expect(mobile.sidecars.map { LibraryWalker.relativePath(of: $0.url, in: sandbox.library) } == ["Doctor Who (1963)/Season 13/Pyramids of Mars/container.smd"], "the ancestors already know their children")
        #expect(mobile.presentation.file == "Part One - mobile.mkv")
        try Placer.apply(mobile)

        let se = try Placer.compute(PlacementRequest(library: sandbox.library, lineage: Self.lineage, item: "part1", presentation: Presentation(alternative: "se", file: ""), source: try sandbox.source("c.mkv")))
        #expect(se.presentation.file == "Part One - Updated special effects.mkv")
        try Placer.apply(se)

        let extra = try Placer.compute(PlacementRequest(library: sandbox.library, lineage: Self.lineage, item: "now-and-then", presentation: Presentation(file: ""), source: try sandbox.source("d.mkv")))
        #expect(extra.folders.map(\.lastPathComponent) == ["extras"])
        #expect(extra.presentation.file == "extras/Now and Then- Pyramids.mkv")
        try Placer.apply(extra)

        let updated = String(decoding: try Data(contentsOf: serialSidecar), as: UTF8.self)
        #expect(updated.contains("<!-- mine -->"))
        let tree = LibraryWalker.walk(sandbox.library)
        let serial = try #require(tree.node(for: Self.serial.id))
        #expect(serial.sidecar.presentations["part1"]?.map(\.file) == ["Part One.mkv", "Part One - mobile.mkv", "Part One - Updated special effects.mkv"])
        #expect(serial.sidecar.presentations["now-and-then"]?.map(\.file) == ["extras/Now and Then- Pyramids.mkv"])
        #expect(Validator.check(tree).isEmpty)
    }

    @Test func whatCannotBePlacedIsRefusedWithReasons() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        try Placer.apply(try Placer.compute(PlacementRequest(library: sandbox.library, lineage: Self.lineage, item: "part1", presentation: Presentation(file: ""), source: try sandbox.source("a.mkv"))))

        let again = try Placer.compute(PlacementRequest(library: sandbox.library, lineage: Self.lineage, item: "part1", presentation: Presentation(file: ""), source: try sandbox.source("b.mkv")))
        #expect(again.errors.map(\.text) == [
            "already exists; nothing is overwritten",
            "item part1 has two presentations for the same alternative and profile",
        ])
        #expect(throws: PlacementError.self) { try Placer.apply(again) }
        #expect(FileManager.default.fileExists(atPath: sandbox.root.appendingPathComponent("b.mkv").path), "nothing moved")

        let wrong = try Placer.compute(PlacementRequest(
            library: sandbox.library, lineage: Self.lineage, item: "part2",
            presentation: Presentation(alternative: "omnibus", file: "", tracks: [TrackMapping(feature: "music1", audio: 1)]),
            source: sandbox.root.appendingPathComponent("missing.mkv")
        ))
        #expect(wrong.errors.map(\.text) == [
            "Pyramids of Mars has no alternative omnibus",
            "Pyramids of Mars has no feature music1",
            "the source \(sandbox.root.path)/missing.mkv is not there",
            "item part2: presentation names alternative omnibus, which is not there",
            "item part2: a track for feature music1, which is not there",
        ])

        #expect(throws: PlacementError.self) {
            try Placer.compute(PlacementRequest(library: sandbox.library, lineage: Self.lineage, item: "part9", presentation: Presentation(file: ""), source: try sandbox.source("c.mkv")))
        }
        #expect(throws: PlacementError.self) {
            try Placer.compute(PlacementRequest(library: sandbox.library, lineage: [Self.series, Self.serial], item: "part1", presentation: Presentation(file: ""), source: try sandbox.source("d.mkv")))
        }
        #expect(throws: PlacementError.self) {
            try Placer.compute(PlacementRequest(library: sandbox.library, lineage: [], item: "part1", presentation: Presentation(file: ""), source: try sandbox.source("e.mkv")))
        }
    }

    @Test func theWalkReportsWhatIsBrokenOrAbandoned() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        try Placer.apply(try Placer.compute(PlacementRequest(library: sandbox.library, lineage: Self.lineage, item: "part1", presentation: Presentation(file: ""), source: try sandbox.source("a.mkv"))))

        let serialFolder = sandbox.library.appendingPathComponent("Doctor Who (1963)/Season 13/Pyramids of Mars")
        try FileManager.default.removeItem(at: serialFolder.appendingPathComponent("Part One.mkv"))
        let orphan = sandbox.library.appendingPathComponent("Doctor Who (1963)/Draft")
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        try SidecarFile.data(for: Sidecar(container: Container(id: ContainerID.mint(), type: .serial, title: Title("Draft")!))).write(to: orphan.appendingPathComponent("container.smd"))
        try FileManager.default.removeItem(at: sandbox.library.appendingPathComponent("Doctor Who (1963)/Season 13/container.smd"))

        let tree = LibraryWalker.walk(sandbox.library)
        #expect(tree.findings.map(\.description) == [
            "error: Doctor Who (1963)/container.smd: child 0000000000000002 is at \"Season 13/container.smd\", which does not exist",
            "warning: Doctor Who (1963)/Draft/container.smd: a sidecar nothing references",
            "warning: Doctor Who (1963)/Season 13/Pyramids of Mars/container.smd: a sidecar nothing references",
        ])
        #expect(Validator.check(tree).map(\.description) == tree.findings.map(\.description) + [
            "error: Doctor Who (1963)/container.smd: child 0000000000000002 at \"Season 13/container.smd\" is not there",
        ])

        var serial = try SidecarFile.sidecar(from: Data(contentsOf: serialFolder.appendingPathComponent("container.smd")))
        serial.presentations["part1"]?[0].file = "../Part One.mkv"
        serial.presentations["part1"]?.append(Presentation(file: "Part One.mkv"))
        #expect(Validator.check(serial).map(\.text) == [
            "item part1: \"../Part One.mkv\" leaves the container's folder",
            "item part1: \"../Part One.mkv\" is not the name the layout would give it, \"Part One.mkv\"",
            "item part1 has two presentations for the same alternative and profile",
        ])
    }

    @Test(arguments: [
        ("Doctor Who: The Movie", "Doctor Who- The Movie"),
        ("  Face/Off  ", "Face-Off"),
        ("..hidden", "hidden"),
        ("Two   spaces\tand\ttabs", "Two spaces and tabs"),
    ])
    func namesAreSanitised(title: String, expected: String) {
        #expect(LibraryLayout.sanitise(title) == expected)
    }

    @Test func theWalkReportsAContainersRulesThatCannotBeRead() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        try Placer.apply(try Placer.compute(PlacementRequest(library: sandbox.library, lineage: Self.lineage, item: "part1", presentation: Presentation(file: ""), source: try sandbox.source("a.mkv"))))
        let serialFolder = sandbox.library.appendingPathComponent("Doctor Who (1963)/Season 13/Pyramids of Mars")
        let sidecar = serialFolder.appendingPathComponent("container.smd")
        let rules = serialFolder.appendingPathComponent("rules")
        try FileManager.default.createDirectory(at: rules, withIntermediateDirectories: true)
        func point(at version: Int) throws {
            try SidecarFile.data(settingRules: SidecarRules(activeVersion: version), in: Data(contentsOf: sidecar)).write(to: sidecar)
        }

        try Data(#"<rules><video><copy/></video></rules>"#.utf8).write(to: rules.appendingPathComponent("1.xml"))
        try point(at: 1)
        #expect(LibraryWalker.walk(sandbox.library).findings.isEmpty, "rules that read are no finding")

        try point(at: 5)
        #expect(LibraryWalker.walk(sandbox.library).findings.map(\.description) == [
            "error: Doctor Who (1963)/Season 13/Pyramids of Mars/container.smd: rules version 5 is not there",
        ])

        try Data(#"<rules><audio><when fact="audio.bitrate" is="1"/><copy/></audio></rules>"#.utf8).write(to: rules.appendingPathComponent("2.xml"))
        try point(at: 2)
        let refused = LibraryWalker.walk(sandbox.library).findings.map(\.description)
        #expect(refused.count == 1)
        #expect(refused.first?.contains("rules version 2:") == true && refused.first?.contains("audio.bitrate") == true, "\(refused)")

        try SidecarFile.data(for: placementOf(sidecar: sidecar), updating: Data(contentsOf: sidecar)).write(to: sidecar)
        #expect(try SidecarFile.sidecar(from: Data(contentsOf: sidecar)).rules == SidecarRules(activeVersion: 2), "a placement keeps the reference")
    }

    /// The serial's sidecar as a placement would update it: a presentation for part two, no rules.
    private func placementOf(sidecar: URL) throws -> Sidecar {
        var value = try SidecarFile.sidecar(from: Data(contentsOf: sidecar))
        value.rules = nil
        value.presentations["part2"] = [Presentation(file: "Part Two.mkv")]
        return value
    }

    @Test func pathsAreCheckedForStayingInside() {
        #expect(LibraryLayout.isInside("Part One.mkv"))
        #expect(LibraryLayout.isInside("extras/Now.mkv"))
        #expect(!LibraryLayout.isInside("../Part One.mkv"))
        #expect(!LibraryLayout.isInside("extras/../../x.mkv"))
        #expect(!LibraryLayout.isInside("/abs.mkv"))
        #expect(!LibraryLayout.isInside(""))
        #expect(!LibraryLayout.isInside("a//b.mkv"))
        #expect(LibraryLayout.fileName(for: .leaf(Entry.Leaf(id: ItemID("part1")!, type: .episode)), displayName: nil, fileExtension: "mkv") == "part1.mkv")
        #expect(LibraryLayout.folderName(for: Container(id: ContainerID("00000000000000aa")!, type: .movie, title: Title("///")!)) == "---")
    }
}
