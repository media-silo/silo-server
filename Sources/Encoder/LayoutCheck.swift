// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloKit

/// A place where the encoded file disagrees with the recipe's layout. Any mismatch fails the job:
/// the sidecar's `<track>` indices were computed from the layout, and a file that does not have
/// it would be described wrongly.
public struct LayoutMismatch: Hashable, Sendable, CustomStringConvertible {
    /// The output stream's absolute index.
    public var position: Int
    public var expected: String
    public var found: String

    public init(position: Int, expected: String, found: String) {
        self.position = position
        self.expected = expected
        self.found = found
    }

    public var description: String {
        "stream \(position): expected \(expected), found \(found)"
    }
}

extension Recipe {
    /// Compares a probe of the output against the layout: the same kinds in the same order, and
    /// the codec the decision implies where that is known — the source's for a copy, the
    /// encoder's output name for an encode. An encoder this table does not know is not checked.
    public func verify(against probed: ProbedSource, source: SourceFacts) -> [LayoutMismatch] {
        let actual = probed.streams.filter { [.video, .audio, .subtitle].contains($0.kind) }
        var mismatches: [LayoutMismatch] = []
        for (position, stream) in layout.streams.enumerated() {
            guard position < actual.count else {
                mismatches.append(LayoutMismatch(position: position, expected: stream.kind.rawValue, found: "nothing"))
                continue
            }
            let found = actual[position]
            guard found.kind.rawValue == stream.kind.rawValue else {
                mismatches.append(LayoutMismatch(position: position, expected: stream.kind.rawValue, found: found.kind.rawValue))
                continue
            }
            if let expected = expectedCodec(for: stream, source: source), expected != found.codec {
                mismatches.append(LayoutMismatch(position: position, expected: "\(stream.kind.rawValue) \(expected)", found: "\(found.kind.rawValue) \(found.codec)"))
            }
        }
        if actual.count > layout.streams.count {
            for extra in actual[layout.streams.count...] {
                mismatches.append(LayoutMismatch(position: extra.absoluteIndex, expected: "nothing", found: "\(extra.kind.rawValue) \(extra.codec)"))
            }
        }
        return mismatches
    }

    private func expectedCodec(for stream: LayoutStream, source: SourceFacts) -> String? {
        guard let decision = decisions.first(where: { $0.kind == stream.kind && $0.sourceIndex == stream.sourceIndex }) else {
            return nil
        }
        switch decision.action {
        case .drop:
            return nil
        case .copy:
            switch stream.kind {
            case .video: return source.video?.codec
            case .audio: return source.audio.first { $0.index == stream.sourceIndex }?.codec
            case .subtitle: return source.subtitles.first { $0.index == stream.sourceIndex }?.codec
            }
        case .encode(let settings):
            return Self.probedName(forEncoder: settings.codec)
        }
    }

    /// `ffprobe`'s codec name for what an encoder writes. Nil for an encoder not listed, which
    /// means "not checked" rather than "wrong".
    public static func probedName(forEncoder encoder: String) -> String? {
        switch encoder {
        case "libx264", "h264_videotoolbox", "h264_nvenc", "h264_qsv", "h264_vaapi": "h264"
        case "libx265", "hevc_videotoolbox", "hevc_nvenc", "hevc_qsv", "hevc_vaapi": "hevc"
        case "libsvtav1", "libaom-av1", "librav1e", "av1_nvenc", "av1_qsv": "av1"
        case "libvpx-vp9": "vp9"
        case "aac", "aac_at", "libfdk_aac": "aac"
        case "flac": "flac"
        case "libopus", "opus": "opus"
        case "ac3", "ac3_fixed": "ac3"
        case "eac3": "eac3"
        case "libmp3lame": "mp3"
        case "truehd": "truehd"
        case "dca": "dts"
        case "srt", "subrip": "subrip"
        case "ass": "ass"
        default: nil
        }
    }
}
