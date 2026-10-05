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
