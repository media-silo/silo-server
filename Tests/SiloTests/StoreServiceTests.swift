// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloLibrary
import SiloStore
import SmdKit
import SmdSidecar
import Testing

@testable import SiloApp

/// A library's stores, on the service alone over a temporary folder and an in-memory index: a store
/// made in order in one turn, sent twice, refused by its check or by a step's route, and resumed.
struct StoreServiceTests {
    struct Bench {
        let root: URL
        let library: LibraryConfig
        let index: Index
        let libraries: Libraries
        let records: StoreRecords
        let blobs: BlobStore

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("silo-stores-\(UUID().uuidString)")
            library = LibraryConfig(id: "main", root: root.appendingPathComponent("Library"))
            try FileManager.default.createDirectory(at: library.root, withIntermediateDirectories: true)
            let config = SiloConfig(
                silo: SiloFile(serverID: "s1", host: "127.0.0.1", port: 0, libraryRoots: [root.path]),
                stateDirectory: root.appendingPathComponent("State")
            )
            index = try Index(at: nil)
            libraries = Libraries(
                config: config,
                settings: SettingsStore(Settings(name: "Silo on test", libraries: [library])),
                index: index,
                checks: CheckSignal()
            )
            records = try StoreRecords(folder: root.appendingPathComponent("State/stores"))
            blobs = try BlobStore(folder: root.appendingPathComponent("State/blobs"))
        }

        /// A service as the silo makes one when it starts, over the same records.
        func service() -> StoreService {
            StoreService(libraries: libraries, index: index, records: records, blobs: blobs)
        }

        /// Takes a store and makes it, as the silo's making of stores would: made or refused.
        @discardableResult
        func store(_ steps: [StoreStep], key: String, with service: StoreService? = nil) async throws -> StoreRecord {
            let service = service ?? self.service()
            _ = try service.take(steps, key: key, in: library)
            await service.makeQueued()
            return try service.record(key, in: library)
        }

        /// A service as the silo makes one when it starts, having made the stores under way.
        func resumed() async {
            let service = service()
            service.resume()
            await service.makeQueued()
        }

        func sidecar(_ folder: String) throws -> Data {
            try Data(contentsOf: library.root.appendingPathComponent("\(folder)/container.smd"))
        }

        func digest(_ folder: String) throws -> String {
            IndexedContainer.digest(of: try sidecar(folder))
        }

        func held(_ id: ContainerID) throws -> Bool {
            try index.container(id, in: library.id) != nil
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    static let season = Container(id: ContainerID("00000000000000a2")!, type: .season, title: Title("Season 1")!)
    static let series = Container(id: ContainerID("00000000000000a1")!, type: .series, title: Title("Andor")!)
    static var naming: Container {
        var series = series
        series.sequences = [
            Sequence(id: "seasons", items: [.child(Entry.Child(id: ItemID("s1")!, container: season.id))])
        ]
        return series
    }
    static let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0] + Array(repeating: 0x55, count: 32))

    static func xml(_ container: Container) -> String {
        String(decoding: ContainerFile.data(for: container), as: UTF8.self)
    }

    static func create(_ container: Container, beneath parent: Container? = nil) -> StoreStep {
        StoreStep.create(StoreStep.Create(documents: [xml(container)], parent: parent?.id.value))
    }

    /// The series made alone at the top of the library, and the three steps that name a season in it,
    /// make the season and put its poster.
    static func steps(basedOn digest: String, image: String) -> [StoreStep] {
        [
            StoreStep.edit(StoreStep.Edit(container: series.id.value, document: xml(naming), basedOn: digest)),
            create(season, beneath: series),
            StoreStep.putArtwork(
                StoreStep.Artwork(
                    container: season.id.value,
                    kind: "poster",
                    image: image,
                    provider: "tmdb",
                    value: "season/1",
                    read: "2026-11-12"
                )
            ),
        ]
    }

    @Test func aStoreIsMadeInOrderAndSentTwiceIsMadeOnce() async throws {
        let bench = try Bench()
        defer { bench.remove() }
        #expect(try await bench.store([Self.create(Self.series)], key: "first").state == .made)
        let image = try bench.blobs.put(Self.jpeg)
        let steps = Self.steps(basedOn: try bench.digest("Andor"), image: image)
        let service = bench.service()

        let made = try await bench.store(steps, key: "walk-1", with: service)
        #expect(made.state == .made)
        #expect(made.made == 3 && made.step == nil)
        #expect(try bench.held(Self.season.id))
        let seasonFolder = "Andor/01 - Season 1"
        #expect(try SidecarFile.sidecar(from: bench.sidecar("Andor")).children[Self.season.id] != nil)
        #expect(
            FileManager.default.fileExists(
                atPath: bench.library.root.appendingPathComponent("\(seasonFolder)/poster.jpg").path
            )
        )
        #expect(
            try SidecarFile.sidecar(from: bench.sidecar(seasonFolder)).attributions.map(\.subject.rawValue) == [
                "artwork/poster"
            ]
        )

        // Sent again with the same steps, the one store is answered, and nothing is made again.
        let written = try bench.sidecar("Andor")
        let again = try service.take(steps, key: "walk-1", in: bench.library)
        #expect(!again.added)
        await service.makeQueued()
        #expect(again.record == made)
        #expect(try bench.sidecar("Andor") == written)

        // With other steps, the key is refused.
        #expect(throws: StoreKeyTaken.self) {
            try service.take(Array(steps.prefix(2)), key: "walk-1", in: bench.library)
        }
        #expect(throws: BadStoreKey.self) { try service.take(steps, key: "a/b", in: bench.library) }
        #expect(throws: NoSuchStore.self) { try service.record("never", in: bench.library) }
    }

    @Test func aStoreTheCheckRefusesMakesNothing() async throws {
        let bench = try Bench()
        defer { bench.remove() }
        try await bench.store([Self.create(Self.series)], key: "first")
        let image = try bench.blobs.put(Self.jpeg)

        // An edit on a sidecar the library no longer holds, after a step the check would pass.
        let before = Container(id: ContainerID("00000000000000a5")!, type: .movie, title: Title("Rogue One")!)
        let stale = try await bench.store(
            [Self.create(before)] + Self.steps(basedOn: String(repeating: "0", count: 64), image: image),
            key: "stale"
        )
        #expect(stale.state == .refused)
        #expect(stale.step == 1 && stale.made == 0)
        #expect(stale.reason?.hasPrefix("the sidecar is now ") == true)
        #expect(try !bench.held(before.id) && !bench.held(Self.season.id), "none of its steps is made")

        // An image the silo does not hold.
        let missing = String(repeating: "f", count: 64)
        let unheld = try await bench.store(
            Self.steps(basedOn: try bench.digest("Andor"), image: missing),
            key: "unheld"
        )
        #expect(unheld.state == .refused && unheld.step == 2)
        #expect(unheld.reason == "the silo holds no image \(missing)")
        #expect(try !bench.held(Self.season.id))

        // A container neither held nor made before, and a kind that is not one.
        let orphan = try await bench.store([Self.create(Self.season, beneath: Self.season)], key: "orphan")
        #expect(orphan.state == .refused && orphan.step == 0)
        let wallpaper = StoreStep.removeArtwork(StoreStep.Artwork(container: Self.series.id.value, kind: "wallpaper"))
        #expect(try await bench.store([wallpaper], key: "wallpaper").reason == "wallpaper is not an artwork kind")
    }

    @Test func aStepIsOneKindInItsJSON() throws {
        let step = StoreStep.removeArtwork(StoreStep.Artwork(container: Self.series.id.value, kind: "poster"))
        let json = try JSONEncoder().encode(step)
        #expect(
            try JSONSerialization.jsonObject(with: json) as? [String: [String: String]] == [
                "removeArtwork": ["container": Self.series.id.value, "kind": "poster"]
            ],
            "an object of one key, the kind, holding the step"
        )
        #expect(try JSONDecoder().decode(StoreStep.self, from: json) == step)
        for notOne in [
            #"{}"#, #"{"edit": {"container": "a", "document": "", "basedOn": ""}, "create": {"documents": []}}"#,
        ] {
            #expect(throws: DecodingError.self, "\(notOne) is no step") {
                try JSONDecoder().decode(StoreStep.self, from: Data(notOne.utf8))
            }
        }
    }

    @Test func aStepTheSiloRefusesEndsTheStoreThere() async throws {
        let bench = try Bench()
        defer { bench.remove() }
        try await bench.store([Self.create(Self.series)], key: "first")
        let other = Container(id: ContainerID("00000000000000a3")!, type: .movie, title: Title("Rogue One")!)
        let last = Container(id: ContainerID("00000000000000a4")!, type: .movie, title: Title("Solo")!)

        // The series is held already, so making it again at another place is refused as it is made.
        let refused = try await bench.store(
            [Self.create(other), Self.create(Self.series, beneath: other), Self.create(last)],
            key: "refused"
        )
        #expect(refused.state == .refused)
        #expect(refused.step == 1 && refused.made == 1)
        #expect(refused.findings?.contains { $0.severity == "error" } == true)
        #expect(try bench.held(other.id), "the step before it stands")
        #expect(try !bench.held(last.id), "and the one after it is not made")
    }

    @Test func aStoreUnderWayWhenTheSiloStoppedIsResumed() async throws {
        let bench = try Bench()
        defer { bench.remove() }
        let image = try bench.blobs.put(Self.jpeg)
        try await bench.store([Self.create(Self.series)], key: "first")
        let steps = [Self.create(Self.series)] + Self.steps(basedOn: try bench.digest("Andor"), image: image)

        // Its first step made before the silo stopped, and the record not yet saying so.
        _ = try bench.records.adding(StoreRecord(library: bench.library.id, key: "resumed", steps: steps))
        #expect(bench.records.imagesUnderWay() == [image], "its image is kept while it is under way")
        await bench.resumed()

        let resumed = try #require(bench.records.record("resumed", in: bench.library.id))
        #expect(resumed.state == .made)
        #expect(resumed.made == 4)
        #expect(try bench.held(Self.season.id))
        #expect(bench.records.imagesUnderWay().isEmpty)
    }

    @Test func storesAreMadeAsTheyAreTakenWhileTheServiceRuns() async throws {
        let bench = try Bench()
        defer { bench.remove() }
        let before = StoreRecord(library: bench.library.id, key: "before", steps: [Self.create(Self.series)])
        _ = try bench.records.adding(before)
        let service = bench.service()
        let running = Task { await service.run() }
        func settled(_ key: String) async throws -> StoreRecord {
            var record = try service.record(key, in: bench.library)
            for _ in 0..<500 where record.state == .underWay {
                try await Task.sleep(for: .milliseconds(10))
                record = try service.record(key, in: bench.library)
            }
            return record
        }
        #expect(try await settled("before").state == .made, "the store under way when it started")
        let after = Array(Self.steps(basedOn: try bench.digest("Andor"), image: "").prefix(2))
        _ = try service.take(after, key: "after", in: bench.library)
        #expect(try await settled("after").state == .made, "and one taken while it runs")
        #expect(try bench.held(Self.season.id))

        // Cancelled, it ends; a store taken after is left under way for the next start.
        running.cancel()
        await running.value
        let other = Container(id: ContainerID("00000000000000b1")!, type: .series, title: Title("Ahsoka")!)
        _ = try service.take([Self.create(other)], key: "stopped", in: bench.library)
        #expect(try service.record("stopped", in: bench.library).state == .underWay)
        await bench.resumed()
        #expect(try service.record("stopped", in: bench.library).state == .made)
    }

    @Test func aStoresStepsCarryWhatTheirRoutesTake() async throws {
        let bench = try Bench()
        defer { bench.remove() }
        try await bench.store([Self.create(Self.series)], key: "first")
        let image = try bench.blobs.put(Self.jpeg)
        var film = Container(
            id: ContainerID("00000000000000a6")!,
            type: .movie,
            title: Title("Andor: A Disney+ Day Special Look")!
        )
        film.outline = "A look behind the series"
        let outline = StoreStep.Attribution(
            container: film.id.value,
            subject: "outline",
            provider: "tmdb",
            value: "movie/1",
            read: "2026-11-12"
        )
        let declined = StoreStep.Ref(provider: "tmdb", value: "tv/2")
        let poster = StoreStep.Artwork(container: Self.series.id.value, kind: "poster", image: image)
        let made = try await bench.store(
            [
                StoreStep.create(StoreStep.Create(documents: [Self.xml(film)], attributions: [outline])),
                StoreStep.edit(
                    StoreStep.Edit(
                        container: Self.series.id.value,
                        document: Self.xml(Self.series),
                        basedOn: try bench.digest("Andor"),
                        declined: [declined]
                    )
                ),
                StoreStep.putArtwork(poster),
                StoreStep.removeArtwork(StoreStep.Artwork(container: Self.series.id.value, kind: "poster")),
            ],
            key: "carried"
        )
        #expect(made.state == .made, "\(made.reason ?? "")")
        let series = try SidecarFile.sidecar(from: bench.sidecar("Andor"))
        #expect(series.declined == [ExternalRef(provider: .tmdb, value: "tv/2")])
        #expect(
            !FileManager.default.fileExists(atPath: bench.library.root.appendingPathComponent("Andor/poster.jpg").path)
        )
        let filmFolder = try #require(try bench.index.container(film.id, in: bench.library.id)).folder
        #expect(
            try SidecarFile.sidecar(from: bench.sidecar(filmFolder)).attributions.map(\.subject.rawValue) == ["outline"]
        )

        // What a route refuses in a step's own terms, the check refuses before any step is made.
        let noDay = StoreStep.Attribution(
            container: film.id.value,
            subject: "outline",
            provider: "tmdb",
            value: "movie/1",
            read: "2026-02-30"
        )
        let refusals: [(StoreStep, String)] = [
            (
                StoreStep.create(StoreStep.Create(documents: [Self.xml(film)], attributions: [noDay])),
                "2026-02-30 is not a yyyy-mm-dd date to have read outline on"
            ),
            (
                StoreStep.putArtwork(
                    StoreStep.Artwork(
                        container: Self.series.id.value,
                        kind: "poster",
                        image: image,
                        provider: "tmdb"
                    )
                ), "a put of poster names a provider, a value and a read day, or none of them"
            ),
            (
                StoreStep.putArtwork(
                    StoreStep.Artwork(
                        container: Self.series.id.value,
                        kind: "poster",
                        image: image,
                        provider: "tmdb",
                        value: "1",
                        read: "never"
                    )
                ), "never is not a yyyy-mm-dd date to have read poster on"
            ),
            (
                StoreStep.edit(
                    StoreStep.Edit(container: "00000000000000ff", document: Self.xml(Self.series), basedOn: "")
                ), "the library does not hold 00000000000000ff, nor does the store make it before"
            ),
            (
                StoreStep.putArtwork(StoreStep.Artwork(container: "00000000000000ff", kind: "poster", image: image)),
                "the library does not hold 00000000000000ff, nor does the store make it before"
            ),
            (
                StoreStep.edit(StoreStep.Edit(container: Self.series.id.value, document: Self.xml(film), basedOn: "")),
                "the document describes \(film.id), not \(Self.series.id)"
            ),
        ]
        for (position, (step, reason)) in refusals.enumerated() {
            let refused = try await bench.store([step], key: "refused-\(position)")
            #expect(refused.state == .refused && refused.step == 0)
            #expect(refused.reason == reason)
        }

        // An edit of a container an earlier step makes has no base the check can know, and its route
        // refuses one that is not the sidecar made.
        let other = Container(id: ContainerID("00000000000000a7")!, type: .movie, title: Title("Rogue One")!)
        var retitled = other
        retitled.title = Title("Rogue One: A Star Wars Story")!
        let conflict = try await bench.store(
            [
                Self.create(other),
                StoreStep.edit(StoreStep.Edit(container: other.id.value, document: Self.xml(retitled), basedOn: "x")),
            ],
            key: "conflict"
        )
        #expect(conflict.state == .refused && conflict.step == 1 && conflict.made == 1)
        #expect(conflict.reason?.hasPrefix("the sidecar is now ") == true)
    }

    @Test func aStoreOfALibraryNoLongerServedIsRefusedWhenResumed() async throws {
        let bench = try Bench()
        defer { bench.remove() }
        _ = try bench.records.adding(StoreRecord(library: "gone", key: "orphaned", steps: [Self.create(Self.series)]))
        #expect(
            try StoreRecords(folder: bench.records.folder).record("orphaned", in: "gone") != nil,
            "a record is read back"
        )
        await bench.resumed()
        let record = try #require(bench.records.record("orphaned", in: "gone"))
        #expect(record.state == .refused)
        #expect(record.reason == "the silo no longer serves gone")
    }

    @Test func aRecordIsKeptThirtyDays() throws {
        let bench = try Bench()
        defer { bench.remove() }
        var record = StoreRecord(library: "main", key: "old", steps: [Self.create(Self.series)], state: .made, made: 1)
        record.updatedAt = Date()
        _ = try bench.records.adding(record)
        bench.records.sweep(now: Date().addingTimeInterval(StoreRecords.lifetime / 2))
        #expect(bench.records.record("old", in: "main") != nil)
        bench.records.sweep(now: Date().addingTimeInterval(2 * StoreRecords.lifetime))
        #expect(bench.records.record("old", in: "main") == nil)
        #expect(try StoreRecords(folder: bench.records.folder).record("old", in: "main") == nil, "nor is its file")
    }
}
