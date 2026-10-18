// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloLibrary
import SiloStore
import SmdKit
import SmdSidecar
import Synchronization
import Testing
@testable import SiloApp
@testable import silo

/// Keeping the index current, on `Libraries` alone over a temporary folder and an in-memory index:
/// what the boot does with a folder that is missing, what a request reaching for one that has come
/// back does, the tick, walks joining, and a placement re-reading only what it wrote.
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
            libraries = Libraries(config: config, index: index, checks: CheckSignal())
        }

        static func place(_ film: Container, into library: URL, from root: URL) throws {
            let source = root.appendingPathComponent("\(UUID().uuidString).mkv")
            try Data("video".utf8).write(to: source)
            try Placer.apply(try Placer.compute(PlacementRequest(library: library, lineage: [film], item: "feature", presentation: Presentation(file: ""), source: source)))
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    @Test func aDriveLateToMountIsUnavailableAndTheRestAreServed() async throws {
        let bench = try Bench()
        defer { bench.remove() }
        try bench.libraries.walkAtBoot()
        #expect(bench.libraries.isAvailable("main"))
        #expect(!bench.libraries.isAvailable("films"), "missing at boot, and the boot went on")
        #expect(try bench.index.roots(in: "main").map(\.id) == [Fixture.thirdMan.id.value])

        // The drive mounts; the next request that reaches for the library walks it.
        try FileManager.default.createDirectory(at: bench.late.root, withIntermediateDirectories: true)
        try Bench.place(Fixture.brief, into: bench.late.root, from: bench.root)
        #expect(try await bench.libraries.reach(bench.late))
        #expect(bench.libraries.isAvailable("films"))
        #expect(try bench.index.roots(in: "films").map(\.id) == [Fixture.brief.id.value])
    }

    @Test func aFolderThatGoesIsUnavailableAndItsIndexKept() async throws {
        let bench = try Bench()
        defer { bench.remove() }
        try bench.libraries.walkAtBoot()
        let aside = bench.root.appendingPathComponent("Library (unplugged)")
        try FileManager.default.moveItem(at: bench.present.root, to: aside)
        #expect(!bench.libraries.availability(of: bench.present))
        #expect(try await bench.libraries.walk(bench.present).available == false, "a walk of a missing folder is not applied")
        #expect(try bench.index.roots(in: "main").count == 1, "and forgets nothing")

        // An empty mount point is a folder, not a missing one: it is unavailable all the same.
        try FileManager.default.createDirectory(at: bench.present.root, withIntermediateDirectories: true)
        #expect(!(try await bench.libraries.reach(bench.present)))
        #expect(try bench.index.roots(in: "main").count == 1)

        try FileManager.default.removeItem(at: bench.present.root)
        try FileManager.default.moveItem(at: aside, to: bench.present.root)
        #expect(try await bench.libraries.reach(bench.present))
    }

    @Test func aChangeBehindTheServersBackIsReadAtTheNextTick() async throws {
        let bench = try Bench()
        defer { bench.remove() }
        try bench.libraries.walkAtBoot()
        // silo-ctl place, say: a second film filed with nobody telling the server.
        try Bench.place(Fixture.brief, into: bench.present.root, from: bench.root)
        #expect(try bench.index.roots(in: "main").count == 1)

        let tick = LibraryTick(libraries: bench.libraries, interval: .milliseconds(20))
        let following = Task { await tick.follow() }
        defer { following.cancel() }
        let deadline = ContinuousClock.now + .seconds(10)
        while try bench.index.roots(in: "main").count < 2, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(try bench.index.roots(in: "main").map(\.id).sorted() == [Fixture.thirdMan.id.value, Fixture.brief.id.value], "read with nobody asking")
    }

    /// Walks of one library never overlap: one asked for while another runs joins it and shares its
    /// report; a re-read waits for the walk, and a walk asked for during a re-read waits for that.
    @Test func walksAskedForTogetherWalkOnce() async throws {
        let lane = LibraryLane()
        let walks = Atomic<Int>(0)
        let order = Mutex<[String]>([])
        let walk: @Sendable () throws -> LastWalk = {
            let count = walks.add(1, ordering: .relaxed).newValue
            Thread.sleep(forTimeInterval: 0.2)
            order.withLock { $0.append("walk \(count)") }
            var report = ScanReport()
            report.read = count
            return LastWalk(walkedAt: .now, available: true, report: report)
        }
        async let first = lane.walk(walk)
        try await Task.sleep(for: .milliseconds(50))
        async let second = lane.walk(walk)
        async let reread: Void = lane.exclusively { order.withLock { $0.append("re-read") } }
        let (one, two, _) = try await (first, second, reread)
        #expect(walks.load(ordering: .relaxed) == 1, "the second joined the first")
        #expect(one == two)
        #expect(order.withLock { $0 } == ["walk 1", "re-read"], "the re-read waited for the walk")

        // Over, a walk is new; asked for during a re-read, it waits for it.
        async let holding: Void = lane.exclusively {
            Thread.sleep(forTimeInterval: 0.2)
            order.withLock { $0.append("re-read") }
        }
        try await Task.sleep(for: .milliseconds(50))
        let third = try await lane.walk(walk)
        try await holding
        #expect(third.report.read == 2)
        #expect(order.withLock { $0 } == ["walk 1", "re-read", "re-read", "walk 2"])
    }

    @Test func aFirstPlacementIndexesEveryContainerItMadeUnderItsParent() async throws {
        let bench = try Bench()
        defer { bench.remove() }
        try FileManager.default.createDirectory(at: bench.late.root, withIntermediateDirectories: true)
        try bench.libraries.walkAtBoot()
        let placement = try Self.placement(into: bench.late.root, from: bench.root)
        try Placer.apply(placement)
        try await bench.libraries.reread(placement.sidecars, in: bench.late)

        #expect(try bench.index.roots(in: "films").map(\.id) == [Self.series.id.value])
        #expect(try bench.index.children(of: Self.series.id).map(\.id) == [Self.season.id.value], "the season under the series")
        #expect(try bench.index.children(of: Self.season.id).map(\.id) == [Self.serial.id.value], "and the serial under the season")
        #expect(try bench.index.presentations(of: Self.serial.id).map(\.item) == ["part1"])
    }

    @Test func aPlacementWalksNothing() async throws {
        let bench = try Bench()
        defer { bench.remove() }
        try bench.libraries.walkAtBoot()
        try Bench.place(Fixture.brief, into: bench.present.root, from: bench.root)
        let placement = try Self.placement(into: bench.present.root, from: bench.root)
        try Placer.apply(placement)
        try await bench.libraries.reread(placement.sidecars, in: bench.present)

        #expect(try bench.index.presentations(of: Self.serial.id).count == 1, "the placed presentation is indexed at once")
        #expect(try bench.index.container(Fixture.brief.id) == nil, "and the change behind the server's back is not")
        try await bench.libraries.walk(bench.present)
        #expect(try bench.index.container(Fixture.brief.id) != nil, "until the library's next walk")
    }

    @Test func theLastWalkIsKeptWithItsFindings() async throws {
        let bench = try Bench()
        defer { bench.remove() }
        try bench.libraries.walkAtBoot()
        #expect(bench.libraries.lastWalk(of: "main")?.report.read == 1)
        #expect(bench.libraries.lastWalk(of: "films")?.available == false)
        #expect(bench.libraries.lastWalk(of: "films")?.report.findings.map(\.description) == ["error: not applied: its folder does not exist"])

        let stray = bench.present.root.appendingPathComponent("The Third Man (1949)/Stray")
        try FileManager.default.createDirectory(at: stray, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: stray.deletingLastPathComponent().appendingPathComponent("container.smd"), to: stray.appendingPathComponent("container.smd"))
        let walk = try await bench.libraries.walk(bench.present)
        #expect(walk == bench.libraries.lastWalk(of: "main"))
        #expect(walk.report.findings.map(\.description) == ["warning: The Third Man (1949)/Stray/container.smd: a sidecar nothing references"])
    }

    static let series: Container = {
        var series = Container(id: ContainerID("0000000000000021")!, type: .series, title: Title("Doctor Who")!, year: 1963, yearInTitle: true)
        series.sequences = [Sequence(id: "seasons", items: [.child(Entry.Child(id: ItemID("s13")!, container: season.id))])]
        return series
    }()
    static let season: Container = {
        var season = Container(id: ContainerID("0000000000000022")!, type: .season, title: Title("Season 13")!)
        season.sequences = [Sequence(id: "stories", items: [.child(Entry.Child(id: ItemID("pyramids")!, container: serial.id))])]
        return season
    }()
    static let serial: Container = {
        var serial = Container(id: ContainerID("0000000000000023")!, type: .serial, title: Title("Pyramids of Mars")!)
        serial.sequences = [Sequence(id: "parts", items: [.leaf(Entry.Leaf(id: ItemID("part1")!, type: .episode, title: "Part One"))])]
        return serial
    }()

    /// A first placement of a serial in a season of a series: three folders, three sidecars.
    static func placement(into library: URL, from root: URL) throws -> Placement {
        let source = root.appendingPathComponent("\(UUID().uuidString).mkv")
        try Data("video".utf8).write(to: source)
        return try Placer.compute(PlacementRequest(library: library, lineage: [series, season, serial], item: "part1", presentation: Presentation(file: ""), source: source))
    }
}
