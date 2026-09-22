// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloKit
import SmdKit
import Testing
@testable import Encoder

struct ArgumentsTests {
    static let household = Ruleset(
        name: "household",
        rules: [
            Rule(id: "small-extras", scope: .video,
                 conditions: [Condition(.kind, .equal("featurette")), Condition(.videoWidth, .less(576))],
                 action: .encode(EncodeSettings(codec: "libx264", preset: "slow", crf: 22, pixelFormat: "yuv420p", filters: [.deinterlace(.auto)]))),
            Rule(id: "lossless-main", scope: .audio,
                 conditions: [Condition(.audioLossless, .equal("true")), Condition(.audioRole, .notEqual("commentary"))],
                 action: .encode(EncodeSettings(codec: "flac", options: ["compression_level": "8"]))),
            Rule(id: "commentary", scope: .audio, conditions: [Condition(.audioRole, .equal("commentary"))],
                 action: .encode(EncodeSettings(codec: "aac", bitrate: "160k", channels: 2))),
            Rule(id: "no-core", scope: .audio, conditions: [Condition(.audioCore, .equal("true"))], action: .drop),
            Rule(scope: .video, action: .copy),
            Rule(scope: .audio, action: .copy),
            Rule(scope: .subtitle, action: .copy),
        ]
    )

    static let episode = SourceFacts(
        kind: .episode,
        video: VideoFacts(absoluteIndex: 0, codec: "h264", width: 1920, height: 1080),
        audio: [
            AudioFacts(index: 1, absoluteIndex: 1, codec: "dts", profile: "DTS-HD MA", lossless: true, channels: 6, role: .main),
            AudioFacts(index: 2, absoluteIndex: 2, codec: "dts", lossless: false, channels: 6, role: .main, core: true),
            AudioFacts(index: 3, absoluteIndex: 3, codec: "ac3", lossless: false, channels: 2, role: .commentary),
        ],
        subtitles: [SubtitleFacts(index: 1, absoluteIndex: 4, codec: "hdmv_pgs_subtitle")]
    )

    @Test func theRecipeIsTheArgumentList() throws {
        let recipe = try RecipeResolver.resolve(Self.episode, with: Self.household)
        let arguments = recipe.ffmpegArguments(input: URL(fileURLWithPath: "/in/t00.mkv"), output: URL(fileURLWithPath: "/out/Part One.mkv"))
        #expect(arguments == [
            "-y", "-nostdin", "-hide_banner", "-loglevel", "error", "-progress", "pipe:1", "-nostats",
            "-i", "/in/t00.mkv",
            "-map", "0:0", "-map", "0:1", "-map", "0:3", "-map", "0:4",
            "-c:v:0", "copy",
            "-c:a:0", "flac", "-compression_level:a:0", "8",
            "-c:a:1", "aac", "-b:a:1", "160k", "-ac:a:1", "2",
            "-c:s:0", "copy",
            "-map_metadata", "0", "-map_chapters", "0", "-f", "matroska", "/out/Part One.mkv",
        ])
        #expect(recipe.tracks(for: [TrackMapping(feature: "commentary1", audio: 3)]) == [TrackMapping(feature: "commentary1", audio: 2)])
    }

    @Test func aReencodedVideoCarriesItsFilters() throws {
        let facts = SourceFacts(kind: .featurette, video: VideoFacts(absoluteIndex: 0, codec: "mpeg2video", width: 352, height: 288, interlaced: true))
        let recipe = try RecipeResolver.resolve(facts, with: Self.household)
        let arguments = recipe.ffmpegArguments(input: URL(fileURLWithPath: "/a"), output: URL(fileURLWithPath: "/b"))
        #expect(arguments.contains(["-c:v:0", "libx264", "-preset:v:0", "slow", "-crf:v:0", "22", "-pix_fmt:v:0", "yuv420p", "-filter:v:0", "yadif=deint=interlaced"]))
        #expect(Filter.scale(width: 1280, height: nil).ffmpegText == "scale=1280:-2")
        #expect(Filter.deinterlace(.always).ffmpegText == "yadif")
    }

    @Test func theLayoutIsVerifiedAgainstAProbe() throws {
        let recipe = try RecipeResolver.resolve(Self.episode, with: Self.household)
        let good = ProbedSource(streams: [
            ProbedStream(absoluteIndex: 0, kind: .video, codec: "h264"),
            ProbedStream(absoluteIndex: 1, kind: .audio, codec: "flac"),
            ProbedStream(absoluteIndex: 2, kind: .audio, codec: "aac"),
            ProbedStream(absoluteIndex: 3, kind: .subtitle, codec: "hdmv_pgs_subtitle"),
            ProbedStream(absoluteIndex: 4, kind: .attachment, codec: "ttf"),
        ])
        #expect(recipe.verify(against: good, source: Self.episode).isEmpty)

        let renumbered = ProbedSource(streams: [
            ProbedStream(absoluteIndex: 0, kind: .video, codec: "h264"),
            ProbedStream(absoluteIndex: 1, kind: .audio, codec: "aac"),
            ProbedStream(absoluteIndex: 2, kind: .audio, codec: "flac"),
            ProbedStream(absoluteIndex: 3, kind: .subtitle, codec: "hdmv_pgs_subtitle"),
            ProbedStream(absoluteIndex: 4, kind: .audio, codec: "ac3"),
        ])
        #expect(recipe.verify(against: renumbered, source: Self.episode) == [
            LayoutMismatch(position: 1, expected: "audio flac", found: "audio aac"),
            LayoutMismatch(position: 2, expected: "audio aac", found: "audio flac"),
            LayoutMismatch(position: 4, expected: "nothing", found: "audio ac3"),
        ])

        let short = ProbedSource(streams: [ProbedStream(absoluteIndex: 0, kind: .video, codec: "hevc")])
        #expect(recipe.verify(against: short, source: Self.episode).map(\.description) == [
            "stream 0: expected video h264, found video hevc",
            "stream 1: expected audio, found nothing",
            "stream 2: expected audio, found nothing",
            "stream 3: expected subtitle, found nothing",
        ])
    }

    @Test func progressBlocksBecomeReports() {
        let parser = ProgressParser()
        #expect(parser.consume("frame=10") == nil)
        #expect(parser.consume("fps=25.0") == nil)
        #expect(parser.consume("out_time_us=400000") == nil)
        #expect(parser.consume("speed=1.5x") == nil)
        #expect(parser.consume("progress=continue") == EncodeProgress(frame: 10, fps: 25, seconds: 0.4, speed: 1.5))
        #expect(parser.consume("out_time_ms=800000") == nil)
        #expect(parser.consume("speed=N/A") == nil)
        #expect(parser.consume("progress=end") == EncodeProgress(seconds: 0.8, finished: true))
    }

    @Test func linesAreSplitAcrossChunks() {
        let splitter = LineSplitter()
        #expect(splitter.append(Data("frame=1\nfps=".utf8)) == ["frame=1"])
        #expect(splitter.append(Data("2\r\nprogress=end\n".utf8)) == ["fps=2", "", "progress=end"])
        #expect(splitter.append(Data("tail".utf8)) == [])
        #expect(splitter.finish() == ["tail"])
    }
}
