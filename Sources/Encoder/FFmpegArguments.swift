// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloKit

extension Recipe {
    /// The recipe as `ffmpeg`'s argument list. Pure: the same recipe and paths give the same
    /// arguments, which is what the tests compare.
    ///
    /// Streams are mapped in layout order, so the output's stream order is the layout's, and each
    /// kept stream's options are addressed by its place among output streams of its kind —
    /// `a:1` is the second audio stream of the output, whatever it was in the source.
    public func ffmpegArguments(input: URL, output: URL) -> [String] {
        var arguments = [
            "-y", "-nostdin", "-hide_banner", "-loglevel", "error",
            "-progress", "pipe:1", "-nostats",
            "-i", input.path,
        ]
        for stream in layout.streams {
            arguments += ["-map", "0:\(stream.sourceAbsoluteIndex)"]
        }
        for (stream, decision) in zip(layout.streams, kept) {
            let specifier = "\(stream.kind.ffmpegSpecifier):\(stream.outputIndex - 1)"
            switch decision.action {
            case .copy:
                arguments += ["-c:\(specifier)", "copy"]
            case .drop:
                continue
            case .encode(let settings):
                arguments += ["-c:\(specifier)", settings.codec]
                if let preset = settings.preset { arguments += ["-preset:\(specifier)", preset] }
                if let crf = settings.crf { arguments += ["-crf:\(specifier)", String(crf)] }
                if let bitrate = settings.bitrate { arguments += ["-b:\(specifier)", bitrate] }
                if let channels = settings.channels { arguments += ["-ac:\(specifier)", String(channels)] }
                if let pixelFormat = settings.pixelFormat { arguments += ["-pix_fmt:\(specifier)", pixelFormat] }
                let filters = settings.filters.map(\.ffmpegText)
                if !filters.isEmpty { arguments += ["-filter:\(specifier)", filters.joined(separator: ",")] }
                for (name, value) in settings.options.sorted(by: { $0.key < $1.key }) {
                    arguments += ["-\(name):\(specifier)", value]
                }
            }
        }
        arguments += ["-map_metadata", "0", "-map_chapters", "0", "-f", self.output.ffmpegFormat, output.path]
        return arguments
    }
}

extension StreamKind {
    var ffmpegSpecifier: String {
        switch self {
        case .video: "v"
        case .audio: "a"
        case .subtitle: "s"
        }
    }
}

extension Filter {
    public var ffmpegText: String {
        switch self {
        case .deinterlace(.auto): "yadif=deint=interlaced"
        case .deinterlace(.always): "yadif"
        case .scale(let width, let height): "scale=\(width ?? -2):\(height ?? -2)"
        case .custom(let text): text
        }
    }
}
