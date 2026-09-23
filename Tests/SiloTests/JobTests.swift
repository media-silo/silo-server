// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Encoder
import Foundation
import SiloClient
import SiloKit
import SiloLibrary
import SiloStore
import SiloWorker
import SmdKit
import SmdSidecar
import Testing
@testable import SiloApp

/// The job's transitions, on the service alone: no server, an in-memory store, a temporary
/// library. What the API tests then check is that each route reaches the same transition.
struct JobServiceTests {
    struct Bench {
        let root: URL
        let config: SiloConfig
        let store: JobStore
        let service: JobService
        let index: Index

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("silo-jobs-\(UUID().uuidString)")
            let library = root.appendingPathComponent("Library")
            try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
            config = SiloConfig(host: "127.0.0.1", port: 0, stateDirectory: root.appendingPathComponent("State"), libraries: [LibraryConfig(id: "main", root: library)], operatorToken: nil)
            store = JobStore()
            let rulesets = try RulesetStore(folder: root.appendingPathComponent("State/rulesets"))
            _ = try rulesets.store(Data(Fixture.household.utf8), as: "household")
            index = try Index(at: nil)
            service = JobService(config: config, jobs: store, rulesets: rulesets, index: index)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }

        /// A source that only needs to exist for these tests.
        func source(_ name: String = "rip.mkv") throws -> FileRef {
            let url = root.appendingPathComponent(name)
            try Data("video".utf8).write(to: url)
            return FileRef(holder: "laptop", url: url, path: url.path, sizeBytes: 5, secret: "s3cret")
        }

        static let probe = ProbedSource(duration: 2, streams: [
            ProbedStream(absoluteIndex: 0, kind: .video, codec: "h264", width: 320, height: 240, frameRate: 25),
            ProbedStream(absoluteIndex: 1, kind: .audio, codec: "flac", channels: 1),
            ProbedStream(absoluteIndex: 2, kind: .audio, codec: "flac", channels: 1, title: "Commentary"),
        ])

        static func assignment(item: String = "part3", profile: String? = nil) -> Assignment {
            Assignment(
                library: "main",
                containers: [Fixture.series, Fixture.serial].map { String(decoding: ContainerFile.data(for: $0), as: UTF8.self) },
                item: item, profile: profile,
                tracks: [TrackMapping(feature: "commentary1", audio: 2)],
                chapters: [Chapter(index: 1, title: "Opening")],
                ruleset: "household"
            )
        }
    }

    @Test func aJobGoesFromRegisteredToPlaced() async throws {
        let bench = try Bench()
        defer { bench.remove() }
        let service = bench.service

        let registered = try service.register(source: try bench.source(), discName: "Disc 1", probe: Bench.probe, makeMKV: nil)
        #expect(registered.state == .unassigned)
        #expect(try service.all().map(\.id) == [registered.id])

        #expect(throws: BadAssignment.self) { try service.assign(registered.id, Assignment(library: "other", containers: [], item: "x", ruleset: "household")) }
        #expect(throws: BadAssignment.self) { try service.assign(registered.id, Bench.assignment(item: "part9")) }
        #expect(throws: BadAssignment.self) {
            var wrong = Bench.assignment()
            wrong.ruleset = "nothing"
            try service.assign(registered.id, wrong)
        }

        let pending = try service.assign(registered.id, Bench.assignment())
        #expect(pending.state == .pending)
        #expect(pending.facts?.kind == .episode)
        #expect(pending.facts?.audio.map(\.role) == [.main, .commentary], "the feature map decides the role; the title alone would only hint")
        #expect(pending.recipe?.decisions.map(\.rule) == ["#4", "lossless-main", "commentary"], "an episode's video is copied; a featurette's would be re-encoded")
        #expect(pending.requirements == ["aac", "flac"])
        #expect(pending.assignment?.rulesetVersion == 1)

        #expect(try await service.claim(node: "box", capabilities: ["flac"]) == nil, "a node without aac cannot claim it")
        let claimed = try #require(try await service.claim(node: "box", capabilities: ["flac", "aac"]))
        #expect(claimed.state == .claimed)
        #expect(claimed.lease?.node == "box")
        #expect(claimed.attempts.count == 1)
        #expect(try await service.claim(node: "other", capabilities: ["flac", "aac"]) == nil, "claimed once")

        #expect(try await service.report(claimed.id, progress: JobProgress(fraction: 0.5)) == .encoding)
        #expect(try service.job(claimed.id).progress?.fraction == 0.5)

        let cancelling = try service.cancel(claimed.id)
        #expect(cancelling.state == .cancelling)
        #expect(try await service.report(claimed.id, progress: JobProgress(fraction: 0.6)) == .cancelling, "the node learns at its next report")
        let cancelled = try await service.fail(claimed.id, reason: "cancelled")
        #expect(cancelled.state == .cancelled)
        #expect(cancelled.attempts.last?.outcome == "cancelled")
        #expect(throws: WrongState.self) { try service.cancel(claimed.id) }

        let again = try service.retry(claimed.id)
        #expect(again.state == .pending)
        #expect(again.attempts.isEmpty)
        let reclaimed = try #require(try await service.claim(node: "box", capabilities: ["flac", "aac"]))

        // A finished file on this filesystem: the embedded node's case.
        let output = bench.root.appendingPathComponent("encoded.mkv")
        try Fixture.mediaBytes.write(to: output)
        let encoded = try await service.complete(reclaimed.id, output: FileRef(holder: "box", url: output, path: output.path, secret: ""), result: EncodeResult(streams: ["video h264", "audio flac", "audio aac"], layoutMatched: true))
        #expect(encoded.state == .encoded)
        #expect(encoded.attempts.last?.outcome == "encoded")

        let placed = try await service.place(encoded.id)
        #expect(placed.state == .placed)
        #expect(placed.placement?.destination == "Doctor Who (1963)/Pyramids of Mars/Part Three.mkv")
        #expect(placed.placement?.presentation != nil)
        #expect(!FileManager.default.fileExists(atPath: output.path), "moved into the library")
        let tree = LibraryWalker.walk(bench.config.libraries[0].root)
        let serial = try #require(tree.node(for: Fixture.serial.id))
        #expect(serial.sidecar.presentations["part3"]?.first?.tracks == [TrackMapping(feature: "commentary1", audio: 2)], "renumbered by the recipe: nothing was dropped, so unchanged")
        #expect(try bench.index.presentation(placed.placement!.presentation!) != nil, "the index learned of it")
        #expect(throws: WrongState.self) { try service.cancel(placed.id) }
    }

    @Test func aMismatchedLayoutFailsAndALapsedLeaseIsReclaimed() async throws {
        let bench = try Bench()
        defer { bench.remove() }
        let service = bench.service
        let job = try service.register(source: try bench.source(), discName: nil, probe: Bench.probe, makeMKV: nil)
        _ = try service.assign(job.id, Bench.assignment())

        let claimed = try #require(try await service.claim(node: "box", capabilities: ["flac", "aac"]))
        let failed = try await service.complete(claimed.id, output: FileRef(holder: "box", url: URL(fileURLWithPath: "/x"), secret: ""), result: EncodeResult(streams: ["video h264"], layoutMatched: false))
        #expect(failed.state == .failed)
        #expect(failed.failure == "the output's layout is not the recipe's")
        await #expect(throws: WrongState.self) { try await service.place(failed.id) }

        _ = try service.retry(job.id)
        for lost in 1...JobService.attemptsAllowed {
            let held = try #require(try await service.claim(node: "box\(lost)", capabilities: ["flac", "aac"]))
            // The node vanishes: its lease is put in the past, and the next read reclaims it.
            try bench.store.update(held.id) { $0.lease = Lease(node: "box\(lost)", expiresAt: .distantPast) }
            let after = try service.job(held.id)
            #expect(after.attempts.last?.outcome == "lost")
            #expect(after.state == (lost == JobService.attemptsAllowed ? .failed : .pending))
        }
        #expect(try service.job(job.id).failure == "lost by 3 nodes")
    }
}

/// The worker on the service directly, as the embedded node runs it, with the real tools on a
/// sample the tools make. Skipped where ffmpeg is missing.
@Suite(.enabled(if: FFmpeg.isAvailable && FFprobe.isAvailable, "ffmpeg and ffprobe are needed"))
struct WorkerTests {
    @Test func theEmbeddedNodeEncodesAndTheSiloPlaces() async throws {
        let bench = try JobServiceTests.Bench()
        defer { bench.remove() }
        let sample = bench.root.appendingPathComponent("sample.mkv")
        let ffmpeg = try FFmpeg()
        let ffprobe = try FFprobe()
        try await ffmpeg.run([
            "-y", "-nostdin", "-hide_banner", "-loglevel", "error",
            "-f", "lavfi", "-i", "testsrc=size=320x240:rate=25:duration=1",
            "-f", "lavfi", "-i", "sine=frequency=440:duration=1",
            "-f", "lavfi", "-i", "sine=frequency=880:duration=1",
            "-map", "0:v", "-map", "1:a", "-map", "2:a", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "flac",
            sample.path,
        ])
        let probe = try await ffprobe.probe(sample)
        let job = try bench.service.register(source: FileRef(holder: "embedded", url: sample, path: sample.path, secret: ""), discName: nil, probe: probe, makeMKV: nil)
        _ = try bench.service.assign(job.id, JobServiceTests.Bench.assignment(profile: "mobile"))

        let work = bench.root.appendingPathComponent("work")
        let worker = Worker(
            api: bench.service,
            configuration: Worker.Configuration(nodeID: "embedded", workFolder: work, progressInterval: .milliseconds(100)) { _, file in
                FileRef(holder: "embedded", url: file, path: file.path, secret: "")
            },
            ffmpeg: ffmpeg, ffprobe: ffprobe
        )
        #expect(try await worker.runOnce() == true)
        #expect(try await worker.runOnce() == false, "nothing left to claim")

        let encoded = try bench.service.job(job.id)
        #expect(encoded.state == .encoded)
        #expect(encoded.result?.streams == ["video h264", "audio flac", "audio aac"])
        #expect(encoded.output?.url.lastPathComponent == "\(job.id).mkv")

        let placed = try await bench.service.place(job.id)
        #expect(placed.state == .placed)
        #expect(placed.placement?.destination == "Doctor Who (1963)/Pyramids of Mars/Part Three - mobile.mkv")
        let probedInPlace = try await ffprobe.probe(bench.config.libraries[0].root.appendingPathComponent(placed.placement!.destination))
        #expect(probedInPlace.streams.map(\.codec) == ["h264", "flac", "aac"])
    }
}
