// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloKit

/// The silo's own producer: an input spec for a plain file, from what `ffprobe` reports of it and
/// nothing else. It knows no medium and no cores, and notes nothing, because a plain file tells it
/// none of that; a producer that knows more — where a file came from, which stream is whose core —
/// writes its own spec.
extension InputSpec {
    public init(probe: ProbedSource) {
        let starts = probe.chapters.map(\.start)
        // `ffprobe` lists chapters in order; one that does not advance is not a division of the file.
        let chapters = probe.chapters.enumerated()
            .filter { position, chapter in position == 0 || chapter.start > starts[position - 1] }
            .enumerated()
            .map { number, element in Chapter(index: number + 1, start: element.element.start, title: element.element.title) }
        self.init(
            duration: probe.duration,
            chapters: chapters,
            streams: probe.streams.map(Stream.init(probed:))
        )
    }
}

extension InputSpec.Stream {
    init(probed stream: ProbedStream) {
        let kind: Kind = switch stream.kind {
        case .video: .video
        case .audio: .audio
        case .subtitle: .subtitle
        case .data, .attachment, .other: .other
        }
        self.init(
            index: stream.absoluteIndex,
            kind: kind,
            codec: stream.codec,
            profile: stream.profile,
            width: kind == .video ? stream.width ?? 0 : nil,
            height: kind == .video ? stream.height ?? 0 : nil,
            frameRate: kind == .video ? stream.frameRate : nil,
            interlaced: kind == .video ? stream.fieldOrder.map { ["tt", "bb", "tb", "bt"].contains($0) } : nil,
            transfer: kind == .video ? stream.colorTransfer : nil,
            bitDepth: kind == .video ? stream.bitsPerRawSample : nil,
            channels: kind == .audio ? stream.channels ?? 0 : nil,
            layout: kind == .audio ? stream.channelLayout : nil,
            language: stream.language.flatMap(LanguageTag.init(canonicalizing:)).flatMap { $0.description == "und" ? nil : $0 },
            title: stream.title,
            marks: Self.marks(stream.dispositions)
        )
    }

    /// `ffprobe`'s dispositions as marks. `comment` is the commentary mark; `visual_impaired` and
    /// `descriptions` both say a stream describes the picture.
    static func marks(_ dispositions: Set<String>) -> Set<InputSpec.Mark> {
        var marks: Set<InputSpec.Mark> = []
        if dispositions.contains("default") { marks.insert(.default) }
        if dispositions.contains("forced") { marks.insert(.forced) }
        if dispositions.contains("hearing_impaired") { marks.insert(.hearingImpaired) }
        if dispositions.contains("comment") { marks.insert(.commentary) }
        if dispositions.contains("visual_impaired") || dispositions.contains("descriptions") { marks.insert(.descriptive) }
        return marks
    }
}
