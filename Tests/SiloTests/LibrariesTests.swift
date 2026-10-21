// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloKit
import SiloLibrary
import SmdKit
import SmdSidecar
import Synchronization
import Testing

@testable import SiloApp
@testable import SiloStore
@testable import silo

/// Keeping the index current, on `Libraries` alone over a temporary folder and an in-memory index:
/// what the boot does with a folder that is missing, what a request reaching for one that has come
/// back does, the tick, walks joining, and a placement re-reading only what it wrote.
struct LibrariesTests {
    struct Bench {
        let root: URL
        let present: LibraryConfig
        let late: LibraryConfig
        let settings: SettingsStore
        let index: Index
        let libraries: Libraries

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("silo-libraries-\(UUID().uuidString)")
            present = LibraryConfig(id: "main", root: root.appendingPathComponent("Library"))
            late = LibraryConfig(id: "films", root: root.appendingPathComponent("Films"))
            try FileManager.default.createDirectory(at: present.root, withIntermediateDirectories: true)
            try Self.place(Fixture.thirdMan, into: present.root, from: root)
            let config = SiloConfig(
                silo: SiloFile(serverID: "s1", host: "127.0.0.1", port: 0, libraryRoots: [root.path]),
                stateDirectory: root.appendingPathComponent("State")
            )
            settings = SettingsStore(Settings(name: "Silo on test", libraries: [present, late]))
            index = try Index(at: nil)
            libraries = Libraries(config: config, settings: settings, index: index, checks: CheckSignal())
        }

        static func place(_ film: Container, into library: URL, from root: URL) throws {
            let source = root.appendingPathComponent("\(UUID().uuidString).mkv")
            try Data("video".utf8).write(to: source)
            try Placer.apply(
                try Placer.compute(
                    PlacementRequest(
                        library: library,
                        lineage: [film],
                        item: "feature",
                        presentation: Presentation(file: ""),
                        source: source
                    )
                )
            )
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
        #expect(
            try await bench.libraries.walk(bench.present).available == false,
            "a walk of a missing folder is not applied"
        )
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
        #expect(
            try bench.index.roots(in: "main").map(\.id).sorted() == [
                Fixture.thirdMan.id.value, Fixture.brief.id.value,
            ],
            "read with nobody asking"
        )
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

    /// Blocks on a semaphore, off the async context that may not wait on one itself.
    private static func wait(for semaphore: DispatchSemaphore) { semaphore.wait() }

    /// Folders moved under the library's lock are walked in the same turn: a refresh asked for while
    /// they move, as the media route asks when a file is not where the index said, waits for the turn
    /// and finds the container where it went, with the ids it had, rather than forgetting it.
    @Test func aRefreshAskedForWhileFoldersMoveFindsWhereTheyWent() async throws {
        let bench = try Bench()
        defer { bench.remove() }
        let library = bench.present
        try FileManager.default.moveItem(
            at: library.root.appendingPathComponent("The Third Man (1949)"),
            to: library.root.appendingPathComponent("Third Man")
        )
        try bench.libraries.walkAtBoot()
        let before = try bench.index.presentations(of: Fixture.thirdMan.id, in: library.id)
        #expect(before.map(\.path) == ["Third Man/The Third Man.mkv"])

        let moved = DispatchSemaphore(value: 0)
        let go = DispatchSemaphore(value: 0)
        async let layout = bench.libraries.exclusively(
            library,
            walkingAfter: { !$0.moves.isEmpty },
            doing: {
                let outcome = Relayout.layOut(LibraryWalker.walk(library.root), dryRun: false)
                moved.signal()
                Self.wait(for: go)
                return outcome
            }
        )
        await Task.detached { Self.wait(for: moved) }.value
        #expect(
            try bench.index.container(Fixture.thirdMan.id, in: library.id)?.folder == "Third Man",
            "the index has not yet been told"
        )
        async let refresh: Void = bench.libraries.refresh(Fixture.thirdMan.id, in: library)
        try await Task.sleep(for: .milliseconds(100))
        go.signal()
        let (outcome, _) = try await (layout, refresh)

        #expect(outcome.moves == [FolderMove(from: "Third Man", to: "The Third Man (1949)")])
        #expect(try bench.index.container(Fixture.thirdMan.id, in: library.id)?.folder == "The Third Man (1949)")
        let after = try bench.index.presentations(of: Fixture.thirdMan.id, in: library.id)
        #expect(after.map(\.path) == ["The Third Man (1949)/The Third Man.mkv"])
        #expect(after.map(\.id) == before.map(\.id))
        #expect(bench.libraries.lastWalk(of: library.id)?.available == true, "the turn's walk is the last walk")
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
        #expect(
            try bench.index.children(of: Self.series.id, in: "films").map(\.id) == [Self.season.id.value],
            "the season under the series"
        )
        #expect(
            try bench.index.children(of: Self.season.id, in: "films").map(\.id) == [Self.serial.id.value],
            "and the serial under the season"
        )
        #expect(try bench.index.presentations(of: Self.serial.id, in: "films").map(\.item) == ["part1"])
    }

    @Test func aPlacementWalksNothing() async throws {
        let bench = try Bench()
        defer { bench.remove() }
        try bench.libraries.walkAtBoot()
        try Bench.place(Fixture.brief, into: bench.present.root, from: bench.root)
        let placement = try Self.placement(into: bench.present.root, from: bench.root)
        try Placer.apply(placement)
        try await bench.libraries.reread(placement.sidecars, in: bench.present)

        #expect(
            try bench.index.presentations(of: Self.serial.id, in: "main").count == 1,
            "the placed presentation is indexed at once"
        )
        #expect(
            try bench.index.container(Fixture.brief.id, in: "main") == nil,
            "and the change behind the server's back is not"
        )
        try await bench.libraries.walk(bench.present)
        #expect(try bench.index.container(Fixture.brief.id, in: "main") != nil, "until the library's next walk")
    }

    @Test func theLastWalkIsKeptWithItsFindings() async throws {
        let bench = try Bench()
        defer { bench.remove() }
        try bench.libraries.walkAtBoot()
        #expect(bench.libraries.lastWalk(of: "main")?.report.read == 1)
        #expect(bench.libraries.lastWalk(of: "films")?.available == false)
        #expect(
            bench.libraries.lastWalk(of: "films")?.report.findings.map(\.description) == [
                "error: not applied: its folder does not exist"
            ]
        )

        let stray = bench.present.root.appendingPathComponent("The Third Man (1949)/Stray")
        try FileManager.default.createDirectory(at: stray, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: stray.deletingLastPathComponent().appendingPathComponent("container.smd"),
            to: stray.appendingPathComponent("container.smd")
        )
        let walk = try await bench.libraries.walk(bench.present)
        #expect(walk == bench.libraries.lastWalk(of: "main"))
        #expect(
            walk.report.findings.map(\.description) == [
                "warning: The Third Man (1949)/Stray/container.smd: a sidecar nothing references"
            ]
        )
    }

    static let series: Container = {
        var series = Container(
            id: ContainerID("0000000000000021")!,
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
        var season = Container(id: ContainerID("0000000000000022")!, type: .season, title: Title("Season 13")!)
        season.sequences = [
            Sequence(id: "stories", items: [.child(Entry.Child(id: ItemID("pyramids")!, container: serial.id))])
        ]
        return season
    }()
    static let serial: Container = {
        var serial = Container(id: ContainerID("0000000000000023")!, type: .serial, title: Title("Pyramids of Mars")!)
        serial.sequences = [
            Sequence(id: "parts", items: [.leaf(Entry.Leaf(id: ItemID("part1")!, type: .episode, title: "Part One"))])
        ]
        return serial
    }()

    /// A first placement of a serial in a season of a series: three folders, three sidecars.
    static func placement(into library: URL, from root: URL) throws -> Placement {
        let source = root.appendingPathComponent("\(UUID().uuidString).mkv")
        try Data("video".utf8).write(to: source)
        return try Placer.compute(
            PlacementRequest(
                library: library,
                lineage: [series, season, serial],
                item: "part1",
                presentation: Presentation(file: ""),
                source: source
            )
        )
    }

    @Test func withTheRootsEmptiedNothingIsAddedOverTheNetwork() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("silo-roots-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("films"),
            withIntermediateDirectories: true
        )
        let settings = SettingsStore(Settings(name: "Silo on test"))
        let libraries = Libraries(
            config: SiloConfig(host: "127.0.0.1", port: 0, stateDirectory: root, libraryRoots: []),
            settings: settings,
            index: try Index(at: nil),
            checks: CheckSignal()
        )
        await #expect(throws: OutsideTheRoots.self) {
            try await libraries.add(id: "films", path: root.appendingPathComponent("films").path)
        }
        #expect(settings.current.libraries.isEmpty)
    }

    /// A path checked before it is added: each folder along it and whether it is there, and the
    /// refusal the addition would meet; then its missing folders made within a root, and never a root.
    @Test func aPathIsCheckedAndItsMissingFoldersMadeWithinARoot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("silo-paths-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let media = root.appendingPathComponent("Media")
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        try Data("not a folder".utf8).write(to: media.appendingPathComponent("notes.txt"))
        let settings = SettingsStore(Settings(name: "Silo on test"))
        let libraries = Libraries(
            config: SiloConfig(
                host: "127.0.0.1",
                port: 0,
                stateDirectory: root,
                libraryRoots: [media, root.appendingPathComponent("Unmounted")]
            ),
            settings: settings,
            index: try Index(at: nil),
            checks: CheckSignal()
        )
        let wanted = media.appendingPathComponent("Films/New")

        let check = libraries.check(id: "films", path: wanted.path, create: false)
        #expect(
            check.components.suffix(3).map(\.state) == [.folder, .missing, .missing],
            "Media is there; Films and New are not"
        )
        #expect(check.components.last?.path == wanted.path)
        #expect(check.root == media.path)
        #expect(check.creates == [media.appendingPathComponent("Films").path, wanted.path])
        #expect(
            check.refusal == .bad("\(wanted.path) is not a folder that exists"),
            "without create, the addition is refused"
        )
        #expect(libraries.check(id: "films", path: wanted.path, create: true).refusal == nil, "with it, it is not")
        #expect(
            libraries.check(id: "", path: wanted.path, create: true).creates.count == 2,
            "the path is checked before the library is named"
        )
        #expect(
            Indexer.isFolder(atPath: media.appendingPathComponent("Films").path) == nil,
            "and checking made nothing"
        )

        let blocked = libraries.check(
            id: "notes",
            path: media.appendingPathComponent("notes.txt/films").path,
            create: true
        )
        #expect(blocked.components.last?.state == .notAFolder, "the list stops at what is not a folder")
        #expect(blocked.refusal == .bad("\(media.appendingPathComponent("notes.txt").path) is not a folder"))
        let unmounted = libraries.check(
            id: "shows",
            path: root.appendingPathComponent("Unmounted/Shows").path,
            create: true
        )
        #expect(
            unmounted.refusal
                == .outside(
                    "\(root.appendingPathComponent("Unmounted").path) would be made outside the library roots: a root is made by the machine's owner"
                ),
            "a missing root is never made"
        )
        #expect(
            libraries.check(id: "shows", path: root.appendingPathComponent("Unmounted/Shows").path, create: false)
                .refusal == unmounted.refusal,
            "and that is said even when nothing asks for it, rather than that the folders do not exist"
        )
        await #expect(throws: OutsideTheRoots.self) {
            try await libraries.add(
                id: "shows",
                path: root.appendingPathComponent("Unmounted/Shows").path,
                create: true
            )
        }
        #expect(Indexer.isFolder(atPath: root.appendingPathComponent("Unmounted").path) == nil)

        let added = try await libraries.add(id: "films", path: wanted.path, create: true)
        #expect(Indexer.isFolder(atPath: wanted.path) == true)
        #expect(settings.current.libraries.map(\.id) == ["films"])
        #expect(libraries.isAvailable(added.id), "an empty folder just made is an available library")
    }

    /// No folder is made where a drive mounts: not in a folder whose children are drives, and not
    /// below a mount point fstab declares while nothing is mounted on it. Inside a drive that is there,
    /// folders are made as anywhere.
    @Test func noFolderIsMadeWhereADriveMounts() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("silo-mounts-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let volumes = root.appendingPathComponent("Volumes")
        let disk = root.appendingPathComponent("Disks/Media")
        try FileManager.default.createDirectory(
            at: volumes.appendingPathComponent("Present"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: disk, withIntermediateDirectories: true)
        func libraries(mounted: Bool) -> Libraries {
            Libraries(
                config: SiloConfig(
                    host: "127.0.0.1",
                    port: 0,
                    stateDirectory: root,
                    libraryRoots: [volumes, root.appendingPathComponent("Disks")]
                ),
                settings: SettingsStore(Settings(name: "Silo on test")),
                index: try! Index(at: nil),
                checks: CheckSignal(),
                mounts: MountPoints(
                    holders: [volumes.path],
                    declared: [.init(path: disk.path, by: "/etc/fstab")],
                    isMounted: { _ in mounted }
                )
            )
        }
        let away = volumes.appendingPathComponent("Media")
        #expect(
            libraries(mounted: false).check(id: "films", path: away.appendingPathComponent("Films").path, create: true)
                .refusal
                == .outside("it would be created where drives are mounted")
        )
        #expect(
            libraries(mounted: false).check(id: "films", path: away.appendingPathComponent("Films").path, create: false)
                .refusal
                == .outside("it would be created where drives are mounted"),
            "said rather than that the folders do not exist, since asking would not make them"
        )
        #expect(
            libraries(mounted: false).check(
                id: "films",
                path: volumes.appendingPathComponent("Present/Films").path,
                create: true
            ).refusal == nil,
            "inside a drive that is there, folders are made"
        )
        let underDisk = disk.appendingPathComponent("Films")
        #expect(
            libraries(mounted: false).check(id: "films", path: underDisk.path, create: true).refusal
                == .outside(
                    "it would be created in \(disk.path), which /etc/fstab declares as a mount point and has nothing mounted on it"
                )
        )
        #expect(
            libraries(mounted: true).check(id: "films", path: underDisk.path, create: true).refusal == nil,
            "and with its drive mounted, they are made"
        )
    }

    @Test func mountPointsAreReadAsTheMachineHasThem() {
        let fstab = """
            # <file system> <mount point> <type> <options> <dump> <pass>
            UUID=1234 / ext4 errors=remount-ro 0 1
            UUID=5678\t/srv/media\text4\tdefaults,nofail 0 2
            LABEL=Films /mnt/My\\040Films ext4 noauto 0 0
            /swapfile none swap sw 0 0
            """
        #expect(MountPoints.declared(fstab: fstab).map(\.path) == ["/", "/srv/media", "/mnt/My Films"])
        #expect(MountPoints.holders(platform: .macOS) == ["/Volumes"])
        #expect(MountPoints.path("/media/simon", matches: "/media/*"))
        #expect(!MountPoints.path("/media/simon/Disk", matches: "/media/*"))
        #expect(MountPoints.isMounted("/"))
        #expect(MountPoints.isMounted("/dev"), "devfs, or the container's tmpfs, is mounted on its own")
        #expect(
            !MountPoints.isMounted(
                FileManager.default.temporaryDirectory.appendingPathComponent("silo-not-a-mount-\(UUID().uuidString)")
                    .path
            ),
            "nothing there, nothing mounted"
        )
    }

    /// The mount points systemd units declare: the machine's own units, and the ones enabled from
    /// elsewhere through a `.wants` link; not a unit only shipped, nor one that is not a mount.
    @Test func mountPointsAreReadFromSystemdUnits() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("silo-units-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let etc = root.appendingPathComponent("etc/systemd/system")
        let shipped = root.appendingPathComponent("usr/lib/systemd/system")
        try FileManager.default.createDirectory(
            at: etc.appendingPathComponent("multi-user.target.wants"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: shipped, withIntermediateDirectories: true)
        func write(_ text: String, to url: URL) throws { try Data(text.utf8).write(to: url) }
        try write(
            "[Unit]\nDescription=Media\n\n[Mount]\nWhat=/dev/disk/by-label/Media\nWhere=/srv/media\nType=ext4\n",
            to: etc.appendingPathComponent("srv-media.mount")
        )
        try write(
            "[Unit]\nWhere=/nowhere\n[Automount]\n  Where = /mnt/backup\n",
            to: shipped.appendingPathComponent("mnt-backup.automount")
        )
        try FileManager.default.createSymbolicLink(
            at: etc.appendingPathComponent("multi-user.target.wants/mnt-backup.automount"),
            withDestinationURL: shipped.appendingPathComponent("mnt-backup.automount")
        )
        try write("[Mount]\nWhere=/tmp\n", to: shipped.appendingPathComponent("tmp.mount"))
        try write("[Service]\nWhere=/srv/service\n", to: etc.appendingPathComponent("media.service"))

        let declared = MountPoints.declared(units: [etc.path, root.appendingPathComponent("run/systemd/system").path])
        #expect(
            declared.map(\.path) == ["/mnt/backup", "/srv/media"],
            "the unit enabled through the link and the machine's own; not the shipped one, nor a service"
        )
        #expect(declared.last?.by == etc.appendingPathComponent("srv-media.mount").path)

        let mounts = MountPoints(holders: [], declared: declared, isMounted: { _ in false })
        #expect(
            mounts.reasonNotToMake(in: "/srv/media", along: ["/srv", "/srv/media"])
                == "it would be created in /srv/media, which \(etc.path)/srv-media.mount declares as a mount point and has nothing mounted on it"
        )
    }

    @Test func aRootIsMatchedByWholeComponents() {
        #expect(Libraries.path("/srv/media/films", liesWithin: "/srv/media"))
        #expect(Libraries.path("/srv/media", liesWithin: "/srv/media"))
        #expect(!Libraries.path("/srv/media2/films", liesWithin: "/srv/media"))
        #expect(!Libraries.path("/etc", liesWithin: "/srv"))
        #expect(Libraries.path("/anything", liesWithin: "/"))
    }
}
