// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloKit

/// A file as `ffprobe` describes it, reduced to what the encoder uses: what the silo's own producer
/// writes an input spec from, and what a finished output is checked against. The silo itself never
/// sees one — a producer describes a source in an input spec — so it lives here, beside `ffprobe`.
public struct ProbedSource: Hashable, Sendable, Codable {
    public var duration: Double?
    public var streams: [ProbedStream]
    /// In the order `ffprobe` lists them.
    public var chapters: [ProbedChapter]

    public init(duration: Double? = nil, streams: [ProbedStream], chapters: [ProbedChapter] = []) {
        self.duration = duration
        self.streams = streams
        self.chapters = chapters
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        streams = try container.decode([ProbedStream].self, forKey: .streams)
        chapters = try container.decodeIfPresent([ProbedChapter].self, forKey: .chapters) ?? []
    }

    public func streams(of kind: ProbedStream.Kind) -> [ProbedStream] {
        streams.filter { $0.kind == kind }
    }
}

/// A chapter as `ffprobe` lists it: where it starts, and its title when it has one.
public struct ProbedChapter: Hashable, Sendable, Codable {
    /// Seconds.
    public var start: Double
    public var title: String?

    public init(start: Double, title: String? = nil) {
        self.start = start
        self.title = title
    }
}

public struct ProbedStream: Hashable, Sendable, Codable {
    public enum Kind: String, Hashable, Sendable, Codable {
        case video, audio, subtitle, data, attachment, other
    }

    public var absoluteIndex: Int
    public var kind: Kind
    public var codec: String
    public var profile: String?
    public var width: Int?
    public var height: Int?
    public var frameRate: FrameRate?
    /// `ffprobe`'s `field_order`: `progressive`, or `tt`, `bb`, `tb`, `bt` for the interlaced ones.
    public var fieldOrder: String?
    /// `ffprobe`'s `color_transfer`: `smpte2084` is HDR10, `arib-std-b67` is HLG.
    public var colorTransfer: String?
    public var pixelFormat: String?
    public var bitsPerRawSample: Int?
    public var channels: Int?
    public var channelLayout: String?
    public var language: String?
    public var title: String?
    /// The disposition flags that are set: `default`, `forced`, `comment`, `visual_impaired`,
    /// `hearing_impaired` and the rest, as `ffprobe` names them.
    public var dispositions: Set<String>

    public init(
        absoluteIndex: Int, kind: Kind, codec: String, profile: String? = nil, width: Int? = nil,
        height: Int? = nil, frameRate: FrameRate? = nil, fieldOrder: String? = nil,
        colorTransfer: String? = nil, pixelFormat: String? = nil, bitsPerRawSample: Int? = nil,
        channels: Int? = nil, channelLayout: String? = nil, language: String? = nil,
        title: String? = nil, dispositions: Set<String> = []
    ) {
        self.absoluteIndex = absoluteIndex
        self.kind = kind
        self.codec = codec
        self.profile = profile
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.fieldOrder = fieldOrder
        self.colorTransfer = colorTransfer
        self.pixelFormat = pixelFormat
        self.bitsPerRawSample = bitsPerRawSample
        self.channels = channels
        self.channelLayout = channelLayout
        self.language = language
        self.title = title
        self.dispositions = dispositions
    }
}
