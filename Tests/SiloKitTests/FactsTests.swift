// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import Testing
@testable import SiloKit

struct FactsTests {
    @Test(arguments: [
        ("truehd", nil, true), ("mlp", nil, true), ("flac", nil, true), ("alac", nil, true),
        ("pcm_s24le", nil, true), ("pcm_bluray", nil, true),
        ("dts", "DTS-HD MA", true), ("dts", "DTS-HD HRA", false), ("dts", "DTS", false), ("dts", nil, false),
        ("ac3", nil, false), ("eac3", nil, false), ("aac", "LC", false), ("opus", nil, false),
    ] as [(String, String?, Bool)])
    func losslessIsAFunctionOfCodecAndProfile(codec: String, profile: String?, lossless: Bool) {
        #expect(AudioFacts.isLossless(codec: codec, profile: profile) == lossless)
    }

    @Test func theRoleComesFromTheMostAuthoritativeSource() {
        let marked = MakeMKVTrack(kind: .audio, flags: 1)
        let plain = MakeMKVTrack(kind: .audio)
        #expect(AudioRole.derive(assigned: .isolatedMusic, makeMKV: marked, dispositions: ["comment"]) == .isolatedMusic)
        #expect(AudioRole.derive(assigned: nil, makeMKV: marked, dispositions: []) == .commentary)
        #expect(AudioRole.derive(assigned: nil, makeMKV: MakeMKVTrack(kind: .audio, flags: 4), dispositions: []) == .descriptive)
        #expect(AudioRole.derive(assigned: nil, makeMKV: plain, dispositions: ["comment"]) == .commentary)
        #expect(AudioRole.derive(assigned: nil, makeMKV: plain, dispositions: ["visual_impaired"]) == .descriptive)
        #expect(AudioRole.derive(assigned: nil, makeMKV: nil, dispositions: ["default"]) == .main)
    }

    @Test func factsAreMergedFromTheProbeTheScanAndTheAssignment() {
        let probe = ProbedSource(duration: 1500.25, streams: [
            ProbedStream(absoluteIndex: 0, kind: .video, codec: "h264", width: 1920, height: 1080, frameRate: 25, fieldOrder: "tt", colorTransfer: "smpte2084", bitsPerRawSample: 10),
            ProbedStream(absoluteIndex: 1, kind: .audio, codec: "dts", profile: "DTS-HD MA", channels: 6, channelLayout: "5.1", language: "eng"),
            ProbedStream(absoluteIndex: 2, kind: .audio, codec: "dts", channels: 6, language: "eng"),
            ProbedStream(absoluteIndex: 3, kind: .audio, codec: "ac3", channels: 2, title: "Commentary with the director"),
            ProbedStream(absoluteIndex: 4, kind: .subtitle, codec: "hdmv_pgs_subtitle", language: "eng"),
            ProbedStream(absoluteIndex: 5, kind: .subtitle, codec: "hdmv_pgs_subtitle", language: "eng", dispositions: ["forced"]),
            ProbedStream(absoluteIndex: 6, kind: .attachment, codec: "ttf"),
        ])
        let scan = MakeMKVFacts(format: .bluray, tracks: [
            MakeMKVTrack(kind: .video, codecId: "V_MPEG4/ISO/AVC"),
            MakeMKVTrack(kind: .audio, codecId: "A_DTS", language: "eng", channels: 6),
            MakeMKVTrack(kind: .audio, codecId: "A_DTS", language: "eng", channels: 6, core: true),
            MakeMKVTrack(kind: .audio, codecId: "A_AC3", language: "eng", channels: 2),
            MakeMKVTrack(kind: .subtitle, language: "eng"),
            MakeMKVTrack(kind: .subtitle, language: "eng", forcedOnly: true),
        ])

        let facts = SourceFacts(probe: probe, makeMKV: scan, roles: [:], kind: .episode, profile: "mobile")
        #expect(facts.format == .bluray)
        #expect(facts.duration == 1500.25)
        #expect(facts.video == VideoFacts(absoluteIndex: 0, codec: "h264", width: 1920, height: 1080, frameRate: 25, interlaced: true, hdr: .hdr10, bitDepth: 10))
        #expect(facts.audio.map(\.index) == [1, 2, 3])
        #expect(facts.audio.map(\.absoluteIndex) == [1, 2, 3])
        #expect(facts.audio.map(\.lossless) == [true, false, false])
        #expect(facts.audio.map(\.core) == [false, true, false])
        #expect(facts.audio.map(\.role) == [.main, .main, .main])
        #expect(facts.audio[2].language == "eng", "the scan's language fills what the file did not say")
        #expect(facts.subtitles.map(\.forced) == [false, true])
        #expect(facts.hints == [FactHint(stream: 3, text: "titled \"Commentary with the director\" but nothing marks it a commentary; assign it to a feature if it is one")])

        let assigned = SourceFacts(probe: probe, makeMKV: scan, roles: [3: .commentary], kind: .episode)
        #expect(assigned.audio[2].role == .commentary)
        #expect(assigned.hints.isEmpty)
    }

    @Test func aScanWhoseCountsDoNotMatchIsNotApplied() {
        let probe = ProbedSource(streams: [
            ProbedStream(absoluteIndex: 0, kind: .video, codec: "h264", width: 720, height: 576),
            ProbedStream(absoluteIndex: 1, kind: .audio, codec: "ac3", channels: 2),
        ])
        let scan = MakeMKVFacts(format: .dvd, tracks: [
            MakeMKVTrack(kind: .audio, language: "eng", flags: 1),
            MakeMKVTrack(kind: .audio, language: "fra"),
        ])
        let facts = SourceFacts(probe: probe, makeMKV: scan)
        #expect(facts.audio[0].role == .main)
        #expect(facts.audio[0].language == nil)
        #expect(facts.format == .dvd, "the disc format is not a per-track fact and still applies")
        #expect(facts.hints.map(\.text) == ["MakeMKV kept 2 audio tracks but the file has 1; the scan's audio facts were not applied"])
    }

    @Test func anAbsentFactMatchesNothingExceptNotEqual() {
        let facts = SourceFacts(video: VideoFacts(absoluteIndex: 0, codec: "h264", width: 1920, height: 1080))
        #expect(Condition(.videoHDR, .equal("hdr10")).holds(facts.value(.videoHDR, for: .video)) == false)
        #expect(Condition(.videoHDR, .notEqual("hdr10")).holds(facts.value(.videoHDR, for: .video)) == true)
        #expect(Condition(.kind, .oneOf(["episode"])).holds(facts.value(.kind, for: .video)) == false)
        #expect(Condition(.duration, .less(100)).holds(facts.value(.duration, for: .video)) == false)
        #expect(Condition(.videoWidth, .greaterOrEqual(1920)).holds(facts.value(.videoWidth, for: .video)) == true)
        #expect(Condition(.videoWidth, .equal("1920")).holds(facts.value(.videoWidth, for: .video)) == true)
        #expect(Condition(.videoInterlaced, .equal("false")).holds(facts.value(.videoInterlaced, for: .video)) == true)
        #expect(Condition(.audioCodec, .equal("ac3")).holds(facts.value(.audioCodec, for: .audio(1))) == false)
    }
}
