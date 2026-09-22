// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloLibrary
import SmdKit
import SmdSidecar
import Testing
@testable import SiloStore

struct IndexTests {
    static let series: Container = {
        var series = Container(id: ContainerID("0000000000000001")!, type: .series, title: "Doctor Who", year: 1963, yearInTitle: true, externalRefs: [ExternalRef(provider: .tvdb, value: "76107")])
        series.sequences = [Sequence(id: "seasons", items: [Entry(id: "s13", type: .container, container: season.id)])]
        return series
    }()
    static let season: Container = {
        var season = Container(id: ContainerID("0000000000000002")!, type: .season, title: "Season 13")
        season.sequences = [Sequence(id: "stories", items: [Entry(id: "pyramids", type: .container, container: serial.id)])]
        return season
    }()
    static let serial: Container = {
        var serial = Container(id: ContainerID("0000000000000003")!, type: .serial, typeLabel: "Story", title: "Pyramids of Mars")
        serial.alternatives = [Alternative(id: "broadcast", sequence: "parts", title: "Broadcast version")]
        serial.defaultAlternative = "broadcast"
        serial.sequences = [Sequence(id: "parts", items: [
            Entry(id: "part1", type: .episode, title: "Part One", externalRefs: [ExternalRef(provider: .tvdb, value: "1")]),
            Entry(id: "part2", type: .episode, title: "Part Two"),
        ])]
        serial.extras = [Entry(id: "now-and-then", type: .featurette, title: "Now and Then")]
        return serial
    }()
    static let unlisted: Container = {
        var behind = Container(id: ContainerID("0000000000000004")!, type: .series, title: "Behind the Sofa", listed: false)
        behind.sequences = [Sequence(id: "all", items: [Entry(id: "ep1", type: .episode, title: "Pyramids of Mars")])]
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
        func place(_ lineage: [Container], item: String, profile: String? = nil) throws {
            let source = root.appendingPathComponent("\(UUID().uuidString).mkv")
            try Data("video".utf8).write(to: source)
            try Placer.apply(try Placer.compute(PlacementRequest(library: library.root, lineage: lineage, item: item, presentation: Presentation(profile: profile, file: ""), source: source)))
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
        let serial = try #require(try index.container(Self.serial.id))
        #expect(serial.parent == Self.season.id.rawValue)
        #expect(serial.folder == "Doctor Who (1963)/Season 13/Pyramids of Mars")
        #expect(serial.typeLabel == "Story")
        #expect(try index.sidecar(Self.serial.id)?.container == Self.serial)
        #expect(try index.children(of: Self.series.id).map(\.id) == [Self.season.id.rawValue])
        #expect(try index.items(of: Self.serial.id).map(\.id) == ["part1", "part2", "now-and-then"])
        #expect(try index.items(of: Self.serial.id).map(\.isExtra) == [false, false, true])

        let presentations = try index.presentations(of: Self.serial.id)
        #expect(presentations.map(\.path) == [
            "Doctor Who (1963)/Season 13/Pyramids of Mars/extras/Now and Then.mkv",
            "Doctor Who (1963)/Season 13/Pyramids of Mars/Part One.mkv",
            "Doctor Who (1963)/Season 13/Pyramids of Mars/Part One - mobile.mkv",
        ])
        let mobile = try #require(presentations.first { $0.profile == "mobile" })
        #expect(try index.presentation(mobile.id) == mobile)
        #expect(mobile.id == IndexedPresentation.id(library: "main", path: mobile.path))

        #expect(try index.lookup(provider: .tvdb, value: "76107").map(\.id) == [Self.series.id.rawValue])
        #expect(try index.lookup(provider: .tvdb, value: "1").map(\.id) == [Self.serial.id.rawValue], "an item's reference names its container")
        #expect(try index.search("pyramids").map { "\($0.container)/\($0.item ?? "-")" } == ["0000000000000003/-", "0000000000000004/ep1"])
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
        #expect(try index.presentations(of: Self.serial.id).map(\.item) == ["part1", "part2"])

        // Or the placement tells the index directly.
        try sandbox.place([Self.series, Self.season, Self.serial], item: "now-and-then")
        let refreshed = try Indexer.refresh(folder: "Doctor Who (1963)/Season 13/Pyramids of Mars", parent: Self.season.id, in: sandbox.library, index: index)
        #expect(refreshed.read == 1)
        #expect(try index.presentations(of: Self.serial.id).count == 3)

        // A container that disappears is forgotten, and an abandoned sidecar is reported.
        let seasonFolder = sandbox.library.root.appendingPathComponent("Doctor Who (1963)/Season 13")
        try FileManager.default.removeItem(at: seasonFolder.appendingPathComponent("container.smd"))
        let gone = try Indexer.scan(sandbox.library, into: index)
        #expect(gone.removed == 2)
        #expect(gone.findings.map(\.description) == [
            "error: Doctor Who (1963)/container.smd: child 0000000000000002 is at \"Season 13/container.smd\", which does not exist",
            "warning: Doctor Who (1963)/Season 13/Pyramids of Mars/container.smd: a sidecar nothing references",
        ])
        #expect(try index.count() == (containers: 1, presentations: 0))
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
}
