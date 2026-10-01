// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import Testing
@testable import SiloKit

struct InputSpecTests {
    /// A DVD title holding four episodes as chapters: interlaced MPEG-2, a main mix, a commentary and
    /// forced subtitles.
    static let playAll = """
    {
        "format": 1,
        "label": "Pyramids of Mars, disc 1, title 4",
        "medium": "dvd",
        "duration": 5990.4,
        "chapters": [
            { "index": 1, "start": 0, "title": "Part One" },
            { "index": 2, "start": 1497.6, "title": "Part Two" },
            { "index": 3, "start": 2995.2 },
            { "index": 4, "start": 4492.8 }
        ],
        "streams": [
            { "index": 0, "kind": "video", "codec": "mpeg2video", "width": 720, "height": 576,
              "frameRate": "25/1", "interlaced": true, "transfer": "bt470bg", "bitDepth": 8 },
            { "index": 1, "kind": "audio", "codec": "ac3", "channels": 2, "language": "en", "marks": ["default"] },
            { "index": 2, "kind": "audio", "codec": "ac3", "channels": 2, "language": "en",
              "title": "Commentary", "marks": ["commentary"] },
            { "index": 3, "kind": "subtitle", "codec": "dvd_subtitle", "language": "en", "marks": ["forced"] }
        ],
        "notes": [{ "stream": 2, "text": "the disc marks this track as the director's comments" }]
    }
    """

    static func read(_ json: String) throws(InputSpecError) -> InputSpec {
        try InputSpec.read(from: Data(json.utf8))
    }

    /// The play-all document with one change, made as text so the change is what a producer would
    /// actually send.
    static func playAll(replacing old: String, with new: String) -> String {
        precondition(playAll.contains(old), "the fixture has no \(old)")
        return playAll.replacingOccurrences(of: old, with: new)
    }

    @Test func aDiscTitleIsDescribed() throws {
        let spec = try Self.read(Self.playAll)
        #expect(spec.format == 1)
        #expect(spec.medium == .dvd)
        #expect(spec.chapters.map(\.index) == [1, 2, 3, 4])
        #expect(spec.chapters.map(\.start) == [0, 1497.6, 2995.2, 4492.8])
        #expect(spec.chapters[0].title == "Part One")
        #expect(spec.streams.map(\.index) == [0, 1, 2, 3])
        #expect(spec.streams.map(\.kind) == [.video, .audio, .audio, .subtitle])
        #expect(spec.streams[0].interlaced == true)
        #expect(spec.streams[0].frameRate == FrameRate(25))
        #expect(spec.streams[2].marks == [.commentary])
        #expect(spec.streams[3].marks == [.forced])
        #expect(spec.streams[1].language?.description == "en")
        #expect(spec.notes == [InputSpec.Note(stream: 2, text: "the disc marks this track as the director's comments")])
    }

    @Test func aSpecSurvivesItsOwnEncoding() throws {
        let spec = try Self.read(Self.playAll)
        let data = try JSONEncoder().encode(spec)
        #expect(try JSONDecoder().decode(InputSpec.self, from: data) == spec)
    }

    @Test func anExactFrameRate() throws {
        let spec = try Self.read(Self.playAll(replacing: "\"frameRate\": \"25/1\"", with: "\"frameRate\": \"24000/1001\""))
        #expect(spec.streams[0].frameRate == FrameRate(24000, 1001))
        #expect(spec.streams[0].frameRate?.description == "24000/1001")
        #expect(try Self.read(Self.playAll(replacing: "\"frameRate\": \"25/1\"", with: "\"frameRate\": 25")).streams[0].frameRate == FrameRate(25))
        #expect(FrameRate("25/1") == FrameRate("25"), "one rate, however it is spelt")
        #expect(FrameRate("0/0") == nil, "ffprobe's spelling of no rate")
        #expect(FrameRate("29.97") == nil, "a decimal is not exact")
    }

    @Test func aRegionalDub() throws {
        let spec = try Self.read(Self.playAll(replacing: "\"language\": \"en\", \"marks\": [\"default\"]", with: "\"language\": \"es-419\", \"marks\": [\"default\"]"))
        let language = try #require(spec.streams[1].language)
        #expect(language.description == "es-419")
        #expect(language.language == "es")
        #expect(language.region == "419")
        #expect(language.script == nil)
    }

    @Test func eachRefusalNamesTheFault() {
        func refusal(_ old: String, _ new: String) -> String? {
            do {
                _ = try Self.read(Self.playAll(replacing: old, with: new))
                return nil
            } catch {
                return error.description
            }
        }
        #expect(refusal("\"index\": 1, \"kind\": \"audio\"", "\"index\": 0, \"kind\": \"audio\"") == "stream index 0 is used twice")
        #expect(refusal("\"marks\": [\"forced\"]", "\"marks\": [\"karaoke\"]")
            == "streams[3].marks is \"karaoke\", which is not a mark: default, forced, commentary, descriptive or hearingImpaired")
        #expect(refusal("\"interlaced\": true", "\"intelaced\": true") == "streams[0].intelaced is not a field of an input spec")
        #expect(refusal("\"format\": 1", "\"format\": 2") == "input spec format 2 is newer than this silo reads (1)")
        #expect(refusal("\"format\": 1,", "") == "the input spec has no format")
        #expect(refusal("\"index\": 2, \"start\": 1497.6", "\"index\": 2, \"start\": 0") == "chapter 2 is out of order")
        #expect(refusal("\"index\": 3, \"start\": 2995.2", "\"index\": 2, \"start\": 2995.2") == "chapter 2 is listed twice")
        #expect(refusal("\"medium\": \"dvd\"", "\"medium\": \"vhs\"") == "medium is \"vhs\", which is not dvd, bluray or uhd")
        #expect(refusal("\"frameRate\": \"25/1\"", "\"frameRate\": \"29.97\"")
            == "streams[0].frameRate is \"29.97\", which is not a fraction such as 24000/1001, or a whole number")
        #expect(refusal("\"width\": 720, ", "") == "streams[0].width is required")
        #expect(refusal("\"channels\": 2, \"language\": \"en\", \"marks\"", "\"language\": \"en\", \"marks\"") == "streams[1].channels is required")
        #expect(refusal("\"kind\": \"subtitle\"", "\"kind\": \"caption\"") == "streams[3].kind is \"caption\", which is not video, audio, subtitle or other")
        #expect(refusal("\"interlaced\": true", "\"interlaced\": 1") == "streams[0].interlaced is 1, which is not true or false")
        #expect(refusal("\"title\": \"Commentary\", ", "\"title\": \"Commentary\", \"coreOf\": 9, ")
            == "stream 2's coreOf names 9, which is not another audio stream of this spec")
        #expect(refusal("\"title\": \"Commentary\", ", "\"title\": \"Commentary\", \"coreOf\": 2, ")
            == "stream 2's coreOf names 2, which is not another audio stream of this spec")
    }

    @Test func aLanguageMustBeCanonical() {
        func refusal(_ tag: String) -> String? {
            do {
                _ = try Self.read(Self.playAll(replacing: "\"language\": \"en\", \"marks\": [\"default\"]", with: "\"language\": \"\(tag)\", \"marks\": [\"default\"]"))
                return nil
            } catch {
                return error.description
            }
        }
        #expect(refusal("eng") == "streams[1].language is eng, which is not canonical; write en")
        #expect(refusal("en-gb") == "streams[1].language is en-gb, which is not canonical; write en-GB")
        #expect(refusal("und") == "streams[1].language is und; an unknown language is no tag")
        #expect(refusal("not a tag") == "streams[1].language is \"not a tag\", which is not a BCP 47 language tag")
        #expect(refusal("en-GB") == nil)
        #expect(refusal("zh-Hant") == nil)
        #expect(refusal("yue") == nil, "a language with no two-letter code keeps its three letters")
    }

    @Test func languageTagsAreCanonicalised() {
        func canonical(_ text: String) -> String? { LanguageTag(canonicalizing: text)?.description }
        #expect(canonical("ENG") == "en")
        #expect(canonical("ger") == "de", "a bibliographic code")
        #expect(canonical("deu") == "de", "a terminological code")
        #expect(canonical("eng-gb") == "en-GB")
        #expect(canonical("zh-hant-tw") == "zh-Hant-TW")
        #expect(canonical("es-419") == "es-419")
        #expect(canonical("sl-rozaj-biske") == "sl-rozaj-biske", "variants")
        #expect(canonical("en-a-bbb-x-Private") == "en-a-bbb-x-private", "an extension and private use")
        #expect(canonical("zh-yue") == nil, "an extended language subtag is written as the language")
        #expect(canonical("x-private") == nil, "private use alone names no language")
        #expect(canonical("en--GB") == nil)
        #expect(canonical("") == nil)
        let tag = LanguageTag(canonicalizing: "zh-Hant-TW")
        #expect(tag?.language == "zh")
        #expect(tag?.script == "Hant")
        #expect(tag?.region == "TW")
    }
}
