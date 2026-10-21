// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import GRDB
import SiloLibrary
import SmdKit
import SmdSidecar
import Testing

@testable import SiloStore

struct IndexTests {
    static let series: Container = {
        var series = Container(
            id: ContainerID("0000000000000001")!,
            type: .series,
            title: Title("Doctor Who")!,
            year: 1963,
            yearInTitle: true,
            externalRefs: [ExternalRef(provider: .tvdb, value: "76107")]
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
        serial.alternatives = [Alternative(id: "broadcast", sequence: "parts", title: "Broadcast version")]
        serial.defaultAlternative = "broadcast"
        serial.sequences = [
            Sequence(
                id: "parts",
                items: [
                    .leaf(
                        Entry.Leaf(
                            id: ItemID("part1")!,
                            type: .episode,
                            title: "Part One",
                            externalRefs: [ExternalRef(provider: .tvdb, value: "1")]
                        )
                    ),
                    .leaf(Entry.Leaf(id: ItemID("part2")!, type: .episode, title: "Part Two")),
                ]
            )
        ]
        serial.extras = [.leaf(Entry.Leaf(id: ItemID("now-and-then")!, type: .featurette, title: "Now and Then"))]
        return serial
    }()
    static let unlisted: Container = {
        var behind = Container(
            id: ContainerID("0000000000000004")!,
            type: .series,
            title: Title("Behind the Sofa")!,
            listed: false
        )
        behind.sequences = [
            Sequence(
                id: "all",
                items: [.leaf(Entry.Leaf(id: ItemID("ep1")!, type: .episode, title: "Pyramids of Mars"))]
            )
        ]
        return behind
    }()

    struct Sandbox {
        let root: URL
        let library: LibraryConfig
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("silo-index-\(UUID().uuidString)")
            library = LibraryConfig(id: "main", root: root.appendingPathComponent("Library"))
            try FileManager.default.createDirectory(at: library.root, withIntermediateDirectories: true)
        }
        func place(
            _ lineage: [Container],
            item: String,
            profile: String? = nil,
            into library: LibraryConfig? = nil
        ) throws {
            let source = root.appendingPathComponent("\(UUID().uuidString).mkv")
            try Data("video".utf8).write(to: source)
            try Placer.apply(
                try Placer.compute(
                    PlacementRequest(
                        library: (library ?? self.library).root,
                        lineage: lineage,
                        item: item,
                        presentation: Presentation(profile: profile, file: ""),
                        source: source
                    )
                )
            )
        }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    @Test func aScanIndexesWhatThePlacerWrote() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        try sandbox.place([Self.series, Self.season, Self.serial], item: "part1")
        try sandbox.place([Self.series, Self.season, Self.serial], item: "part1", profile: "mobile")
        try sandbox.place([Self.series, Self.season, Self.serial], item: "now-and-then")
        try sandbox.place([Self.unlisted], item: "ep1")

        let index = try Index(at: nil)
        let report = try Indexer.scan(sandbox.library, into: index)
        #expect(report.read == 4)
        #expect(report.unchanged == 0)
        #expect(report.findings.isEmpty)
        #expect(try index.count() == (containers: 4, presentations: 4))

        #expect(try index.roots().map(\.displayTitle) == ["Doctor Who (1963)"])
        #expect(try index.roots(listedOnly: false).map(\.displayTitle) == ["Behind the Sofa", "Doctor Who (1963)"])
        let serial = try #require(try index.container(Self.serial.id, in: "main"))
        #expect(serial.parent == Self.season.id.value)
        #expect(serial.folder == "Doctor Who (1963)/01 - Season 13/01 - Pyramids of Mars")
        #expect(serial.typeLabel == "Story")
        #expect(try index.sidecar(Self.serial.id, in: "main")?.container == Self.serial)
        #expect(try index.children(of: Self.series.id, in: "main").map(\.id) == [Self.season.id.value])
        #expect(try index.items(of: Self.serial.id, in: "main").map(\.id) == ["part1", "part2", "now-and-then"])
        #expect(try index.items(of: Self.serial.id, in: "main").map(\.isExtra) == [false, false, true])

        let presentations = try index.presentations(of: Self.serial.id, in: "main")
        #expect(
            presentations.map(\.path).sorted() == [
                "Doctor Who (1963)/01 - Season 13/01 - Pyramids of Mars/Part One - mobile.mkv",
                "Doctor Who (1963)/01 - Season 13/01 - Pyramids of Mars/Part One.mkv",
                "Doctor Who (1963)/01 - Season 13/01 - Pyramids of Mars/extras/Now and Then.mkv",
            ]
        )
        let mobile = try #require(presentations.first { $0.profile == "mobile" })
        #expect(try index.presentation(mobile.id) == mobile)
        #expect(
            mobile.id
                == IndexedPresentation.id(
                    library: "main",
                    container: Self.serial.id.value,
                    item: "part1",
                    alternative: nil,
                    profile: "mobile"
                )
        )

        #expect(try index.lookup(provider: .tvdb, value: "76107").map(\.id) == [Self.series.id.value])
        #expect(
            try index.lookup(provider: .tvdb, value: "1").map(\.id) == [Self.serial.id.value],
            "an item's reference names its container"
        )
        #expect(
            try index.search("pyramids").map { "\($0.container)/\($0.item ?? "-")" } == [
                "0000000000000003/-", "0000000000000004/ep1",
            ]
        )
        #expect(try index.search("part").map(\.title) == ["Part One", "Part Two"])
    }

    @Test func aSecondScanReadsOnlyWhatChanged() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        try sandbox.place([Self.series, Self.season, Self.serial], item: "part1")
        let index = try Index(at: nil)
        _ = try Indexer.scan(sandbox.library, into: index)

        let again = try Indexer.scan(sandbox.library, into: index)
        #expect(again.read == 0)
        #expect(again.unchanged == 3)
        #expect(try index.count() == (containers: 3, presentations: 1))

        // A placement changes one sidecar; only it is read on the next scan.
        try sandbox.place([Self.series, Self.season, Self.serial], item: "part2")
        let after = try Indexer.scan(sandbox.library, into: index)
        #expect(after.read == 1)
        #expect(after.unchanged == 2)
        #expect(try index.presentations(of: Self.serial.id, in: "main").map(\.item) == ["part1", "part2"])

        // Or the placement tells the index directly.
        try sandbox.place([Self.series, Self.season, Self.serial], item: "now-and-then")
        let refreshed = try Indexer.refresh(
            folder: "Doctor Who (1963)/01 - Season 13/01 - Pyramids of Mars",
            parent: Self.season.id,
            in: sandbox.library,
            index: index
        )
        #expect(refreshed.read == 1)
        #expect(try index.presentations(of: Self.serial.id, in: "main").count == 3)

        // A container that disappears is forgotten, and an abandoned sidecar is reported.
        let seasonFolder = sandbox.library.root.appendingPathComponent("Doctor Who (1963)/01 - Season 13")
        try FileManager.default.removeItem(at: seasonFolder.appendingPathComponent("container.smd"))
        let gone = try Indexer.scan(sandbox.library, into: index)
        #expect(gone.removed == 2)
        #expect(
            gone.findings.map(\.description) == [
                "error: Doctor Who (1963)/container.smd: child 0000000000000002 is at \"01 - Season 13/container.smd\", which does not exist",
                "warning: Doctor Who (1963)/01 - Season 13/01 - Pyramids of Mars/container.smd: a sidecar nothing references",
            ]
        )
        #expect(try index.count() == (containers: 1, presentations: 0))
    }

    /// One container filed in two libraries is held twice, each as its own library's sidecar says, and
    /// removing one library's sidecar leaves the other's container and presentations.
    @Test func aContainerInTwoLibrariesIsHeldForEach() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let other = LibraryConfig(id: "4k", root: sandbox.root.appendingPathComponent("4K"))
        try sandbox.place([Self.series, Self.season, Self.serial], item: "part1")
        try sandbox.place([Self.unlisted], item: "ep1")
        try sandbox.place([Self.unlisted], item: "ep1", profile: "hdr", into: other)
        let index = try Index(at: nil)
        _ = try Indexer.scan(sandbox.library, into: index)
        _ = try Indexer.scan(other, into: index)

        #expect(try index.containers(Self.unlisted.id).map(\.library).sorted() == ["4k", "main"])
        #expect(try index.presentations(of: Self.unlisted.id, in: "main").map(\.file) == ["Pyramids of Mars.mkv"])
        #expect(try index.presentations(of: Self.unlisted.id, in: "4k").map(\.file) == ["Pyramids of Mars - hdr.mkv"])
        #expect(try index.search("behind").count == 1, "a hit names the container, once")

        try FileManager.default.removeItem(at: sandbox.library.root.appendingPathComponent("Behind the Sofa"))
        #expect(try Indexer.scan(sandbox.library, into: index).removed == 1)
        #expect(try Indexer.scan(other, into: index).unchanged == 1)
        #expect(try index.containers(Self.unlisted.id).map(\.library) == ["4k"])
        #expect(try index.presentations(of: Self.unlisted.id, in: "4k").map(\.file) == ["Pyramids of Mars - hdr.mkv"])
    }

    /// A library holds a container once: a second sidecar for it is reported and not indexed, and the
    /// first is kept whichever of them the index held before.
    @Test func aContainerFiledTwiceInALibraryIsReportedOnce() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        var film = Container(
            id: ContainerID("0000000000000005")!,
            type: .movie,
            title: Title("Alien")!,
            year: 1979,
            yearInTitle: true
        )
        film.sequences = [
            Sequence(id: "main", items: [.leaf(Entry.Leaf(id: ItemID("feature")!, type: .movie, title: "Alien"))])
        ]
        func file(_ folder: String) throws {
            let url = sandbox.library.root.appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try SidecarFile.data(for: Sidecar(container: film)).write(to: url.appendingPathComponent("container.smd"))
        }
        try file("Alien (1979)")
        let index = try Index(at: nil)
        #expect(try Indexer.scan(sandbox.library, into: index).read == 1)

        try file("Alien")
        let report = try Indexer.scan(sandbox.library, into: index)
        #expect(
            report.findings.map(\.description) == [
                "warning: Alien/container.smd: folder \"Alien\" is not the name the layout would give it, \"Alien (1979)\"",
                "error: Alien (1979)/container.smd: container 0000000000000005 is already at \"Alien\"",
            ]
        )
        #expect(try index.containers(film.id).map(\.folder) == ["Alien"])
        #expect(
            LibraryWalker.walk(sandbox.library.root).findings.map(\.description) == report.findings.map(\.description),
            "the walker says the same"
        )
        #expect(
            try Indexer.scan(sandbox.library, into: index).findings == report.findings,
            "and so does every walk after"
        )
        #expect(
            try Indexer.refresh(folder: "Alien (1979)", parent: nil, in: sandbox.library, index: index).findings
                == report.findings.filter { $0.severity == .error },
            "and a refresh"
        )
        #expect(try index.containers(film.id).map(\.folder) == ["Alien"])

        try FileManager.default.removeItem(at: sandbox.library.root.appendingPathComponent("Alien"))
        let after = try Indexer.scan(sandbox.library, into: index)
        #expect(after.findings.isEmpty)
        #expect(try index.containers(film.id).map(\.folder) == ["Alien (1979)"], "the one left is read again")
    }

    /// A folder is named when it is made: a sidecar whose display title has changed since leaves it
    /// where it is, and every walk warns that it is not the name the layout would give it now.
    @Test func aFolderNotNamedAsTheLayoutWouldNameItIsAWarning() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        var film = Container(
            id: ContainerID("0000000000000005")!,
            type: .movie,
            title: Title("Alien")!,
            year: 1997,
            yearInTitle: true
        )
        film.sequences = [
            Sequence(id: "main", items: [.leaf(Entry.Leaf(id: ItemID("feature")!, type: .movie, title: "Alien"))])
        ]
        try sandbox.place([film], item: "feature")
        let index = try Index(at: nil)
        #expect(try Indexer.scan(sandbox.library, into: index).findings.isEmpty)

        let sidecar = sandbox.library.root.appendingPathComponent("Alien (1997)/container.smd")
        film.year = 1979
        try SidecarFile.data(settingContainer: film, in: try Data(contentsOf: sidecar)).write(to: sidecar)
        let warning =
            "warning: Alien (1997)/container.smd: folder \"Alien (1997)\" is not the name the layout would give it, \"Alien (1979)\""
        #expect(try Indexer.scan(sandbox.library, into: index).findings.map(\.description) == [warning])
        #expect(
            try Indexer.scan(sandbox.library, into: index).findings.map(\.description) == [warning],
            "an unchanged sidecar too"
        )
        #expect(LibraryWalker.walk(sandbox.library.root).findings.map(\.description) == [warning])
        #expect(try index.containers(film.id).map(\.folder) == ["Alien (1997)"], "the folder is where it was")

        // A child's folder is named for its position too: a season renamed by hand without it.
        try sandbox.place([Self.series, Self.season, Self.serial], item: "part1")
        let series = sandbox.library.root.appendingPathComponent("Doctor Who (1963)")
        try FileManager.default.moveItem(
            at: series.appendingPathComponent("01 - Season 13"),
            to: series.appendingPathComponent("Season 13")
        )
        let seriesURL = series.appendingPathComponent("container.smd")
        let existing = try Data(contentsOf: seriesURL)
        var held = try SidecarFile.sidecar(from: existing)
        held.children[Self.season.id] = "Season 13/container.smd"
        try SidecarFile.data(for: held, updating: existing).write(to: seriesURL)
        let season =
            "warning: Doctor Who (1963)/Season 13/container.smd: folder \"Season 13\" is not the name the layout would give it, \"01 - Season 13\""
        #expect(try Indexer.scan(sandbox.library, into: index).findings.map(\.description) == [warning, season])
        #expect(try Indexer.scan(sandbox.library, into: index).findings.map(\.description) == [warning, season])
        #expect(try index.container(Self.season.id, in: "main")?.folder == "Doctor Who (1963)/Season 13")
    }

    /// A presentation's id is what it is, so a folder renamed by hand keeps it; and what would share an
    /// id or a file with another presentation of its sidecar is reported, not indexed.
    @Test func aPresentationIsNamedForWhatItIs() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        var film = Container(
            id: ContainerID("0000000000000005")!,
            type: .movie,
            title: Title("Alien")!,
            year: 1979,
            yearInTitle: true
        )
        film.sequences = [
            Sequence(id: "main", items: [.leaf(Entry.Leaf(id: ItemID("feature")!, type: .movie, title: "Alien"))])
        ]
        try sandbox.place([film], item: "feature")
        try sandbox.place([film], item: "feature", profile: "mobile")
        try sandbox.place([Self.series, Self.season, Self.serial], item: "part1")
        let index = try Index(at: nil)
        _ = try Indexer.scan(sandbox.library, into: index)
        let before = try index.presentations(of: film.id, in: "main")
        #expect(before.count == 2)

        let library = sandbox.library.root
        try FileManager.default.moveItem(
            at: library.appendingPathComponent("Alien (1979)"),
            to: library.appendingPathComponent("Alien")
        )
        _ = try Indexer.scan(sandbox.library, into: index)
        let after = try index.presentations(of: film.id, in: "main")
        #expect(after.map(\.id) == before.map(\.id), "the ids it had")
        #expect(after.map(\.path).sorted() == ["Alien/Alien - mobile.mkv", "Alien/Alien.mkv"])

        let url = library.appendingPathComponent("Alien/container.smd")
        var sidecar = try SidecarFile.sidecar(from: Data(contentsOf: url))
        sidecar.presentations["feature"] = [
            Presentation(file: "Alien.mkv"), Presentation(file: "Alien (again).mkv"),
        ]
        try SidecarFile.data(for: sidecar).write(to: url)
        var report = try Indexer.scan(sandbox.library, into: index)
        #expect(
            report.findings.filter { $0.severity == .error }.map(\.description) == [
                "error: Alien/container.smd: item feature has two presentations for the same alternative and profile"
            ]
        )
        #expect(try index.presentations(of: film.id, in: "main").map(\.file) == ["Alien.mkv"], "the first")
        #expect(try index.presentations(of: Self.serial.id, in: "main").count == 1, "and the rest of the library")

        sidecar.presentations["feature"] = [
            Presentation(file: "Alien.mkv"), Presentation(profile: "mobile", file: "Alien.mkv"),
        ]
        try SidecarFile.data(for: sidecar).write(to: url)
        report = try Indexer.scan(sandbox.library, into: index)
        #expect(
            report.findings.filter { $0.severity == .error }.map(\.description) == [
                "error: Alien/container.smd: item feature: \"Alien.mkv\" is named by another presentation"
            ]
        )
        #expect(try index.presentations(of: film.id, in: "main").map(\.profile) == [nil])
        #expect(try index.presentations(of: Self.serial.id, in: "main").count == 1)
    }

    /// A kind of artwork held in both formats is a warning on the sidecar, and the `.jpg` is the one
    /// that counts.
    @Test func artworkInTwoFormatsIsAWarning() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        try sandbox.place([Self.unlisted], item: "ep1")
        let folder = sandbox.library.root.appendingPathComponent("Behind the Sofa")
        try Data([0xFF, 0xD8, 0xFF]).write(to: folder.appendingPathComponent("poster.jpg"))
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: folder.appendingPathComponent("fanart.png"))
        let index = try Index(at: nil)
        #expect(try Indexer.scan(sandbox.library, into: index).findings.isEmpty)
        #expect(Artwork.held(in: folder) == ["poster", "fanart"])

        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: folder.appendingPathComponent("poster.png"))
        let warning = "warning: Behind the Sofa/container.smd: poster is both poster.jpg and poster.png"
        #expect(try Indexer.scan(sandbox.library, into: index).findings.map(\.description) == [warning])
        #expect(LibraryWalker.walk(sandbox.library.root).findings.map(\.description) == [warning])
        #expect(Artwork.file(of: "poster", in: folder)?.format == .jpg, "the .jpg counts")
    }

    /// An attributed kind of artwork the folder holds no file for is a warning, whether the walk reads
    /// the sidecar or finds it unchanged.
    @Test func anAttributedKindWithNoFileIsAWarning() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        try sandbox.place([Self.unlisted], item: "ep1")
        let folder = sandbox.library.root.appendingPathComponent("Behind the Sofa")
        let url = folder.appendingPathComponent("container.smd")
        let poster = Attribution(subject: .artwork("poster"), provider: .tmdb, value: "348")
        try SidecarFile.data(settingAttributions: [poster], in: Data(contentsOf: url)).write(to: url)

        let index = try Index(at: nil)
        let warning =
            "warning: Behind the Sofa/container.smd: artwork poster is attributed to tmdb but the folder has none"
        #expect(try Indexer.scan(sandbox.library, into: index).findings.map(\.description) == [warning])
        #expect(try Indexer.scan(sandbox.library, into: index).findings.map(\.description) == [warning], "unchanged")
        #expect(LibraryWalker.walk(sandbox.library.root).findings.map(\.description) == [warning])

        try Data([0xFF, 0xD8, 0xFF]).write(to: folder.appendingPathComponent("poster.jpg"))
        #expect(try Indexer.scan(sandbox.library, into: index).findings.isEmpty)
        #expect(LibraryWalker.walk(sandbox.library.root).findings.isEmpty)
    }

    /// An unmounted mount point is an empty folder, not a missing one: a walk of it would forget
    /// the whole library, so it is not applied, and neither is a walk of a folder that has gone.
    @Test func anEmptyMountPointForgetsNothing() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        try sandbox.place([Self.series, Self.season, Self.serial], item: "part1")
        let index = try Index(at: nil)
        _ = try Indexer.scan(sandbox.library, into: index)

        let aside = sandbox.root.appendingPathComponent("Library (unmounted)")
        try FileManager.default.moveItem(at: sandbox.library.root, to: aside)
        try FileManager.default.createDirectory(at: sandbox.library.root, withIntermediateDirectories: true)
        #expect(throws: LibraryUnavailable.empty) { try Indexer.scan(sandbox.library, into: index) }
        #expect(try index.count() == (containers: 3, presentations: 1))

        try FileManager.default.removeItem(at: sandbox.library.root)
        #expect(throws: LibraryUnavailable.missing) { try Indexer.scan(sandbox.library, into: index) }
        #expect(try index.count() == (containers: 3, presentations: 1))

        // A library the index holds nothing for may well be empty: that walk is applied.
        try FileManager.default.createDirectory(at: sandbox.library.root, withIntermediateDirectories: true)
        #expect(try Indexer.scan(LibraryConfig(id: "new", root: sandbox.library.root), into: index).read == 0)
    }

    @Test func theIndexIsAFileThatCanBeThrownAway() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        try sandbox.place([Self.unlisted], item: "ep1")
        let file = sandbox.root.appendingPathComponent("index.sqlite")
        do {
            let index = try Index(at: file)
            _ = try Indexer.scan(sandbox.library, into: index)
        }
        let reopened = try Index(at: file)
        #expect(try reopened.count() == (containers: 1, presentations: 1))
        try FileManager.default.removeItem(at: file)
        let rebuilt = try Index(at: file)
        #expect(try rebuilt.count() == (containers: 0, presentations: 0))
        #expect(try Indexer.scan(sandbox.library, into: rebuilt).read == 1)
    }

    /// A file an earlier version of the index made — here one whose items are not keyed by library,
    /// its migration recorded as done — is emptied on opening and filled by the next scan, rather
    /// than refusing every write.
    @Test func anIndexAnotherVersionMadeIsRebuilt() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        try sandbox.place([Self.unlisted], item: "ep1")
        let file = sandbox.root.appendingPathComponent("index.sqlite")
        do {
            let earlier = try DatabaseQueue(path: file.path)
            try earlier.write { db in
                try db.execute(sql: "CREATE TABLE item (container TEXT NOT NULL, id TEXT NOT NULL)")
                try db.execute(sql: "CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY)")
                try db.execute(sql: "INSERT INTO grdb_migrations VALUES ('v1')")
            }
        }
        let index = try Index(at: file)
        #expect(try index.count() == (containers: 0, presentations: 0))
        #expect(try Indexer.scan(sandbox.library, into: index).read == 1)
        #expect(try index.items(of: Self.unlisted.id, in: "main").map(\.id) == ["ep1"])
        #expect(try Index(at: file).count() == (containers: 1, presentations: 1), "this version's file is kept")
    }
}
