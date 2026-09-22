// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloKit
import Testing
@testable import Encoder

struct ProbeParsingTests {
    /// The shape `ffprobe -print_format json -show_format -show_streams` writes, trimmed to the
    /// fields read and one of each thing the reader has to cope with.
    static let document = """
    {
        "streams": [
            {
                "index": 0, "codec_name": "h264", "codec_type": "video", "profile": "High",
                "width": 1920, "height": 1080, "pix_fmt": "yuv420p", "field_order": "progressive",
                "color_transfer": "bt709", "r_frame_rate": "25/1", "avg_frame_rate": "25/1",
                "bits_per_raw_sample": "8",
                "disposition": { "default": 1, "forced": 0, "comment": 0 },
                "tags": { "language": "eng" }
            },
            {
                "index": 1, "codec_name": "dts", "codec_type": "audio", "profile": "DTS-HD MA",
                "channels": 6, "channel_layout": "5.1(side)",
                "r_frame_rate": "0/0", "avg_frame_rate": "0/0",
                "disposition": { "default": 1, "comment": 0 },
                "tags": { "language": "eng", "title": "Surround" }
            },
            {
                "index": 2, "codec_name": "ac3", "codec_type": "audio", "channels": 2,
                "disposition": { "default": 0, "comment": 1 },
                "tags": { "LANGUAGE": "eng", "TITLE": "Commentary" }
            },
            {
                "index": 3, "codec_name": "hdmv_pgs_subtitle", "codec_type": "subtitle",
                "disposition": { "default": 0, "forced": 1 },
                "tags": { "language": "eng" }
            },
            { "index": 4, "codec_type": "attachment", "codec_name": "ttf" }
        ],
        "format": { "filename": "t.mkv", "duration": "1500.320000" }
    }
    """

    @Test func theDocumentIsReducedToWhatFactsNeed() throws {
        let probed = try ProbedSource(ffprobeJSON: Data(Self.document.utf8))
        #expect(probed.duration == 1500.32)
        #expect(probed.streams.count == 5)
        #expect(probed.streams[0] == ProbedStream(
            absoluteIndex: 0, kind: .video, codec: "h264", profile: "High", width: 1920, height: 1080,
            frameRate: 25, fieldOrder: "progressive", colorTransfer: "bt709", pixelFormat: "yuv420p",
            bitsPerRawSample: 8, language: "eng", dispositions: ["default"]
        ))
        #expect(probed.streams[1].frameRate == nil, "0/0 is no rate, not a rate of zero")
        #expect(probed.streams[1].profile == "DTS-HD MA")
        #expect(probed.streams[1].channelLayout == "5.1(side)")
        #expect(probed.streams[2].language == "eng", "tags come in either case")
        #expect(probed.streams[2].title == "Commentary")
        #expect(probed.streams[2].dispositions == ["comment"])
        #expect(probed.streams[3].dispositions == ["forced"])
        #expect(probed.streams[4].kind == .attachment)

        let facts = SourceFacts(probe: probed)
        #expect(facts.audio.map(\.role) == [.main, .commentary])
        #expect(facts.audio.map(\.lossless) == [true, false])
        #expect(facts.subtitles.map(\.forced) == [true])
    }

    @Test func aFractionalRateIsAFraction() throws {
        let json = """
        {"streams":[{"index":0,"codec_type":"video","codec_name":"mpeg2video","avg_frame_rate":"30000/1001","r_frame_rate":"30000/1001","field_order":"tt"}]}
        """
        let probed = try ProbedSource(ffprobeJSON: Data(json.utf8))
        #expect(abs(probed.streams[0].frameRate! - 29.97) < 0.001)
        #expect(SourceFacts(probe: probed).video?.interlaced == true)
    }

    @Test func somethingThatIsNotFFprobesOutputIsRefused() {
        #expect(throws: ToolError.self) { try ProbedSource(ffprobeJSON: Data("not json".utf8)) }
    }
}
