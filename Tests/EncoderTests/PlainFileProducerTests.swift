// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloKit
import Testing
@testable import Encoder

struct PlainFileProducerTests {
    @Test func aProbedFileIsDescribed() throws {
        let spec = InputSpec(probe: try ProbedSource(ffprobeJSON: Data(ProbeParsingTests.document.utf8)))
        #expect(spec.format == 1)
        #expect(spec.medium == nil, "a plain file names no medium")
        #expect(spec.notes.isEmpty)
        #expect(spec.duration == 1500.32)
        #expect(spec.chapters == [InputSpec.Chapter(index: 1, start: 0, title: "Part One"), InputSpec.Chapter(index: 2, start: 750)])

        let video = spec.streams[0]
        #expect(video == InputSpec.Stream(
            index: 0, kind: .video, codec: "h264", profile: "High", width: 1920, height: 1080, frameRate: 25,
            interlaced: false, transfer: "bt709", bitDepth: 8, language: LanguageTag(canonicalizing: "en"), marks: [.default]
        ))
        #expect(spec.streams[1].kind == .audio)
        #expect(spec.streams[1].channels == 6)
        #expect(spec.streams[1].layout == "5.1(side)")
        #expect(spec.streams[1].frameRate == nil, "a rate is the video's alone")
        #expect(spec.streams[2].marks == [.commentary])
        #expect(spec.streams[2].language?.description == "en", "an ISO 639-2 code becomes the shortest code")
        #expect(spec.streams[3].marks == [.forced])
        #expect(spec.streams[4].kind == .other, "an attachment is a stream no rule decides")
        #expect(spec.streams.allSatisfy { $0.coreOf == nil })
        try spec.validate()
    }

    @Test func dispositionsBecomeMarks() {
        #expect(InputSpec.Stream.marks(["default", "forced", "hearing_impaired"]) == [.default, .forced, .hearingImpaired])
        #expect(InputSpec.Stream.marks(["comment"]) == [.commentary])
        #expect(InputSpec.Stream.marks(["visual_impaired"]) == [.descriptive])
        #expect(InputSpec.Stream.marks(["descriptions"]) == [.descriptive])
        #expect(InputSpec.Stream.marks(["dub", "original"]).isEmpty, "a disposition with no mark is not one")
    }

    @Test func fieldOrderDecidesInterlacing() {
        func interlaced(_ fieldOrder: String?) -> Bool? {
            InputSpec.Stream(probed: ProbedStream(absoluteIndex: 0, kind: .video, codec: "mpeg2video", width: 720, height: 576, fieldOrder: fieldOrder)).interlaced
        }
        #expect(interlaced("tt") == true)
        #expect(interlaced("bb") == true)
        #expect(interlaced("tb") == true)
        #expect(interlaced("bt") == true)
        #expect(interlaced("progressive") == false)
        #expect(interlaced("unknown") == false, "a field order that says nothing is not interlaced")
        #expect(interlaced(nil) == nil)
    }

    @Test func languagesTheProbeReportsAreMadeCanonical() {
        func language(_ tag: String?) -> String? {
            InputSpec.Stream(probed: ProbedStream(absoluteIndex: 1, kind: .audio, codec: "ac3", channels: 2, language: tag)).language?.description
        }
        #expect(language("fre") == "fr", "a bibliographic code")
        #expect(language("fra") == "fr", "a terminological code")
        #expect(language("es-419") == "es-419", "a BCP 47 tag, as Matroska carries one")
        #expect(language("pt-br") == "pt-BR")
        #expect(language("zh-Hant") == "zh-Hant")
        #expect(language("und") == nil, "an unknown language is no tag")
        #expect(language("not a tag") == nil)
        #expect(language(nil) == nil)
    }

    @Test func chaptersThatDoNotAdvanceAreDropped() {
        let probe = ProbedSource(streams: [], chapters: [ProbedChapter(start: 0), ProbedChapter(start: 0), ProbedChapter(start: 10)])
        #expect(InputSpec(probe: probe).chapters.map(\.start) == [0, 10])
        #expect(InputSpec(probe: probe).chapters.map(\.index) == [1, 2])
    }
}
