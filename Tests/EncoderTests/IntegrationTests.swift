// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloKit
import SmdKit
import Testing
@testable import Encoder

/// The one test that runs the real tools, on a sample the tools make: two seconds of test pattern
/// with two sine-wave tracks, the second titled and marked as a commentary. Skipped where `ffmpeg`
/// is not installed, which is why the argument list and the probe reduction are tested on their
/// own above; this checks the two agree with `ffmpeg` itself.
@Suite(.enabled(if: FFmpeg.isAvailable && FFprobe.isAvailable, "ffmpeg and ffprobe are needed"))
struct IntegrationTests {
    @Test func aSampleIsEncodedToTheLayoutTheRecipePromised() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("silo-encoder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let sample = folder.appendingPathComponent("sample.mkv")
        let output = folder.appendingPathComponent("output.mkv")

        let ffmpeg = try FFmpeg()
        let probe = try FFprobe()
        try await ffmpeg.run([
            "-y", "-nostdin", "-hide_banner", "-loglevel", "error",
            "-f", "lavfi", "-i", "testsrc=size=320x240:rate=25:duration=2",
            "-f", "lavfi", "-i", "sine=frequency=440:duration=2",
            "-f", "lavfi", "-i", "sine=frequency=880:duration=2",
            "-map", "0:v", "-map", "1:a", "-map", "2:a",
            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "flac",
            "-metadata:s:a:0", "title=Main", "-metadata:s:a:1", "title=Commentary",
            "-disposition:a:1", "comment",
            sample.path,
        ])

        let facts = SourceFacts(probe: try await probe.probe(sample), kind: .featurette)
        #expect(facts.video?.width == 320)
        #expect(facts.audio.map(\.lossless) == [true, true])
        #expect(facts.audio.map(\.role) == [.main, .commentary])

        let ruleset = Ruleset(name: "test", rules: [
            Rule(id: "small-extras", scope: .video,
                 conditions: [Condition(.kind, .equal("featurette")), Condition(.videoWidth, .less(576))],
                 action: .encode(EncodeSettings(codec: "libx264", preset: "ultrafast", crf: 30, pixelFormat: "yuv420p", filters: [.deinterlace(.auto)]))),
            Rule(id: "lossless-main", scope: .audio,
                 conditions: [Condition(.audioLossless, .equal("true")), Condition(.audioRole, .notEqual("commentary"))],
                 action: .encode(EncodeSettings(codec: "flac"))),
            Rule(id: "commentary", scope: .audio, conditions: [Condition(.audioRole, .equal("commentary"))],
                 action: .encode(EncodeSettings(codec: "aac", bitrate: "96k", channels: 2))),
            Rule(scope: .video, action: .copy),
            Rule(scope: .audio, action: .copy),
            Rule(scope: .subtitle, action: .copy),
        ])
        let mappings = [TrackMapping(feature: "commentary1", audio: 2)]
        let recipe = try RecipeResolver.resolve(facts, with: ruleset, mappings: mappings)
        #expect(recipe.decisions.map(\.rule) == ["small-extras", "lossless-main", "commentary"])

        let reports = Reports()
        try await ffmpeg.run(recipe.ffmpegArguments(input: sample, output: output)) { reports.add($0) }
        #expect(reports.count > 0)
        #expect(reports.last?.finished == true)

        let result = try await probe.probe(output)
        #expect(recipe.verify(against: result, source: facts).isEmpty)
        #expect(result.streams.map(\.codec) == ["h264", "flac", "aac"])
        #expect(result.streams[2].title == "Commentary", "metadata travels with the stream")
        #expect(recipe.tracks(for: mappings) == [TrackMapping(feature: "commentary1", audio: 2)])
    }

    @Test func aFailureCarriesWhatFFmpegSaid() async throws {
        let ffmpeg = try FFmpeg()
        await #expect(throws: ToolError.self) {
            try await ffmpeg.run(["-nostdin", "-hide_banner", "-loglevel", "error", "-i", "/nonexistent/file.mkv", "-f", "null", "-"])
        }
    }

    @Test func theEncodersAreListed() async throws {
        let encoders = try await FFmpeg().encoders()
        #expect(encoders.contains("flac"))
        #expect(encoders.contains("aac"))
    }
}

final class Reports: Sendable {
    private let reports = Mutex<[EncodeProgress]>([])
    func add(_ report: EncodeProgress) { reports.withLock { $0.append(report) } }
    var count: Int { reports.withLock { $0.count } }
    var last: EncodeProgress? { reports.withLock { $0.last } }
}

import Synchronization
