// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SmdKit

/// What a rule may test about a file. Facts are derived — from the input spec its producer observed,
/// from the binding that says what the file is, and from the output being made — and a rule reads
/// them and never writes them. `Silo.md`, principle 3; `Ingestion.md`, *Observed and derived*.
///
/// The derived facts, `lossless`, `role` and `core`, are each derived in exactly one place, so that
/// every caller agrees.
public struct SourceFacts: Hashable, Sendable, Codable {
    /// The item's kind from the binding: episode, movie, featurette and the other extra types. Nil
    /// when nothing says, which is why a ruleset's catch-alls are written last.
    public var kind: EntryType?
    /// The profile the file is being made into. Nil for the unqualified presentation.
    public var profile: String?
    public var format: SourceFormat?
    /// Seconds.
    public var duration: Double?
    public var video: VideoFacts?
    /// In the file's stream order; `index` counts from one among audio streams.
    public var audio: [AudioFacts]
    public var subtitles: [SubtitleFacts]
    /// Things the derivation noticed but did not act on — a title that says "commentary" on a
    /// stream nothing else calls one, a note the producer left on a stream.
    /// Shown to a person; never a fact a rule can test.
    public var hints: [FactHint]

    public init(
        kind: EntryType? = nil,
        profile: String? = nil,
        format: SourceFormat? = nil,
        duration: Double? = nil,
        video: VideoFacts? = nil,
        audio: [AudioFacts] = [],
        subtitles: [SubtitleFacts] = [],
        hints: [FactHint] = []
    ) {
        self.kind = kind
        self.profile = profile
        self.format = format
        self.duration = duration
        self.video = video
        self.audio = audio
        self.subtitles = subtitles
        self.hints = hints
    }
}

public enum SourceFormat: String, Hashable, Sendable, Codable, CaseIterable {
    case dvd, bluray, uhd
}

public enum HDRKind: String, Hashable, Sendable, Codable, CaseIterable {
    case hdr10, hlg
}

public enum StreamKind: String, Hashable, Sendable, Codable, CaseIterable {
    case video, audio, subtitle
}

/// What an audio stream is *for*, which is the question "is this a commentary" really asks.
public enum AudioRole: String, Hashable, Sendable, Codable, CaseIterable {
    case main, commentary, isolatedMusic, descriptive, other
}

public struct VideoFacts: Hashable, Sendable, Codable {
    /// `ffprobe`'s index across every stream in the file.
    public var absoluteIndex: Int
    public var codec: String
    public var width: Int
    public var height: Int
    public var frameRate: Double?
    public var interlaced: Bool
    public var hdr: HDRKind?
    public var bitDepth: Int?

    public init(
        absoluteIndex: Int, codec: String, width: Int, height: Int, frameRate: Double? = nil,
        interlaced: Bool = false, hdr: HDRKind? = nil, bitDepth: Int? = nil
    ) {
        self.absoluteIndex = absoluteIndex
        self.codec = codec
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.interlaced = interlaced
        self.hdr = hdr
        self.bitDepth = bitDepth
    }
}

public struct AudioFacts: Hashable, Sendable, Codable {
    /// From one, among the file's audio streams: the way a player's menu counts and the way
    /// `<track audio="n">` counts.
    public var index: Int
    public var absoluteIndex: Int
    public var codec: String
    /// The codec's profile as `ffprobe` names it — "DTS-HD MA" is the one that matters.
    public var profile: String?
    public var lossless: Bool
    public var channels: Int
    public var layout: String?
    /// The primary language subtag of the stream's BCP 47 tag: `en`, `es`.
    public var language: String?
    /// The script subtag: `Hant`.
    public var script: String?
    /// The region subtag: `419`, `BR`.
    public var region: String?
    public var role: AudioRole
    /// The lossy core a producer extracted from inside a lossless track, kept as a stream of its
    /// own. The same audio again, smaller and worse; a rule may want to drop it.
    public var core: Bool
    public var title: String?

    public init(
        index: Int, absoluteIndex: Int, codec: String, profile: String? = nil, lossless: Bool,
        channels: Int, layout: String? = nil, language: String? = nil, script: String? = nil,
        region: String? = nil, role: AudioRole = .main, core: Bool = false, title: String? = nil
    ) {
        self.index = index
        self.absoluteIndex = absoluteIndex
        self.codec = codec
        self.profile = profile
        self.lossless = lossless
        self.channels = channels
        self.layout = layout
        self.language = language
        self.script = script
        self.region = region
        self.role = role
        self.core = core
        self.title = title
    }
}

public struct SubtitleFacts: Hashable, Sendable, Codable {
    public var index: Int
    public var absoluteIndex: Int
    public var codec: String
    /// The primary language subtag, as for audio.
    public var language: String?
    public var script: String?
    public var region: String?
    public var forced: Bool
    public var hearingImpaired: Bool
    public var title: String?

    public init(
        index: Int, absoluteIndex: Int, codec: String, language: String? = nil, script: String? = nil,
        region: String? = nil, forced: Bool = false, hearingImpaired: Bool = false, title: String? = nil
    ) {
        self.index = index
        self.absoluteIndex = absoluteIndex
        self.codec = codec
        self.language = language
        self.script = script
        self.region = region
        self.forced = forced
        self.hearingImpaired = hearingImpaired
        self.title = title
    }
}

public struct FactHint: Hashable, Sendable, Codable, CustomStringConvertible {
    /// The stream's absolute index, when the hint is about one.
    public var stream: Int?
    public var text: String

    public init(stream: Int? = nil, text: String) {
        self.stream = stream
        self.text = text
    }

    public var description: String {
        stream.map { "stream \($0): \(text)" } ?? text
    }
}

// MARK: - Derivation

extension AudioFacts {
    /// Whether a codec carries the audio without loss. One function, so that every caller
    /// agrees. DTS is lossless only in its Master Audio profile; its core, and the DTS-HD High
    /// Resolution profile, are not.
    public static func isLossless(codec: String, profile: String?) -> Bool {
        switch codec.lowercased() {
        case "truehd", "mlp", "flac", "alac", "wavpack", "tta", "ape", "mlp_dvd":
            return true
        case let name where name.hasPrefix("pcm_"):
            return true
        case "dts":
            return profile?.uppercased().contains("DTS-HD MA") ?? false
        default:
            return false
        }
    }
}

extension AudioFacts {
    /// The stream's language as one tag again, for a person to read: `es-419`.
    public var languageTag: String? {
        language.map { ([$0] + [script, region].compactMap { $0 }).joined(separator: "-") }
    }
}

extension SubtitleFacts {
    public var languageTag: String? {
        language.map { ([$0] + [script, region].compactMap { $0 }).joined(separator: "-") }
    }
}
