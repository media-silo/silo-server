// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SmdKit

/// What a rule may test about a file. Facts are discovered — by `ffprobe`, by MakeMKV's scan of
/// the title the file was ripped from, and by the assignment that says what the file is — and a
/// rule reads them and never writes them. `Silo.md`, principle 3.
///
/// The two derived facts, `lossless` and `role`, are each derived in exactly one place here, so
/// that the tool at rip time, the resolver at registration and the node at encode time agree.
public struct SourceFacts: Hashable, Sendable, Codable {
    /// The item's kind from the assignment: episode, movie, featurette and the other extra types.
    /// Nil while a file is unassigned, which is why a ruleset's catch-alls are written last.
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
    /// stream nothing else calls one, a MakeMKV scan whose track count does not match the file.
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
    public var language: String?
    public var role: AudioRole
    /// The lossy core MakeMKV can extract from inside a lossless track, kept as a stream of its
    /// own. The same audio again, smaller and worse; a rule may want to drop it.
    public var core: Bool
    public var title: String?

    public init(
        index: Int, absoluteIndex: Int, codec: String, profile: String? = nil, lossless: Bool,
        channels: Int, layout: String? = nil, language: String? = nil, role: AudioRole = .main,
        core: Bool = false, title: String? = nil
    ) {
        self.index = index
        self.absoluteIndex = absoluteIndex
        self.codec = codec
        self.profile = profile
        self.lossless = lossless
        self.channels = channels
        self.layout = layout
        self.language = language
        self.role = role
        self.core = core
        self.title = title
    }
}

public struct SubtitleFacts: Hashable, Sendable, Codable {
    public var index: Int
    public var absoluteIndex: Int
    public var codec: String
    public var language: String?
    public var forced: Bool
    public var hearingImpaired: Bool
    public var title: String?

    public init(
        index: Int, absoluteIndex: Int, codec: String, language: String? = nil,
        forced: Bool = false, hearingImpaired: Bool = false, title: String? = nil
    ) {
        self.index = index
        self.absoluteIndex = absoluteIndex
        self.codec = codec
        self.language = language
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

// MARK: - What ffprobe saw

/// A file as `ffprobe` describes it, reduced to what facts are derived from. The encoder fills
/// this from `ffprobe`'s JSON; it is here rather than there so that facts can be derived, and
/// tested, from a literal value with no `ffprobe` on the machine.
public struct ProbedSource: Hashable, Sendable, Codable {
    public var duration: Double?
    public var streams: [ProbedStream]

    public init(duration: Double? = nil, streams: [ProbedStream]) {
        self.duration = duration
        self.streams = streams
    }

    public func streams(of kind: ProbedStream.Kind) -> [ProbedStream] {
        streams.filter { $0.kind == kind }
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
    public var frameRate: Double?
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
        height: Int? = nil, frameRate: Double? = nil, fieldOrder: String? = nil,
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

// MARK: - What MakeMKV saw

/// What MakeMKV recorded about the title a file was ripped from, reduced to what facts are derived
/// from. The ingestion tool builds one from MakeMKVKit's `Track`; this package does not import
/// MakeMKVKit, so that a node with no disc drive never resolves it.
///
/// `tracks` are the tracks the rip *kept*, in the order MakeMKV listed them, one list for every
/// kind. That order is the order the ripped file's streams of that kind come in, which is how a
/// MakeMKV track is matched to a probed stream; a count that does not match is reported as a
/// hint and the scan's facts are not applied.
public struct MakeMKVFacts: Hashable, Sendable, Codable {
    public var format: SourceFormat?
    public var tracks: [MakeMKVTrack]

    public init(format: SourceFormat? = nil, tracks: [MakeMKVTrack]) {
        self.format = format
        self.tracks = tracks
    }

    public func tracks(of kind: StreamKind) -> [MakeMKVTrack] {
        tracks.filter { $0.kind == kind }
    }
}

public struct MakeMKVTrack: Hashable, Sendable, Codable {
    public var kind: StreamKind
    public var codecId: String?
    public var language: String?
    public var channels: Int?
    /// MakeMKV's stream flags, raw. Bit 1 and bit 2 are the disc's own "director's comments"
    /// marks; bit 4 is "for the visually impaired".
    public var flags: Int
    public var core: Bool
    public var forcedOnly: Bool

    public init(
        kind: StreamKind, codecId: String? = nil, language: String? = nil, channels: Int? = nil,
        flags: Int = 0, core: Bool = false, forcedOnly: Bool = false
    ) {
        self.kind = kind
        self.codecId = codecId
        self.language = language
        self.channels = channels
        self.flags = flags
        self.core = core
        self.forcedOnly = forcedOnly
    }

    public var isCommentary: Bool { flags & 0b11 != 0 }
    public var isDescriptive: Bool { flags & 0b100 != 0 }
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

extension AudioRole {
    /// The role of a stream, from its sources in order of authority: what the assignment maps it
    /// to; what MakeMKV's stream flags say the disc marked it; what the file's own disposition
    /// says. None of them speaking, it is the main mix. A title that merely *says* "commentary"
    /// is not consulted here; `SourceFacts` reports it as a hint.
    public static func derive(assigned: AudioRole?, makeMKV: MakeMKVTrack?, dispositions: Set<String>) -> AudioRole {
        if let assigned { return assigned }
        if let makeMKV {
            if makeMKV.isCommentary { return .commentary }
            if makeMKV.isDescriptive { return .descriptive }
        }
        if dispositions.contains("comment") { return .commentary }
        if dispositions.contains("visual_impaired") || dispositions.contains("descriptions") { return .descriptive }
        return .main
    }
}

extension SourceFacts {
    /// Facts from what `ffprobe` saw, what MakeMKV saw, and what the assignment says.
    ///
    /// `roles` is the assignment's feature map reduced to what a rule needs: the role of each
    /// audio stream by its index from one. `kind`, `profile` and `format` are the assignment's
    /// too; a format the assignment does not give comes from the scan.
    public init(
        probe: ProbedSource,
        makeMKV: MakeMKVFacts? = nil,
        roles: [Int: AudioRole] = [:],
        kind: EntryType? = nil,
        profile: String? = nil,
        format: SourceFormat? = nil
    ) {
        var hints: [FactHint] = []

        let probedAudio = probe.streams(of: .audio)
        let probedSubtitles = probe.streams(of: .subtitle)
        let scannedAudio = makeMKV?.tracks(of: .audio) ?? []
        let scannedSubtitles = makeMKV?.tracks(of: .subtitle) ?? []
        let audioAligned = makeMKV != nil && scannedAudio.count == probedAudio.count
        let subtitlesAligned = makeMKV != nil && scannedSubtitles.count == probedSubtitles.count
        if makeMKV != nil && !audioAligned {
            hints.append(FactHint(text: "MakeMKV kept \(scannedAudio.count) audio tracks but the file has \(probedAudio.count); the scan's audio facts were not applied"))
        }
        if makeMKV != nil && !subtitlesAligned {
            hints.append(FactHint(text: "MakeMKV kept \(scannedSubtitles.count) subtitle tracks but the file has \(probedSubtitles.count); the scan's subtitle facts were not applied"))
        }

        let video = probe.streams(of: .video).first.map { stream in
            VideoFacts(
                absoluteIndex: stream.absoluteIndex,
                codec: stream.codec,
                width: stream.width ?? 0,
                height: stream.height ?? 0,
                frameRate: stream.frameRate,
                interlaced: ["tt", "bb", "tb", "bt"].contains(stream.fieldOrder ?? "progressive"),
                hdr: Self.hdr(colorTransfer: stream.colorTransfer),
                bitDepth: stream.bitsPerRawSample
            )
        }
        if probe.streams(of: .video).count > 1 {
            hints.append(FactHint(text: "the file has \(probe.streams(of: .video).count) video streams; only the first is described"))
        }

        let audio = probedAudio.enumerated().map { position, stream -> AudioFacts in
            let index = position + 1
            let scanned = audioAligned ? scannedAudio[position] : nil
            let role = AudioRole.derive(assigned: roles[index], makeMKV: scanned, dispositions: stream.dispositions)
            if role == .main, let title = stream.title, title.range(of: "commentary", options: .caseInsensitive) != nil {
                hints.append(FactHint(stream: stream.absoluteIndex, text: "titled \"\(title)\" but nothing marks it a commentary; assign it to a feature if it is one"))
            }
            return AudioFacts(
                index: index,
                absoluteIndex: stream.absoluteIndex,
                codec: stream.codec,
                profile: stream.profile,
                lossless: AudioFacts.isLossless(codec: stream.codec, profile: stream.profile),
                channels: stream.channels ?? scanned?.channels ?? 0,
                layout: stream.channelLayout,
                language: stream.language ?? scanned?.language,
                role: role,
                core: scanned?.core ?? false,
                title: stream.title
            )
        }

        let subtitles = probedSubtitles.enumerated().map { position, stream -> SubtitleFacts in
            let scanned = subtitlesAligned ? scannedSubtitles[position] : nil
            return SubtitleFacts(
                index: position + 1,
                absoluteIndex: stream.absoluteIndex,
                codec: stream.codec,
                language: stream.language ?? scanned?.language,
                forced: stream.dispositions.contains("forced") || (scanned?.forcedOnly ?? false),
                hearingImpaired: stream.dispositions.contains("hearing_impaired"),
                title: stream.title
            )
        }

        self.init(
            kind: kind,
            profile: profile,
            format: format ?? makeMKV?.format,
            duration: probe.duration,
            video: video,
            audio: audio,
            subtitles: subtitles,
            hints: hints
        )
    }

    private static func hdr(colorTransfer: String?) -> HDRKind? {
        switch colorTransfer {
        case "smpte2084": .hdr10
        case "arib-std-b67": .hlg
        default: nil
        }
    }
}
