// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import Testing
@testable import SiloKit

struct BindingTests {
    /// A play-all title of four episodes, each a chapter.
    static let playAll = InputSpec(
        duration: 5990.4,
        chapters: [
            InputSpec.Chapter(index: 1, start: 0), InputSpec.Chapter(index: 2, start: 1497.6),
            InputSpec.Chapter(index: 3, start: 2995.2), InputSpec.Chapter(index: 4, start: 4492.8),
        ],
        streams: [
            InputSpec.Stream(index: 0, kind: .video, codec: "mpeg2video", width: 720, height: 576),
            InputSpec.Stream(index: 1, kind: .audio, codec: "ac3", channels: 2),
        ]
    )

    static func segment(_ source: String, _ from: Int? = nil, _ to: Int? = nil) -> Binding.Segment {
        Binding.Segment(source: source, chapters: from.map { Binding.ChapterSpan(from: $0, to: to ?? $0) })
    }

    @Test func anEpisodeOutOfAPlayAllTitleIsItsChapterSpan() throws {
        let joined = try JoinedMedia([Self.segment("title", 2)], specs: ["title": Self.playAll])
        #expect(joined.segments.count == 1)
        #expect(joined.segments[0].start == 1497.6)
        #expect(joined.segments[0].end == 2995.2)
        #expect(!joined.segments[0].isWhole)
        #expect(joined.duration == 1497.6)

        let last = try JoinedMedia([Self.segment("title", 4)], specs: ["title": Self.playAll])
        #expect(last.segments[0].end == 5990.4, "the last chapter runs to the source's end")
        let two = try JoinedMedia([Self.segment("title", 2, 3)], specs: ["title": Self.playAll])
        #expect(two.duration.map { abs($0 - 2995.2) < 0.0001 } == true, "a span of two chapters")
    }

    @Test func aFilmAcrossTwoDiscsIsBothWhole() throws {
        let joined = try JoinedMedia([Self.segment("one"), Self.segment("two")], specs: ["one": Self.playAll, "two": Self.playAll])
        #expect(joined.segments.map(\.source) == ["one", "two"])
        #expect(joined.segments.allSatisfy { $0.isWhole })
        #expect(joined.duration == 5990.4 * 2)
    }

    @Test func segmentsThatCannotBeJoinedAreRefused() {
        var dts = Self.playAll
        dts.streams[1].codec = "dts"
        #expect(throws: BindingError.layoutDiffers(segment: 2, stream: 1, first: "audio ac3", other: "audio dts")) {
            try JoinedMedia([Self.segment("one"), Self.segment("two")], specs: ["one": Self.playAll, "two": dts])
        }
        #expect(BindingError.layoutDiffers(segment: 2, stream: 1, first: "audio ac3", other: "audio dts").description
            == "segments cannot be joined: segment 2's stream 1 is audio dts, where segment 1's is audio ac3")
        #expect(throws: BindingError.unknownChapter(source: "title", chapter: 5)) {
            try JoinedMedia([Self.segment("title", 3, 5)], specs: ["title": Self.playAll])
        }
        #expect(throws: BindingError.spanBackwards(source: "title", from: 3, to: 2)) {
            try JoinedMedia([Self.segment("title", 3, 2)], specs: ["title": Self.playAll])
        }
        #expect(throws: BindingError.unknownSource("nothing")) {
            try JoinedMedia([Self.segment("nothing")], specs: [:])
        }
    }

    @Test func factsAreDerivedFromWhatWasObserved() throws {
        let spec = InputSpec(
            medium: .bluray,
            streams: [
                InputSpec.Stream(index: 0, kind: .video, codec: "hevc", width: 3840, height: 2160, frameRate: FrameRate(24000, 1001), transfer: "smpte2084", bitDepth: 10),
                InputSpec.Stream(index: 1, kind: .audio, codec: "truehd", channels: 8, language: LanguageTag(canonicalizing: "es-419")),
                InputSpec.Stream(index: 2, kind: .audio, codec: "ac3", channels: 6, coreOf: 1),
                InputSpec.Stream(index: 3, kind: .audio, codec: "ac3", channels: 2, title: "Commentary with the director"),
                InputSpec.Stream(index: 4, kind: .audio, codec: "aac", channels: 2, marks: [.descriptive]),
                InputSpec.Stream(index: 5, kind: .audio, codec: "aac", channels: 2, marks: [.commentary]),
                InputSpec.Stream(index: 6, kind: .subtitle, codec: "hdmv_pgs_subtitle", language: LanguageTag(canonicalizing: "zh-Hant"), marks: [.forced]),
                InputSpec.Stream(index: 7, kind: .other, codec: "ttf"),
            ],
            notes: [InputSpec.Note(stream: 2, text: "a core")]
        )
        let facts = SourceFacts(input: spec, roles: [5: .isolatedMusic], kind: .movie, profile: "mobile", duration: 100)
        #expect(facts.kind == .movie)
        #expect(facts.profile == "mobile")
        #expect(facts.format == .bluray, "the medium stands in for the format")
        #expect(facts.duration == 100)
        #expect(facts.video?.hdr == .hdr10)
        #expect(facts.video?.interlaced == false, "absent means progressive")
        #expect(facts.value(.videoFrameRate, for: .video) == .number(24000.0 / 1001.0))
        #expect(Condition(.videoFrameRate, .less(24)).holds(facts.value(.videoFrameRate, for: .video)))

        #expect(facts.audio.map(\.index) == [1, 2, 3, 4, 5])
        #expect(facts.audio.map(\.absoluteIndex) == [1, 2, 3, 4, 5])
        #expect(facts.audio[0].lossless)
        #expect(facts.audio[0].language == "es")
        #expect(facts.audio[0].region == "419")
        #expect(facts.audio[0].script == nil)
        #expect(facts.audio.map(\.core) == [false, true, false, false, false])
        #expect(facts.audio.map(\.role) == [.main, .main, .main, .descriptive, .isolatedMusic], "the feature map outranks the marks")
        #expect(facts.subtitles[0].language == "zh")
        #expect(facts.subtitles[0].script == "Hant")
        #expect(facts.subtitles[0].region == nil)
        #expect(facts.subtitles[0].forced)
        #expect(facts.hints.contains(FactHint(stream: 2, text: "a core")), "the producer's notes join the hints")
        #expect(facts.hints.contains(FactHint(stream: 3, text: "titled \"Commentary with the director\" but nothing marks it a commentary; assign it to a feature if it is one")))

        var sdr = spec
        sdr.streams[0].transfer = "bt709"
        #expect(SourceFacts(input: sdr).video?.hdr == nil)
        #expect(SourceFacts(input: spec).audio[4].role == .commentary, "the commentary mark, when no feature is mapped")
    }

    @Test func anAdjustmentReplacesADecisionAndRecordsWhatItReplaced() throws {
        let resolved = try RecipeResolver.resolve(.episode, with: .household)
        #expect(resolved.encoders == ["flac", "aac"])
        let kept = try resolved.adjusted(by: [Adjustment(kind: .audio, index: 1, action: .copy, note: "keep the Atmos object track")], mappings: [])
        let audio1 = try #require(kept.audio.first)
        #expect(audio1.action == .copy)
        #expect(audio1.rule == "lossless-main", "the decision still names its rule")
        #expect(audio1.adjusted == Adjusted(ruleAction: .encode(EncodeSettings(codec: "flac")), note: "keep the Atmos object track"))
        #expect(kept.encoders == ["aac"], "flac leaves the encoders when nothing else needs it")
        #expect(try resolved.adjusted(by: [], mappings: []) == resolved, "no adjustments, the rules' recipe")
    }

    @Test func aDroppedStreamRenumbersTheRestAndWarns() throws {
        let resolved = try RecipeResolver.resolve(.episode, with: .household)
        let mappings = [TrackMapping(feature: "commentary1", audio: 2)]
        let dropped = try resolved.adjusted(by: [Adjustment(kind: .audio, index: 2, action: .drop)], mappings: mappings)
        #expect(dropped.layout.streams(of: .audio).map(\.sourceIndex) == [1, 3])
        #expect(dropped.layout.streams(of: .audio).map(\.outputIndex) == [1, 2])
        #expect(dropped.warnings == ["feature commentary1 is mapped to audio 2, which this recipe drops"])
    }

    @Test func anAdjustmentThatNamesNothingOrTwiceIsRefused() throws {
        let resolved = try RecipeResolver.resolve(.episode, with: .household)
        #expect(throws: AdjustmentError.noSuchStream(kind: .audio, index: 4)) {
            try resolved.adjusted(by: [Adjustment(kind: .audio, index: 4, action: .copy)], mappings: [])
        }
        #expect(throws: AdjustmentError.adjustedTwice(kind: .audio, index: 1)) {
            try resolved.adjusted(by: [Adjustment(kind: .audio, index: 1, action: .copy), Adjustment(kind: .audio, index: 1, action: .drop)], mappings: [])
        }
        #expect(AdjustmentError.noSuchStream(kind: .audio, index: 4).description == "the recipe has no audio 4 to adjust")
    }
}
