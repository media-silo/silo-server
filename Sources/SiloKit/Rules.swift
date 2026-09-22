// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation

/// A named, ordered list of encoding rules, with the extraction policy the ingestion tool applies
/// at rip time beside them: the two halves of "what is kept and how" in one document.
/// `Silo.md`, *Encoding rules*.
public struct Ruleset: Hashable, Sendable, Codable {
    public var name: String
    /// Assigned by the silo when the ruleset is stored; nil in a file that has not been. A job
    /// names the version it resolved against, and a version is immutable once stored.
    public var version: Int?
    public var extraction: ExtractionPolicy
    public var rules: [Rule]
    public var output: OutputPolicy

    public init(
        name: String, version: Int? = nil, extraction: ExtractionPolicy = ExtractionPolicy(),
        rules: [Rule], output: OutputPolicy = OutputPolicy()
    ) {
        self.name = name
        self.version = version
        self.extraction = extraction
        self.rules = rules
        self.output = output
    }

    public func rules(in scope: Scope) -> [(position: Int, rule: Rule)] {
        rules.enumerated().compactMap { $0.element.scope == scope ? (position: $0.offset + 1, rule: $0.element) : nil }
    }
}

/// Which streams a rule is about.
public enum Scope: String, Hashable, Sendable, Codable, CaseIterable {
    case video, audio, subtitle
}

/// One rule: every condition must hold, and then the action is what happens to the stream. The
/// first rule in a scope whose conditions all hold decides; a stream no rule decides is an error.
public struct Rule: Hashable, Sendable, Codable {
    public var id: String?
    public var scope: Scope
    public var conditions: [Condition]
    public var action: Action

    public init(id: String? = nil, scope: Scope, conditions: [Condition] = [], action: Action) {
        self.id = id
        self.scope = scope
        self.conditions = conditions
        self.action = action
    }
}

public struct Condition: Hashable, Sendable, Codable {
    public var fact: FactKey
    public var test: Test

    public init(_ fact: FactKey, _ test: Test) {
        self.fact = fact
        self.test = test
    }

    /// `is` and `ne` compare the fact's text; `in` is membership in a set of texts; the four
    /// ordering tests compare numbers, and a fact that is not a number refuses them at parse.
    public enum Test: Hashable, Sendable, Codable {
        case equal(String)
        case notEqual(String)
        case oneOf([String])
        case less(Double)
        case lessOrEqual(Double)
        case greater(Double)
        case greaterOrEqual(Double)

        public var isNumeric: Bool {
            switch self {
            case .equal, .notEqual, .oneOf: false
            case .less, .lessOrEqual, .greater, .greaterOrEqual: true
            }
        }
    }

    public func holds(_ value: FactValue) -> Bool {
        switch test {
        case .equal(let expected):
            return value.matches(expected)
        case .notEqual(let expected):
            // An absent fact is not equal to anything: `hdr ne hdr10` holds for SDR video.
            return !value.matches(expected)
        case .oneOf(let expected):
            return expected.contains { value.matches($0) }
        case .less(let bound):
            return value.number.map { $0 < bound } ?? false
        case .lessOrEqual(let bound):
            return value.number.map { $0 <= bound } ?? false
        case .greater(let bound):
            return value.number.map { $0 > bound } ?? false
        case .greaterOrEqual(let bound):
            return value.number.map { $0 >= bound } ?? false
        }
    }
}

/// The closed vocabulary of things a rule may test. A key carries its scope as a prefix; a
/// file-level key is visible in every scope. An unknown key is a parse error, not a rule that
/// never matches.
public enum FactKey: String, Hashable, Sendable, Codable, CaseIterable {
    case kind
    case profile
    case format
    case duration
    case videoCodec = "video.codec"
    case videoWidth = "video.width"
    case videoHeight = "video.height"
    case videoFrameRate = "video.frameRate"
    case videoInterlaced = "video.interlaced"
    case videoHDR = "video.hdr"
    case videoBitDepth = "video.bitDepth"
    case audioCodec = "audio.codec"
    case audioLossless = "audio.lossless"
    case audioChannels = "audio.channels"
    case audioLanguage = "audio.language"
    case audioRole = "audio.role"
    case audioCore = "audio.core"
    case subtitleCodec = "subtitle.codec"
    case subtitleLanguage = "subtitle.language"
    case subtitleForced = "subtitle.forced"

    /// Nil for a file-level fact.
    public var scope: Scope? {
        switch self {
        case .kind, .profile, .format, .duration: nil
        case .videoCodec, .videoWidth, .videoHeight, .videoFrameRate, .videoInterlaced, .videoHDR, .videoBitDepth: .video
        case .audioCodec, .audioLossless, .audioChannels, .audioLanguage, .audioRole, .audioCore: .audio
        case .subtitleCodec, .subtitleLanguage, .subtitleForced: .subtitle
        }
    }

    public var isNumeric: Bool {
        switch self {
        case .duration, .videoWidth, .videoHeight, .videoFrameRate, .videoBitDepth, .audioChannels: true
        default: false
        }
    }

    public func isVisible(in scope: Scope) -> Bool {
        self.scope == nil || self.scope == scope
    }
}

/// A fact's value at the moment a condition reads it.
public enum FactValue: Hashable, Sendable {
    case text(String)
    case number(Double)
    case flag(Bool)
    case absent

    public var number: Double? {
        switch self {
        case .number(let value): value
        case .text(let text): Double(text)
        case .flag, .absent: nil
        }
    }

    /// Text comparison, with a number compared as a number when the expected text is one, so
    /// that `frameRate is 25` holds for `25.0`.
    public func matches(_ expected: String) -> Bool {
        switch self {
        case .text(let text): text == expected
        case .number(let value): Double(expected) == value || String(value) == expected
        case .flag(let flag): (flag ? "true" : "false") == expected
        case .absent: false
        }
    }
}

/// What happens to a stream a rule decided.
public enum Action: Hashable, Sendable, Codable {
    case copy
    case drop
    case encode(EncodeSettings)
}

public struct EncodeSettings: Hashable, Sendable, Codable {
    /// The encoder as `ffmpeg` names it: `libx264`, `libx265`, `flac`, `aac`.
    public var codec: String
    public var preset: String?
    public var crf: Int?
    /// As `ffmpeg` takes it: `160k`.
    public var bitrate: String?
    public var channels: Int?
    public var pixelFormat: String?
    public var filters: [Filter]
    /// Anything else, handed to `ffmpeg` as `-<name>:<stream> <value>`. Kept sorted by name so
    /// that two settings that mean the same thing compare equal and encode the same way.
    public var options: [String: String]

    public init(
        codec: String, preset: String? = nil, crf: Int? = nil, bitrate: String? = nil,
        channels: Int? = nil, pixelFormat: String? = nil, filters: [Filter] = [],
        options: [String: String] = [:]
    ) {
        self.codec = codec
        self.preset = preset
        self.crf = crf
        self.bitrate = bitrate
        self.channels = channels
        self.pixelFormat = pixelFormat
        self.filters = filters
        self.options = options
    }
}

public enum Filter: Hashable, Sendable, Codable {
    /// `auto` deinterlaces frames the stream marks interlaced and leaves the rest; `always` does
    /// every frame.
    case deinterlace(DeinterlaceMode)
    /// Either dimension nil keeps the aspect ratio.
    case scale(width: Int?, height: Int?)
    /// Raw `ffmpeg` filter text, for the one a rule needs that has no element of its own.
    case custom(String)

    public enum DeinterlaceMode: String, Hashable, Sendable, Codable, CaseIterable {
        case auto, always
    }
}

/// What the ingestion tool keeps when it rips: every track on the disc, minus what these leave
/// out. The defaults are the tool's, with its reasons: the lossy core inside a lossless track is
/// the same audio again, smaller and worse, and can be pulled out later, exactly; the forced-only
/// subtitle stream MakeMKV derives is free, because it is dropped when it turns out empty.
public struct ExtractionPolicy: Hashable, Sendable, Codable {
    public var includeEmbeddedAudioTracks: Bool
    public var includeSubtitles: Bool
    public var includeEmbeddedSubtitleTracks: Bool

    public init(includeEmbeddedAudioTracks: Bool = false, includeSubtitles: Bool = true, includeEmbeddedSubtitleTracks: Bool = true) {
        self.includeEmbeddedAudioTracks = includeEmbeddedAudioTracks
        self.includeSubtitles = includeSubtitles
        self.includeEmbeddedSubtitleTracks = includeEmbeddedSubtitleTracks
    }
}

public struct OutputPolicy: Hashable, Sendable, Codable {
    /// The container format, as `ffmpeg -f` names it. Only `matroska` is exercised.
    public var container: String

    public init(container: String = "mkv") {
        self.container = container
    }

    public var fileExtension: String { container == "matroska" ? "mkv" : container }
    public var ffmpegFormat: String { container == "mkv" ? "matroska" : container }
}

// MARK: - Reading a fact

/// Which stream a condition is being evaluated for.
public enum StreamSelector: Hashable, Sendable {
    case video
    /// By index from one among streams of the kind.
    case audio(Int)
    case subtitle(Int)
}

extension SourceFacts {
    public func value(_ key: FactKey, for stream: StreamSelector) -> FactValue {
        switch key {
        case .kind: return kind.map { .text($0.rawValue) } ?? .absent
        case .profile: return profile.map(FactValue.text) ?? .absent
        case .format: return format.map { .text($0.rawValue) } ?? .absent
        case .duration: return duration.map(FactValue.number) ?? .absent
        case .videoCodec: return video.map { .text($0.codec) } ?? .absent
        case .videoWidth: return video.map { .number(Double($0.width)) } ?? .absent
        case .videoHeight: return video.map { .number(Double($0.height)) } ?? .absent
        case .videoFrameRate: return video?.frameRate.map(FactValue.number) ?? .absent
        case .videoInterlaced: return video.map { .flag($0.interlaced) } ?? .absent
        case .videoHDR: return video?.hdr.map { .text($0.rawValue) } ?? .absent
        case .videoBitDepth: return video?.bitDepth.map { .number(Double($0)) } ?? .absent
        case .audioCodec: return audioFacts(stream).map { .text($0.codec) } ?? .absent
        case .audioLossless: return audioFacts(stream).map { .flag($0.lossless) } ?? .absent
        case .audioChannels: return audioFacts(stream).map { .number(Double($0.channels)) } ?? .absent
        case .audioLanguage: return audioFacts(stream)?.language.map(FactValue.text) ?? .absent
        case .audioRole: return audioFacts(stream).map { .text($0.role.rawValue) } ?? .absent
        case .audioCore: return audioFacts(stream).map { .flag($0.core) } ?? .absent
        case .subtitleCodec: return subtitleFacts(stream).map { .text($0.codec) } ?? .absent
        case .subtitleLanguage: return subtitleFacts(stream)?.language.map(FactValue.text) ?? .absent
        case .subtitleForced: return subtitleFacts(stream).map { .flag($0.forced) } ?? .absent
        }
    }

    private func audioFacts(_ stream: StreamSelector) -> AudioFacts? {
        guard case .audio(let index) = stream else { return nil }
        return audio.first { $0.index == index }
    }

    private func subtitleFacts(_ stream: StreamSelector) -> SubtitleFacts? {
        guard case .subtitle(let index) = stream else { return nil }
        return subtitles.first { $0.index == index }
    }
}
