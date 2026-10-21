// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SmdKit
import SmdSidecar
import Testing

@testable import SiloLibrary

struct PlacementTests {
    static let series: Container = {
        var series = Container(
            id: ContainerID("0000000000000001")!,
            type: .series,
            title: Title("Doctor Who")!,
            year: 1963,
            yearInTitle: true
        )
        series.sequences = [
            Sequence(id: "seasons", items: [.child(Entry.Child(id: ItemID("s13")!, container: season.id))])
        ]
        return series
    }()
    static let season: Container = {
        var season = Container(id: ContainerID("0000000000000002")!, type: .season, title: Title("Season 13")!)
        season.sequences = [
            Sequence(id: "stories", items: [.child(Entry.Child(id: ItemID("pyramids")!, container: serial.id))])
        ]
        return season
    }()
    static let serial: Container = {
        var serial = Container(
            id: ContainerID("0000000000000003")!,
            type: .serial,
            typeLabel: "Story",
            title: Title("Pyramids of Mars")!
        )
        serial.alternatives = [
            Alternative(id: "broadcast", sequence: "parts", title: "Broadcast version"),
            Alternative(id: "se", sequence: "parts", title: "Updated special effects"),
        ]
        serial.defaultAlternative = "broadcast"
        serial.features = [Feature(id: "commentary1", type: .commentary, title: "Commentary")]
        serial.sequences = [
            Sequence(
                id: "parts",
                items: [
                    .leaf(Entry.Leaf(id: ItemID("part1")!, type: .episode, title: "Part One")),
                    .leaf(Entry.Leaf(id: ItemID("part2")!, type: .episode, title: "Part Two")),
                ]
            )
        ]
        serial.extras = [
            .leaf(Entry.Leaf(id: ItemID("now-and-then")!, type: .featurette, title: "Now and Then: Pyramids"))
        ]
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
            library: sandbox.library,
            lineage: Self.lineage,
            item: "part1",
            presentation: Presentation(
                file: "",
                source: PresentationSource(
                    binding: "5b0e7c1a-3d2f-4e8a-9c41-7f0d2e6a91d2",
                    segments: [.init(key: SmdSidecar.NaturalKey(scheme: "discTitle", value: "3F1A/00004.mpls"))]
                ),
                tracks: [TrackMapping(feature: "commentary1", audio: 3)],
                chapters: [Chapter(index: 1, title: "Opening")]
            ),
            source: source
        )
        let placement = try Placer.compute(request)
        #expect(placement.isApplicable)
        #expect(
            placement.describe(relativeTo: sandbox.library) == [
                "create   Doctor Who (1963)/",
                "create   Doctor Who (1963)/01 - Season 13/",
                "create   Doctor Who (1963)/01 - Season 13/01 - Pyramids of Mars/",
                "place    \(source.path) -> Doctor Who (1963)/01 - Season 13/01 - Pyramids of Mars/Part One.mkv",
                "write    Doctor Who (1963)/container.smd",
                "write    Doctor Who (1963)/01 - Season 13/container.smd",
                "write    Doctor Who (1963)/01 - Season 13/01 - Pyramids of Mars/container.smd",
            ]
        )
        #expect(placement.presentation.file == "Part One.mkv")

        try Placer.apply(placement)
        #expect(!FileManager.default.fileExists(atPath: source.path), "moved, not copied")
        let tree = LibraryWalker.walk(sandbox.library)
        #expect(tree.findings.isEmpty)
        #expect(tree.roots.count == 1)
        #expect(tree.roots[0].sidecar.container == Self.series)
        #expect(tree.roots[0].sidecar.children == [Self.season.id: "01 - Season 13/container.smd"])
        #expect(
            tree.roots[0].children[0].children[0].relativeFolder
                == "Doctor Who (1963)/01 - Season 13/01 - Pyramids of Mars"
        )
        let serial = try #require(tree.node(for: Self.serial.id))
        #expect(serial.sidecar.presentations == ["part1": [placement.presentation]])
        #expect(Validator.check(tree).isEmpty)
    }

    /// A serial with one part, as a child of whatever holds it.
    static func story(_ id: String, _ title: String) -> Container {
        var story = Container(id: ContainerID(id)!, type: .serial, title: Title(title)!)
        story.sequences = [
            Sequence(id: "parts", items: [.leaf(Entry.Leaf(id: ItemID("part1")!, type: .episode, title: "Part One"))])
        ]
        return story
    }

    /// A child's folder begins with its position among its parent's children, padded to two digits
    /// or as many as the count needs; a root keeps its title alone.
    @Test func childFoldersAreNumberedInTheirOrder() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let stories = [
            Self.story("0000000000000011", "Terror of the Zygons"),
            Self.story("0000000000000012", "Planet of Evil"),
            Self.story("0000000000000013", "Pyramids of Mars"),
        ]
        var season = Self.season
        season.sequences = [
            Sequence(
                id: "stories",
                items: stories.enumerated().map { index, story in
                    .child(Entry.Child(id: ItemID("s\(index)")!, container: story.id))
                }
            )
        ]
        func place(_ lineage: [Container]) throws -> String {
            let placement = try Placer.compute(
                PlacementRequest(
                    library: sandbox.library,
                    lineage: lineage,
                    item: "part1",
                    presentation: Presentation(file: ""),
                    source: try sandbox.source("\(UUID().uuidString).mkv")
                )
            )
            try Placer.apply(placement)
            return LibraryWalker.relativePath(
                of: placement.destination.deletingLastPathComponent(),
                in: sandbox.library
            )
        }
        // Placed out of order, each is numbered by where its parent names it.
        #expect(
            try place([Self.series, season, stories[2]]) == "Doctor Who (1963)/01 - Season 13/03 - Pyramids of Mars"
        )
        #expect(
            try place([Self.series, season, stories[0]]) == "Doctor Who (1963)/01 - Season 13/01 - Terror of the Zygons"
        )
        #expect(try place([Self.series, season, stories[1]]) == "Doctor Who (1963)/01 - Season 13/02 - Planet of Evil")
        #expect(LibraryWalker.walk(sandbox.library).findings.isEmpty)

        let episodes = (1...120).map { Self.story(String(format: "%016x", 0x100 + $0), "Episode \($0)") }
        var long = Container(id: ContainerID("0000000000000099")!, type: .series, title: Title("Neighbours")!)
        long.sequences = [
            Sequence(
                id: "episodes",
                items: episodes.enumerated().map { index, episode in
                    .child(Entry.Child(id: ItemID("e\(index)")!, container: episode.id))
                }
            )
        ]
        #expect(try place([long, episodes[0]]) == "Neighbours/001 - Episode 1")
        #expect(try place([long, episodes[119]]) == "Neighbours/120 - Episode 120")
        #expect(
            LibraryLayout.Position(of: episodes[0].id, among: [episodes[0].id, episodes[0].id])
                == .init(number: 1, count: 1)
        )
    }

    /// A container already in the library is where its parent's sidecar records it: a folder renamed
    /// by hand, or a title corrected in the library, is filed into rather than beside.
    @Test func aPlacementFollowsThePathItsParentRecords() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        func compute(_ item: String, lineage: [Container] = Self.lineage, profile: String? = nil) throws -> Placement {
            try Placer.compute(
                PlacementRequest(
                    library: sandbox.library,
                    lineage: lineage,
                    item: item,
                    presentation: Presentation(profile: profile, file: ""),
                    source: try sandbox.source("\(UUID().uuidString).mkv")
                )
            )
        }
        try Placer.apply(try compute("part1"))
        let series = sandbox.library.appendingPathComponent("Doctor Who (1963)")
        try FileManager.default.moveItem(
            at: series.appendingPathComponent("01 - Season 13"),
            to: series.appendingPathComponent("Season 13")
        )
        let seriesURL = series.appendingPathComponent("container.smd")
        let existing = try Data(contentsOf: seriesURL)
        var sidecar = try SidecarFile.sidecar(from: existing)
        sidecar.children[Self.season.id] = "Season 13/container.smd"
        try SidecarFile.data(for: sidecar, updating: existing).write(to: seriesURL)

        let part2 = try compute("part2")
        #expect(part2.folders.isEmpty, "no 01 - Season 13 is made")
        #expect(
            LibraryWalker.relativePath(of: part2.destination, in: sandbox.library)
                == "Doctor Who (1963)/Season 13/01 - Pyramids of Mars/Part Two.mkv"
        )
        #expect(!part2.sidecars.contains { $0.url == seriesURL }, "the series' sidecar is not rewritten")
        try Placer.apply(part2)

        var retitled = Self.serial
        retitled.title = Title("The Pyramids of Mars")!
        let mobile = try compute("part1", lineage: [Self.series, Self.season, retitled], profile: "mobile")
        #expect(mobile.folders.isEmpty)
        #expect(
            LibraryWalker.relativePath(of: mobile.destination, in: sandbox.library)
                == "Doctor Who (1963)/Season 13/01 - Pyramids of Mars/Part One - mobile.mkv"
        )
    }

    @Test func aSecondPlacementUpdatesOnlyWhatChanged() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        try Placer.apply(
            try Placer.compute(
                PlacementRequest(
                    library: sandbox.library,
                    lineage: Self.lineage,
                    item: "part1",
                    presentation: Presentation(file: ""),
                    source: try sandbox.source("a.mkv")
                )
            )
        )

        // A person edits the serial's sidecar by hand; the next placement must leave the edit.
        let serialSidecar = sandbox.library.appendingPathComponent(
            "Doctor Who (1963)/01 - Season 13/01 - Pyramids of Mars/container.smd"
        )
        var text = String(decoding: try Data(contentsOf: serialSidecar), as: UTF8.self)
        text = text.replacingOccurrences(
            of: "<title>Pyramids of Mars</title>",
            with: "<!-- mine -->\n    <title>Pyramids of Mars</title>"
        )
        try Data(text.utf8).write(to: serialSidecar)

        let mobile = try Placer.compute(
            PlacementRequest(
                library: sandbox.library,
                lineage: Self.lineage,
                item: "part1",
                presentation: Presentation(
                    profile: "mobile",
                    file: "",
                    tracks: [TrackMapping(feature: "commentary1", audio: 2)]
                ),
                source: try sandbox.source("b.mkv")
            )
        )
        #expect(mobile.folders.isEmpty)
        #expect(
            mobile.sidecars.map { LibraryWalker.relativePath(of: $0.url, in: sandbox.library) } == [
                "Doctor Who (1963)/01 - Season 13/01 - Pyramids of Mars/container.smd"
            ],
            "the ancestors already know their children"
        )
        #expect(mobile.presentation.file == "Part One - mobile.mkv")
        try Placer.apply(mobile)

        let se = try Placer.compute(
            PlacementRequest(
                library: sandbox.library,
                lineage: Self.lineage,
                item: "part1",
                presentation: Presentation(alternative: "se", file: ""),
                source: try sandbox.source("c.mkv")
            )
        )
        #expect(se.presentation.file == "Part One - Updated special effects.mkv")
        try Placer.apply(se)

        let extra = try Placer.compute(
            PlacementRequest(
                library: sandbox.library,
                lineage: Self.lineage,
                item: "now-and-then",
                presentation: Presentation(file: ""),
                source: try sandbox.source("d.mkv")
            )
        )
        #expect(extra.folders.map(\.lastPathComponent) == ["extras"])
        #expect(extra.presentation.file == "extras/Now and Then- Pyramids.mkv")
        try Placer.apply(extra)

        let updated = String(decoding: try Data(contentsOf: serialSidecar), as: UTF8.self)
        #expect(updated.contains("<!-- mine -->"))
        let tree = LibraryWalker.walk(sandbox.library)
        let serial = try #require(tree.node(for: Self.serial.id))
        #expect(
            serial.sidecar.presentations["part1"]?.map(\.file) == [
                "Part One.mkv", "Part One - mobile.mkv", "Part One - Updated special effects.mkv",
            ]
        )
        #expect(serial.sidecar.presentations["now-and-then"]?.map(\.file) == ["extras/Now and Then- Pyramids.mkv"])
        #expect(Validator.check(tree).isEmpty)
    }

    @Test func whatCannotBePlacedIsRefusedWithReasons() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        try Placer.apply(
            try Placer.compute(
                PlacementRequest(
                    library: sandbox.library,
                    lineage: Self.lineage,
                    item: "part1",
                    presentation: Presentation(file: ""),
                    source: try sandbox.source("a.mkv")
                )
            )
        )

        let again = try Placer.compute(
            PlacementRequest(
                library: sandbox.library,
                lineage: Self.lineage,
                item: "part1",
                presentation: Presentation(file: ""),
                source: try sandbox.source("b.mkv")
            )
        )
        #expect(
            again.errors.map(\.text) == [
                "already exists; nothing is overwritten",
                "item part1 has two presentations for the same alternative and profile",
            ]
        )
        #expect(throws: PlacementError.self) { try Placer.apply(again) }
        #expect(
            FileManager.default.fileExists(atPath: sandbox.root.appendingPathComponent("b.mkv").path),
            "nothing moved"
        )

        let wrong = try Placer.compute(
            PlacementRequest(
                library: sandbox.library,
                lineage: Self.lineage,
                item: "part2",
                presentation: Presentation(
                    alternative: "omnibus",
                    file: "",
                    tracks: [TrackMapping(feature: "music1", audio: 1)]
                ),
                source: sandbox.root.appendingPathComponent("missing.mkv")
            )
        )
        #expect(
            wrong.errors.map(\.text) == [
                "Pyramids of Mars has no alternative omnibus",
                "Pyramids of Mars has no feature music1",
                "the source \(sandbox.root.path)/missing.mkv is not there",
                "item part2: presentation names alternative omnibus, which is not there",
                "item part2: a track for feature music1, which is not there",
            ]
        )

        #expect(throws: PlacementError.self) {
            try Placer.compute(
                PlacementRequest(
                    library: sandbox.library,
                    lineage: Self.lineage,
                    item: "part9",
                    presentation: Presentation(file: ""),
                    source: try sandbox.source("c.mkv")
                )
            )
        }
        #expect(throws: PlacementError.self) {
            try Placer.compute(
                PlacementRequest(
                    library: sandbox.library,
                    lineage: [Self.series, Self.serial],
                    item: "part1",
                    presentation: Presentation(file: ""),
                    source: try sandbox.source("d.mkv")
                )
            )
        }
        #expect(throws: PlacementError.self) {
            try Placer.compute(
                PlacementRequest(
                    library: sandbox.library,
                    lineage: [],
                    item: "part1",
                    presentation: Presentation(file: ""),
                    source: try sandbox.source("e.mkv")
                )
            )
        }
    }

    @Test func aTreeOfContainersIsMadeWithNoFile() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }

        // The tree in an empty library, the documents in any order: made from the top down.
        let making = try Maker.compute(
            MakingRequest(library: sandbox.library, holder: nil, containers: [Self.serial, Self.series, Self.season])
        )
        #expect(
            making.describe(relativeTo: sandbox.library) == [
                "create   Doctor Who (1963)/",
                "create   Doctor Who (1963)/01 - Season 13/",
                "create   Doctor Who (1963)/01 - Season 13/01 - Pyramids of Mars/",
                "write    Doctor Who (1963)/container.smd",
                "write    Doctor Who (1963)/01 - Season 13/container.smd",
                "write    Doctor Who (1963)/01 - Season 13/01 - Pyramids of Mars/container.smd",
            ]
        )
        #expect(making.sidecars.map(\.parent) == [nil, Self.series.id, Self.season.id])
        try Maker.apply(making)
        let seriesURL = sandbox.library.appendingPathComponent("Doctor Who (1963)/container.smd")
        let made = try SidecarFile.sidecar(from: Data(contentsOf: seriesURL))
        #expect(made.container == Self.series)
        #expect(made.children == [Self.season.id: "01 - Season 13/container.smd"])
        let serial = try SidecarFile.sidecar(
            from: Data(
                contentsOf: sandbox.library.appendingPathComponent(
                    "Doctor Who (1963)/01 - Season 13/01 - Pyramids of Mars/container.smd"
                )
            )
        )
        #expect(serial.presentations.isEmpty, "no file is placed")
        #expect(LibraryWalker.walk(sandbox.library).findings.filter { $0.severity == .error }.isEmpty)

        // A season beneath the series, which holds a presentation: its sidecar is updated last, with the
        // season's path alone.
        let source = try sandbox.source("a.mkv")
        try Placer.apply(
            try Placer.compute(
                PlacementRequest(
                    library: sandbox.library,
                    lineage: Self.lineage,
                    item: "part1",
                    presentation: Presentation(profile: nil, file: ""),
                    source: source
                )
            )
        )
        var series = Self.series
        let season14 = Container(id: ContainerID("0000000000000004")!, type: .season, title: Title("Season 14")!)
        series.sequences[0].items.append(.child(Entry.Child(id: ItemID("s14")!, container: season14.id)))
        try SidecarFile.data(settingContainer: series, in: Data(contentsOf: seriesURL)).write(to: seriesURL)
        let seriesFolder = sandbox.library.appendingPathComponent("Doctor Who (1963)", isDirectory: true)
        let beneath = try Maker.compute(
            MakingRequest(
                library: sandbox.library,
                holder: MakingRequest.Holder(folder: seriesFolder, parent: nil),
                containers: [season14]
            )
        )
        #expect(
            beneath.describe(relativeTo: sandbox.library) == [
                "create   Doctor Who (1963)/02 - Season 14/",
                "write    Doctor Who (1963)/02 - Season 14/container.smd",
                "update   Doctor Who (1963)/container.smd",
            ]
        )
        #expect(beneath.sidecars.map(\.parent) == [Self.series.id, nil])
        try Maker.apply(beneath)
        let updated = try SidecarFile.sidecar(from: Data(contentsOf: seriesURL))
        #expect(updated.container == series)
        #expect(updated.children[season14.id] == "02 - Season 14/container.smd")
        #expect(updated.children[Self.season.id] == "01 - Season 13/container.smd")

        // A folder holding another container, and the same container already there, are refused and
        // make nothing; so is a holder that does not name the top.
        let impostor = Container(
            id: ContainerID("00000000000000aa")!,
            type: .series,
            title: Self.series.title,
            year: 1963,
            yearInTitle: true
        )
        let taken = try Maker.compute(MakingRequest(library: sandbox.library, holder: nil, containers: [impostor]))
        #expect(taken.errors.map(\.text) == ["the folder for Doctor Who (1963) already holds \(Self.series.id)"])
        #expect(throws: MakingError.refused(taken.errors)) { try Maker.apply(taken) }
        let again = try Maker.compute(MakingRequest(library: sandbox.library, holder: nil, containers: [Self.series]))
        #expect(again.errors.map(\.text) == ["container \(Self.series.id) is already at \"Doctor Who (1963)\""])
        let season15 = Container(id: ContainerID("0000000000000005")!, type: .season, title: Title("Season 15")!)
        let unnamed = try Maker.compute(
            MakingRequest(
                library: sandbox.library,
                holder: MakingRequest.Holder(folder: seriesFolder, parent: nil),
                containers: [season15]
            )
        )
        #expect(unnamed.errors.map(\.text) == ["\(Self.series.id) does not name \(season15.id) as a child"])
        #expect(!FileManager.default.fileExists(atPath: seriesFolder.appendingPathComponent("Season 15").path))

        // Containers that are not one tree are thrown, not found.
        #expect(throws: MakingError.empty) {
            try Maker.compute(MakingRequest(library: sandbox.library, holder: nil, containers: []))
        }
        #expect(throws: MakingError.self) {
            try Maker.compute(MakingRequest(library: sandbox.library, holder: nil, containers: [season14, season15]))
        }
        #expect(throws: MakingError.self) {
            try Maker.compute(MakingRequest(library: sandbox.library, holder: nil, containers: [season14, season14]))
        }
    }

    @Test func theWalkReportsWhatIsBrokenOrAbandoned() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        try Placer.apply(
            try Placer.compute(
                PlacementRequest(
                    library: sandbox.library,
                    lineage: Self.lineage,
                    item: "part1",
                    presentation: Presentation(file: ""),
                    source: try sandbox.source("a.mkv")
                )
            )
        )

        let serialFolder = sandbox.library.appendingPathComponent(
            "Doctor Who (1963)/01 - Season 13/01 - Pyramids of Mars"
        )
        try FileManager.default.removeItem(at: serialFolder.appendingPathComponent("Part One.mkv"))
        let orphan = sandbox.library.appendingPathComponent("Doctor Who (1963)/Draft")
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        try SidecarFile.data(
            for: Sidecar(container: Container(id: ContainerID.mint(), type: .serial, title: Title("Draft")!))
        ).write(to: orphan.appendingPathComponent("container.smd"))
        try FileManager.default.removeItem(
            at: sandbox.library.appendingPathComponent("Doctor Who (1963)/01 - Season 13/container.smd")
        )

        let tree = LibraryWalker.walk(sandbox.library)
        #expect(
            tree.findings.map(\.description) == [
                "error: Doctor Who (1963)/container.smd: child 0000000000000002 is at \"01 - Season 13/container.smd\", which does not exist",
                "warning: Doctor Who (1963)/01 - Season 13/01 - Pyramids of Mars/container.smd: a sidecar nothing references",
                "warning: Doctor Who (1963)/Draft/container.smd: a sidecar nothing references",
            ]
        )
        #expect(
            Validator.check(tree).map(\.description) == tree.findings.map(\.description) + [
                "error: Doctor Who (1963)/container.smd: child 0000000000000002 at \"01 - Season 13/container.smd\" is not there"
            ]
        )

        var serial = try SidecarFile.sidecar(
            from: Data(contentsOf: serialFolder.appendingPathComponent("container.smd"))
        )
        serial.presentations["part1"]?[0].file = "../Part One.mkv"
        serial.presentations["part1"]?.append(Presentation(file: "Part One.mkv"))
        #expect(
            Validator.check(serial).map(\.text) == [
                "item part1: \"../Part One.mkv\" leaves the container's folder",
                "item part1: \"../Part One.mkv\" is not the name the layout would give it, \"Part One.mkv\"",
                "item part1 has two presentations for the same alternative and profile",
            ]
        )
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
        try Placer.apply(
            try Placer.compute(
                PlacementRequest(
                    library: sandbox.library,
                    lineage: Self.lineage,
                    item: "part1",
                    presentation: Presentation(file: ""),
                    source: try sandbox.source("a.mkv")
                )
            )
        )
        let serialFolder = sandbox.library.appendingPathComponent(
            "Doctor Who (1963)/01 - Season 13/01 - Pyramids of Mars"
        )
        let sidecar = serialFolder.appendingPathComponent("container.smd")
        let rules = serialFolder.appendingPathComponent("rules")
        try FileManager.default.createDirectory(at: rules, withIntermediateDirectories: true)
        func point(at version: Int) throws {
            try SidecarFile.data(settingRules: SidecarRules(activeVersion: version), in: Data(contentsOf: sidecar))
                .write(to: sidecar)
        }

        try Data(#"<rules><video><copy/></video></rules>"#.utf8).write(to: rules.appendingPathComponent("1.xml"))
        try point(at: 1)
        #expect(LibraryWalker.walk(sandbox.library).findings.isEmpty, "rules that read are no finding")

        try point(at: 5)
        #expect(
            LibraryWalker.walk(sandbox.library).findings.map(\.description) == [
                "error: Doctor Who (1963)/01 - Season 13/01 - Pyramids of Mars/container.smd: rules version 5 is not there"
            ]
        )

        try Data(#"<rules><audio><when fact="audio.bitrate" is="1"/><copy/></audio></rules>"#.utf8).write(
            to: rules.appendingPathComponent("2.xml")
        )
        try point(at: 2)
        let refused = LibraryWalker.walk(sandbox.library).findings.map(\.description)
        #expect(refused.count == 1)
        #expect(
            refused.first?.contains("rules version 2:") == true && refused.first?.contains("audio.bitrate") == true,
            "\(refused)"
        )

        try SidecarFile.data(for: placementOf(sidecar: sidecar), updating: Data(contentsOf: sidecar)).write(to: sidecar)
        #expect(
            try SidecarFile.sidecar(from: Data(contentsOf: sidecar)).rules == SidecarRules(activeVersion: 2),
            "a placement keeps the reference"
        )
    }

    /// The serial's sidecar as a placement would update it: a presentation for part two, no rules.
    private func placementOf(sidecar: URL) throws -> Sidecar {
        var value = try SidecarFile.sidecar(from: Data(contentsOf: sidecar))
        value.rules = nil
        value.presentations["part2"] = [Presentation(file: "Part Two.mkv")]
        return value
    }

    /// Places part one, gives the serial an outline, and returns the serial's sidecar.
    private func placedSerial(in sandbox: Sandbox) throws -> URL {
        try Placer.apply(
            try Placer.compute(
                PlacementRequest(
                    library: sandbox.library,
                    lineage: Self.lineage,
                    item: "part1",
                    presentation: Presentation(file: ""),
                    source: try sandbox.source("a.mkv")
                )
            )
        )
        return sandbox.library.appendingPathComponent(
            "Doctor Who (1963)/01 - Season 13/01 - Pyramids of Mars/container.smd"
        )
    }

    private func placePartTwo(in sandbox: Sandbox, lineage: [Container] = lineage) throws {
        try Placer.apply(
            try Placer.compute(
                PlacementRequest(
                    library: sandbox.library,
                    lineage: lineage,
                    item: "part2",
                    presentation: Presentation(file: ""),
                    source: try sandbox.source("b.mkv")
                )
            )
        )
    }

    @Test func attributionsAreLibraryFacts() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let url = try placedSerial(in: sandbox)
        var serial = Self.serial
        serial.outline = "Sutekh is imprisoned beneath a pyramid."
        let outline = Attribution(subject: .outline, provider: .tmdb, value: "1012")
        let edited = try SidecarFile.data(
            settingAttributions: [outline],
            in: SidecarFile.data(settingContainer: serial, in: Data(contentsOf: url))
        )
        try edited.write(to: url)

        try placePartTwo(in: sandbox, lineage: [Self.series, Self.season, serial])
        let placed = try SidecarFile.sidecar(from: Data(contentsOf: url))
        #expect(placed.attributions == [outline], "a placement keeps them")
        #expect(placed.presentations["part2"]?.count == 1)
        #expect(Validator.check(placed).isEmpty)

        var unattributed = placed
        unattributed.container.outline = nil
        #expect(
            Validator.check(unattributed).map(\.text) == ["outline is attributed to tmdb but the container has none"]
        )
        var odd = placed
        odd.attributions = [
            outline,
            outline,
            Attribution(subject: .outline(ofAlternative: "se"), provider: .tmdb, value: "1012"),
            Attribution(subject: Attribution.Subject(rawValue: "tagline"), provider: .tmdb, value: "1012"),
            Attribution(subject: .artwork("poster"), provider: .tmdb, value: "1012"),
        ]
        #expect(
            Validator.check(odd).map(\.text) == [
                "outline is attributed twice",
                "alternative/se/outline is attributed to tmdb but the container has none",
                "tagline is not a field or an artwork kind to attribute",
            ]
        )
    }

    @Test func declinedRefsAreLibraryFacts() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let url = try placedSerial(in: sandbox)
        let trailer = ExternalRef(provider: .tmdb, value: "99")
        try SidecarFile.data(settingDeclined: [trailer], in: Data(contentsOf: url)).write(to: url)

        try placePartTwo(in: sandbox)
        let placed = try SidecarFile.sidecar(from: Data(contentsOf: url))
        #expect(placed.declined == [trailer], "a placement keeps them")
        #expect(Validator.check(placed).isEmpty)

        var held = placed
        held.declined = [trailer, trailer]
        held.container.sequences[0].items[0] = .leaf(
            Entry.Leaf(id: ItemID("part1")!, type: .episode, title: "Part One", externalRefs: [trailer])
        )
        #expect(
            Validator.check(held).map(\.text) == [
                "tmdb 99 is declined but item part1 carries it",
                "tmdb 99 is declined twice",
            ]
        )
    }

    @Test func pathsAreCheckedForStayingInside() {
        #expect(LibraryLayout.isInside("Part One.mkv"))
        #expect(LibraryLayout.isInside("extras/Now.mkv"))
        #expect(!LibraryLayout.isInside("../Part One.mkv"))
        #expect(!LibraryLayout.isInside("extras/../../x.mkv"))
        #expect(!LibraryLayout.isInside("/abs.mkv"))
        #expect(!LibraryLayout.isInside(""))
        #expect(!LibraryLayout.isInside("a//b.mkv"))
        #expect(
            LibraryLayout.fileName(
                for: .leaf(Entry.Leaf(id: ItemID("part1")!, type: .episode)),
                displayName: nil,
                fileExtension: "mkv"
            ) == "part1.mkv"
        )
        #expect(
            LibraryLayout.folderName(
                for: Container(id: ContainerID("00000000000000aa")!, type: .movie, title: Title("///")!)
            ) == "---"
        )
    }
}
