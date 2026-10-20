// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloKit
import SmdKit

/// A rule as the console's form reads it to a person: what decides, in words rather than the
/// document's attributes. The document is unchanged by any of this; it is only how it is shown.
extension Rule {
    /// One clause of a rule as the form shows it: a keyword, and what follows it.
    public struct Clause: Hashable, Sendable {
        public var keyword: String
        public var text: String

        public init(_ keyword: String, _ text: String) {
            self.keyword = keyword
            self.text = text
        }
    }

    /// The rule's clauses, in groups the form starts on a line of their own: its conditions, IF the
    /// first and AND each other, and then its action, THEN what it does, WHERE its first setting and
    /// AND each other. Every rule after the first of its scope is reached only when those before it
    /// did not decide, so its IF reads OTHERWISE IF. A rule with no condition is its action alone,
    /// ALWAYS when it is its scope's first rule and OTHERWISE after another.
    public func reading(afterOthers: Bool) -> [[Clause]] {
        guard let first = conditions.first else {
            return [action.clauses(lead: afterOthers ? "OTHERWISE" : "ALWAYS", in: scope)]
        }
        return [
            [Clause(afterOthers ? "OTHERWISE IF" : "IF", first.phrase(in: scope))]
                + conditions.dropFirst().map { Clause("AND", $0.phrase(in: scope)) },
            action.clauses(lead: "THEN", in: scope),
        ]
    }
}

extension Condition {
    /// `width < 1280` in a video rule, `language one of en, fr` in an audio one: the fact named as
    /// the rule's scope sees it.
    public func phrase(in scope: Scope) -> String {
        let value = if case .oneOf(let values) = test { values.joined(separator: ", ") } else { test.attribute.value }
        return "\(fact.name(in: scope)) \(Condition.Test.label(of: test.attribute.name)) \(value)"
    }
}

extension Condition.Test {
    /// How the form names a test the document writes as `is`, `ne`, `in`, `lt`, `le`, `gt` or `ge`.
    public static func label(of attribute: String) -> String {
        switch attribute {
        case "is": "is"
        case "ne": "is not"
        case "in": "one of"
        case "lt": "<"
        case "le": "≤"
        case "gt": ">"
        case "ge": "≥"
        default: attribute
        }
    }
}

extension FactKey {
    /// The fact as a rule of `scope` names it: without the scope's prefix, which the rule already
    /// says, so `codec` in a video rule and `video.codec` nowhere else it could be read.
    public func name(in scope: Scope) -> String {
        let prefix = scope.rawValue + "."
        return self.scope == scope && rawValue.hasPrefix(prefix) ? String(rawValue.dropFirst(prefix.count)) : rawValue
    }

    /// Values an open fact is commonly met with, offered beside the field that takes any: an
    /// item's types as SmdKit names them, a main item's and then an extra's, and codecs as
    /// `ffprobe` names them. Empty for a fact with none to suggest; a closed fact's are `values`.
    public var suggestedValues: [String] {
        switch self {
        case .kind: ([EntryType.episode, .movie] + EntryType.extraTypes).map(\.rawValue)
        case .videoCodec: ["h264", "hevc", "av1", "vp9", "mpeg2video", "vc1"]
        case .audioCodec: ["truehd", "dts", "eac3", "ac3", "aac", "flac", "opus", "mp3", "pcm_s16le", "pcm_s24le"]
        case .subtitleCodec: ["hdmv_pgs_subtitle", "dvd_subtitle", "subrip", "ass"]
        default: []
        }
    }
}

extension Action {
    /// The action's clauses: `lead` and what it does, and for an encode each of its settings, WHERE
    /// the first and AND each other — its codec named as a condition on the codec would name it.
    public func clauses(lead: String, in scope: Scope) -> [Rule.Clause] {
        guard case .encode(let settings) = self else { return [Rule.Clause(lead, summary)] }
        let settingsRead =
            [
                "codec is \(scope.codec(ofEncoder: settings.codec))",
                settings.bitrate.map { "bitrate is \($0)" },
                settings.crf.map { "crf is \($0)" },
                settings.preset.map { "preset is \($0)" },
                settings.channels.map { "channels is \($0)" },
                settings.pixelFormat.map { "pixel format is \($0)" },
            ].compactMap { $0 } + settings.filters.map(\.phrase)
            + settings.options.sorted { $0.key < $1.key }.map { "\($0.key) is \($0.value)" }
        return [Rule.Clause(lead, "encode")]
            + settingsRead.enumerated().map { Rule.Clause($0.offset == 0 ? "WHERE" : "AND", $0.element) }
    }
}

extension Filter {
    /// `deinterlace is auto`, `scale is 1280×720`.
    public var phrase: String {
        switch self {
        case .deinterlace(let mode): "deinterlace is \(mode.rawValue)"
        case .scale(let width?, let height?): "scale is \(width)×\(height)"
        case .scale(let width?, nil): "width is \(width)"
        case .scale(nil, let height?): "height is \(height)"
        case .scale(nil, nil): "scale is source"
        case .custom(let text): "filter is \(text)"
        }
    }
}

extension Scope {
    /// The codecs the form offers an encode of the scope, as `ffprobe` names them and as a
    /// condition on the codec is written, each with the encoder the document names for it; the
    /// first is the one a new encode starts with. The document names encoders because a node
    /// takes on a job by the encoders its `ffmpeg` lists, which name `libx265` and never `hevc`.
    public var codecs: [(codec: String, encoder: String)] {
        switch self {
        case .video: [("h264", "libx264"), ("hevc", "libx265"), ("av1", "libsvtav1")]
        case .audio: [("aac", "aac"), ("flac", "flac"), ("opus", "libopus"), ("eac3", "eac3"), ("ac3", "ac3")]
        case .subtitle: [("subrip", "subrip"), ("ass", "ass")]
        }
    }

    /// The codec an encoder offered here makes, or the encoder itself for one that is not offered.
    public func codec(ofEncoder encoder: String) -> String {
        codecs.first { $0.encoder == encoder }?.codec ?? encoder
    }

    /// The encoder the document names for a codec offered here, or the text itself, taken as an
    /// encoder, for one that is not.
    public func encoder(forCodec codec: String) -> String {
        codecs.first { $0.codec == codec }?.encoder ?? codec
    }
}

/// A setting of an encode the form shows as a field of its own.
public enum EncodeSetting: String, CaseIterable, Hashable, Sendable {
    case preset, crf, bitrate, channels, pixelFormat
}

extension Scope {
    /// The settings an encode to `codec` takes, named as the form offers it or as an encoder: a
    /// video encode its preset, quality, bitrate and pixel format; an audio encode its channels,
    /// and its bitrate unless the codec is lossless, which has none to set; a subtitle encode none.
    public func settings(forCodec codec: String) -> [EncodeSetting] {
        switch self {
        case .video: [.preset, .crf, .bitrate, .pixelFormat]
        case .audio:
            Self.isLossless(self.codec(ofEncoder: encoder(forCodec: codec))) ? [.channels] : [.bitrate, .channels]
        case .subtitle: []
        }
    }

    private static func isLossless(_ codec: String) -> Bool {
        ["flac", "alac", "truehd", "mlp", "wavpack", "tta"].contains(codec) || codec.hasPrefix("pcm_")
    }
}
