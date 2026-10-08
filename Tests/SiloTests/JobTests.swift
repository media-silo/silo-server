// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Encoder
import FileServing
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
        let sources: SourceStore
        let recipes: RecipeStore
        let settings: SettingsStore
        let bindingService: BindingService
        let service: JobService
        let index: Index

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("silo-jobs-\(UUID().uuidString)")
            let library = root.appendingPathComponent("Library")
            try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
            config = SiloConfig(host: "127.0.0.1", port: 0, stateDirectory: root.appendingPathComponent("State"), libraries: [LibraryConfig(id: "main", root: library)])
            store = JobStore()
            sources = SourceStore()
            recipes = RecipeStore()
            let bindings = BindingStore()
            let rulesets = try RulesetStore(folder: root.appendingPathComponent("State/rulesets"))
            _ = try rulesets.store(Data(Self.household.utf8), as: "household")
            index = try Index(at: nil)
            settings = SettingsStore(Settings(name: "Silo on test", libraries: config.libraries))
            bindingService = BindingService(config: config, settings: settings, index: index, rulesets: rulesets, sources: sources, bindings: bindings, recipes: recipes)
            service = JobService(config: config, jobs: store, sources: sources, bindings: bindings, recipes: recipes, index: index)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }

        /// The household ruleset with a second output, for the mobile profile.
        static let household = Fixture.household.replacingOccurrences(of: #"<output container="mkv"/>"#, with: #"<output container="mkv"/><output profile="mobile" container="mkv"/>"#)

        /// A copy of a file that only needs to exist for these tests.
        func copy(_ name: String = "rip.mkv", on holder: String = "laptop") throws -> FileRef {
            let url = root.appendingPathComponent(name)
            try Data("video".utf8).write(to: url)
            return FileRef(holder: holder, url: url, path: url.path, sizeBytes: 5, secret: "s3cret")
        }

        /// Two seconds in four chapters: video, a main mix and a commentary only titled one.
        static let input = InputSpec(
            duration: 2,
            chapters: [InputSpec.Chapter(index: 1, start: 0), InputSpec.Chapter(index: 2, start: 0.5), InputSpec.Chapter(index: 3, start: 1), InputSpec.Chapter(index: 4, start: 1.5)],
            streams: [
                InputSpec.Stream(index: 0, kind: .video, codec: "h264", width: 320, height: 240, frameRate: 25),
                InputSpec.Stream(index: 1, kind: .audio, codec: "flac", channels: 1),
                InputSpec.Stream(index: 2, kind: .audio, codec: "flac", channels: 1, title: "Commentary"),
            ]
        )

        static let containers = [Fixture.series, Fixture.serial].map { String(decoding: ContainerFile.data(for: $0), as: UTF8.self) }

        /// Registers a source with the copy given, binds part three of *Pyramids of Mars* to the
        /// segments of it given, and applies the household ruleset for one output: the draft.
        func draft(input: InputSpec = Bench.input, copy: FileRef?, chapters: Binding.ChapterSpan? = nil, segments count: Int = 1, profile: String? = nil) throws -> StoredRecipe {
            let source = try sources.register(input, key: nil, copy: copy).source
            let binding = try bindingService.make(Binding(
                library: "main", containers: Self.containers, item: "part3",
                tracks: [TrackMapping(feature: "commentary1", audio: 2)], chapters: [Chapter(index: 1, title: "Opening")],
                segments: Array(repeating: Binding.Segment(source: source.id, chapters: chapters), count: count)
            ))
            return try #require(try bindingService.apply(Application(ruleset: "household", outputs: [Application.OutputChoice(profile: profile)]), to: binding.id).first)
        }
    }

    @Test func aJobGoesFromADraftToPlaced() async throws {
        let bench = try Bench()
        defer { bench.remove() }
        let service = bench.service

        let draft = try bench.draft(copy: try bench.copy())
        #expect(draft.facts.audio.map(\.role) == [.main, .commentary], "the feature map decides the role; the title alone would only hint")
        #expect(draft.recipe.decisions.map(\.rule) == ["#4", "lossless-main", "commentary"], "an episode's video is copied; a featurette's would be re-encoded")

        let pending = try service.make(from: draft.id)
        #expect(pending.state == .pending)
        #expect(pending.recipe == draft.id)
        #expect(pending.requirements == ["aac", "flac"])
        #expect(pending.attempts.isEmpty && pending.lease == nil && pending.output == nil && pending.failure == nil)
        #expect(pending.id == pending.id.lowercased())
        #expect(bench.recipes.recipe(draft.id)?.state == .committed, "making the job commits its recipe")
        #expect(try service.all().map(\.id) == [pending.id])

        #expect(try await service.claim(node: "box", capabilities: ["flac"]) == nil, "a node without aac cannot claim it")
        let claim = try #require(try await service.claim(node: "box", capabilities: ["flac", "aac"]))
        let claimed = claim.job
        #expect(claimed.state == .claimed)
        #expect(claimed.lease?.node == "box")
        #expect(claimed.attempts.count == 1)
        #expect(claim.recipe?.id == draft.id)
        #expect(claim.segments.map(\.copy.secret) == ["s3cret"], "the claimant is handed the secret it will fetch by")
        #expect(claim.segments.allSatisfy { $0.isWhole }, "a whole source needs no cutting")
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
        #expect(again.recipe == draft.id, "the same committed recipe")
        let reclaimed = try #require(try await service.claim(node: "box", capabilities: ["flac", "aac"])).job

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
        #expect(serial.sidecar.presentations["part3"]?.first?.chapters == [Chapter(index: 1, title: "Opening")], "the binding's chapter names")
        #expect(try bench.index.presentation(placed.placement!.presentation!) != nil, "the index learned of it")
        #expect(throws: WrongState.self) { try service.cancel(placed.id) }
    }

    @Test func aJobIsMadeOnlyFromADraftWhoseSourcesCanBeHad() throws {
        let bench = try Bench()
        defer { bench.remove() }
        let service = bench.service
        #expect(throws: NoSuchRecipe.self) { try service.make(from: "nothing") }

        let draft = try bench.draft(copy: try bench.copy())
        _ = try service.make(from: draft.id)
        #expect(throws: CommittedRecipe.self) { try service.make(from: draft.id) }
        #expect(try service.all().count == 1, "one recipe is run by one job")

        let unheld = try bench.draft(copy: nil)
        let source = try bench.bindingService.binding(unheld.binding).binding.segments[0].source
        let refusal = #expect(throws: Unrunnable.self) { try service.make(from: unheld.id) }
        #expect(refusal?.reason == "source \(source) has no copy; no node could fetch it")
        #expect(bench.recipes.recipe(unheld.id)?.state == .draft, "and the recipe stays a draft")
        #expect(try service.all().count == 1)
    }

    @Test func aClaimPrefersWhatTheNodeHoldsAndHandsOverEachSpan() async throws {
        let bench = try Bench()
        defer { bench.remove() }
        let service = bench.service
        let elsewhere = try service.make(from: try bench.draft(copy: try bench.copy("a.mkv", on: "laptop")).id)
        let held = try service.make(from: try bench.draft(copy: try bench.copy("b.mkv", on: "box"), chapters: Binding.ChapterSpan(from: 2, to: 3), segments: 2).id)
        #expect(elsewhere.createdAt <= held.createdAt)

        let claim = try #require(try await service.claim(node: "box", capabilities: ["flac", "aac"]))
        #expect(claim.job.id == held.id, "the job whose every source the node holds, though it is newer")
        #expect(claim.segments.count == 2)
        #expect(claim.segments.map(\.start) == [0.5, 0.5])
        #expect(claim.segments.map(\.end) == [1.5, 1.5], "chapters two and three: from the second's start to the fourth's")
        #expect(claim.segments.allSatisfy { $0.copy.holder == "box" })
        #expect(try await service.claim(node: "box", capabilities: ["flac", "aac"])?.job.id == elsewhere.id, "then the oldest")
    }

    @Test func aMismatchedLayoutFailsAndALapsedLeaseIsReclaimed() async throws {
        let bench = try Bench()
        defer { bench.remove() }
        let service = bench.service
        let job = try service.make(from: try bench.draft(copy: try bench.copy()).id)

        let claimed = try #require(try await service.claim(node: "box", capabilities: ["flac", "aac"])).job
        let failed = try await service.complete(claimed.id, output: FileRef(holder: "box", url: URL(fileURLWithPath: "/x"), secret: ""), result: EncodeResult(streams: ["video h264"], layoutMatched: false))
        #expect(failed.state == .failed)
        #expect(failed.failure == "the output's layout is not the recipe's")
        await #expect(throws: WrongState.self) { try await service.place(failed.id) }

        _ = try service.retry(job.id)
        for lost in 1...JobService.attemptsAllowed {
            let held = try #require(try await service.claim(node: "box\(lost)", capabilities: ["flac", "aac"])).job
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
    /// Two seconds of video and two audio streams, made by the tools themselves.
    static func sample(_ url: URL, with ffmpeg: FFmpeg) async throws {
        try await ffmpeg.run([
            "-y", "-nostdin", "-hide_banner", "-loglevel", "error",
            "-f", "lavfi", "-i", "testsrc=size=320x240:rate=25:duration=2",
            "-f", "lavfi", "-i", "sine=frequency=440:duration=2",
            "-f", "lavfi", "-i", "sine=frequency=880:duration=2",
            "-map", "0:v", "-map", "1:a", "-map", "2:a", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-g", "5", "-c:a", "flac",
            url.path,
        ])
    }

    static func worker(_ bench: JobServiceTests.Bench, ffmpeg: FFmpeg, ffprobe: FFprobe) -> Worker {
        Worker(
            api: bench.service,
            configuration: Worker.Configuration(nodeID: "embedded", workFolder: bench.root.appendingPathComponent("work"), progressInterval: .milliseconds(100)) { _, file in
                FileRef(holder: "embedded", url: file, path: file.path, secret: "")
            },
            ffmpeg: ffmpeg, ffprobe: ffprobe
        )
    }

    @Test func theEmbeddedNodeEncodesAndTheSiloPlaces() async throws {
        let bench = try JobServiceTests.Bench()
        defer { bench.remove() }
        let sample = bench.root.appendingPathComponent("sample.mkv")
        let ffmpeg = try FFmpeg()
        let ffprobe = try FFprobe()
        try await Self.sample(sample, with: ffmpeg)
        let input = InputSpec(probe: try await ffprobe.probe(sample))
        let draft = try bench.draft(input: input, copy: FileRef(holder: "embedded", url: sample, path: sample.path, secret: ""), profile: "mobile")
        let job = try bench.service.make(from: draft.id)

        let worker = Self.worker(bench, ffmpeg: ffmpeg, ffprobe: ffprobe)
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

    @Test func aSpanOfOneHeldSourceAndAWholeFetchedOneAreEncodedAsOneInput() async throws {
        let bench = try JobServiceTests.Bench()
        defer { bench.remove() }
        let ffmpeg = try FFmpeg()
        let ffprobe = try FFprobe()
        let first = bench.root.appendingPathComponent("disc1.mkv")
        let second = bench.root.appendingPathComponent("disc2.mkv")
        try await Self.sample(first, with: ffmpeg)
        try await Self.sample(second, with: ffmpeg)
        var input = InputSpec(probe: try await ffprobe.probe(first))
        input.chapters = [InputSpec.Chapter(index: 1, start: 0), InputSpec.Chapter(index: 2, start: 1)]

        // The first held here, opened by its path; the second served by another node, and fetched.
        let server = try FileServer(host: "127.0.0.1", port: 0, advertisedHost: "127.0.0.1")
        let serving = Task { try await server.run() }
        defer { serving.cancel() }
        var served = server.publish(second, at: "disc2/source")
        served.holder = "elsewhere"
        served.url = URL(string: "http://127.0.0.1:\(try await server.boundPort)/files/disc2/source")!
        let one = try bench.sources.register(input, key: nil, copy: FileRef(holder: "embedded", url: first, path: first.path, secret: "")).source
        let two = try bench.sources.register(input, key: NaturalKey(scheme: "test", value: "two"), copy: served).source
        let binding = try bench.bindingService.make(Binding(
            library: "main", containers: JobServiceTests.Bench.containers, item: "part3",
            segments: [Binding.Segment(source: one.id, chapters: Binding.ChapterSpan(from: 2, to: 2)), Binding.Segment(source: two.id)]
        ))
        let draft = try #require(try bench.bindingService.apply(Application(ruleset: "household"), to: binding.id).first)
        #expect(draft.facts.duration.map { abs($0 - 3) < 0.1 } == true, "a second of the first and two of the second")
        let job = try bench.service.make(from: draft.id)

        #expect(try await Self.worker(bench, ffmpeg: ffmpeg, ffprobe: ffprobe).runOnce() == true)
        let encoded = try bench.service.job(job.id)
        #expect(encoded.state == .encoded, "\(encoded.failure ?? "")")
        let list = try String(contentsOf: bench.root.appendingPathComponent("work/\(job.id).concat"), encoding: .utf8)
        #expect(list.hasPrefix("ffconcat version 1.0\nfile '\(first.path)'\ninpoint 1.0\noutpoint "), "the span of the first, to its end")
        let fetched = bench.root.appendingPathComponent("work/\(job.id).2.source.mkv")
        #expect(try Data(contentsOf: fetched) == Data(contentsOf: second), "the second fetched into the work folder by its position")
        #expect(list.hasSuffix("\nfile '\(fetched.path)'\n"), "and joined whole, uncut")
        let output = try #require(encoded.output?.url)
        let duration = try #require(try await ffprobe.probe(output).duration)
        #expect(duration > 2.5 && duration < 3.5, "joined and cut: \(duration) seconds")
    }
}
