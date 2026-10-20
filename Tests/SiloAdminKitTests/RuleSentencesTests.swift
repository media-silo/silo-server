// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import SiloAdminKit
import SiloKit
import Testing

/// Rules as the console's form reads them to a person.
struct RuleSentencesTests {
    @Test func aRuleReadsAsIfAndThenWhere() {
        let rule = Rule(
            scope: .video,
            conditions: [Condition(.videoInterlaced, .equal("true")), Condition(.videoWidth, .less(1280))],
            action: .encode(EncodeSettings(codec: "libx265", crf: 20, filters: [.deinterlace(.auto)]))
        )
        #expect(
            rule.reading(afterOthers: false) == [
                [Rule.Clause("IF", "interlaced is true"), Rule.Clause("AND", "width < 1280")],
                [
                    Rule.Clause("THEN", "encode"), Rule.Clause("WHERE", "codec is hevc"),
                    Rule.Clause("AND", "crf is 20"),
                    Rule.Clause("AND", "deinterlace is auto"),
                ],
            ]
        )
        let audio = Rule(
            scope: .audio,
            conditions: [Condition(.audioLanguage, .oneOf(["en", "fr"])), Condition(.kind, .equal("movie"))],
            action: .encode(EncodeSettings(codec: "aac", bitrate: "96k", channels: 2))
        )
        #expect(
            audio.reading(afterOthers: false) == [
                [Rule.Clause("IF", "language one of en, fr"), Rule.Clause("AND", "kind is movie")],
                [
                    Rule.Clause("THEN", "encode"), Rule.Clause("WHERE", "codec is aac"),
                    Rule.Clause("AND", "bitrate is 96k"),
                    Rule.Clause("AND", "channels is 2"),
                ],
            ]
        )
    }

    @Test func aLaterRuleIsReachedOnlyOtherwise() {
        let conditional = Rule(scope: .audio, conditions: [Condition(.audioRole, .equal("commentary"))], action: .drop)
        #expect(
            conditional.reading(afterOthers: true) == [
                [Rule.Clause("OTHERWISE IF", "role is commentary")], [Rule.Clause("THEN", "drop")],
            ]
        )
        let unconditional = Rule(scope: .subtitle, action: .copy)
        #expect(unconditional.reading(afterOthers: false) == [[Rule.Clause("ALWAYS", "copy")]])
        #expect(unconditional.reading(afterOthers: true) == [[Rule.Clause("OTHERWISE", "copy")]])
    }

    @Test func testsAreNamedInWordsAndFactsWithoutTheirScope() {
        #expect(
            ["is", "ne", "in", "lt", "le", "gt", "ge"].map(Condition.Test.label(of:))
                == ["is", "is not", "one of", "<", "≤", ">", "≥"]
        )
        #expect(FactKey.videoCodec.name(in: .video) == "codec")
        #expect(FactKey.format.name(in: .video) == "format")
    }

    @Test func aKindIsOfferedFromTheTypesSmdKitNames() {
        #expect(
            FactKey.kind.suggestedValues == [
                "episode", "movie", "featurette", "behindTheScenes", "deletedScene", "interview", "trailer", "scene",
                "short", "clip",
                "themeSong", "themeVideo",
            ]
        )
        #expect(FactKey.kind.values == nil, "offered beside a field that takes any type")
        #expect(FactKey.extra.values == ["true", "false"])
    }

    @Test func anEncodeIsOfferedByCodecAndWritesItsEncoder() {
        #expect(Scope.video.codecs.first?.codec == "h264")
        #expect(Scope.audio.codecs.first?.codec == "aac")
        #expect(Scope.subtitle.codecs.first?.codec == "subrip")
        #expect(Scope.video.encoder(forCodec: "hevc") == "libx265")
        #expect(Scope.video.codec(ofEncoder: "libx265") == "hevc")
        #expect(
            Scope.video.encoder(forCodec: "hevc_videotoolbox") == "hevc_videotoolbox",
            "any other encoder is taken as written"
        )
        for scope in Scope.allCases {
            let fact: FactKey =
                switch scope {
                case .video: .videoCodec
                case .audio: .audioCodec
                case .subtitle: .subtitleCodec
                }
            #expect(
                scope.codecs.allSatisfy { fact.suggestedValues.contains($0.codec) },
                "an encode's codecs are named as its conditions name them"
            )
        }
    }

    @Test func anEncodeTakesTheSettingsItsCodecHas() {
        #expect(Scope.video.settings(forCodec: "hevc") == [.preset, .crf, .bitrate, .pixelFormat])
        #expect(Scope.audio.settings(forCodec: "aac") == [.bitrate, .channels])
        #expect(Scope.audio.settings(forCodec: "flac") == [.channels], "a lossless codec has no bitrate")
        #expect(Scope.audio.settings(forCodec: "pcm_s24le") == [.channels])
        #expect(Scope.subtitle.settings(forCodec: "subrip").isEmpty)
    }
}
