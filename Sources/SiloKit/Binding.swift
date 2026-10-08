// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SmdKit
import SmdSidecar

/// What one entry of a library is made from: segments of one or more sources, joined in order, with
/// the entry and its feature map. A fact about the library, so it names no ruleset: applying a
/// ruleset to it is a separate act, made as often as the rules change. Made once and never changed —
/// a correction is a new binding.
public struct Binding: Hashable, Sendable, Codable {
    /// A lowercased UUID, minted by the silo.
    public var id: String
    public var library: String
    /// The item's container and every one above it, root first, as repository documents.
    public var containers: [String]
    public var item: String
    public var alternative: String?
    /// The last container's features, mapped to streams of the joined media.
    public var tracks: [TrackMapping]
    /// The chapter names the presentation will carry.
    public var chapters: [Chapter]
    public var segments: [Segment]
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString.lowercased(), library: String, containers: [String], item: String, alternative: String? = nil,
        tracks: [TrackMapping] = [], chapters: [Chapter] = [], segments: [Segment], createdAt: Date = .now
    ) {
        self.id = id
        self.library = library
        self.containers = containers
        self.item = item
        self.alternative = alternative
        self.tracks = tracks
        self.chapters = chapters
        self.segments = segments
        self.createdAt = createdAt
    }

    /// A source, or a span of its chapters, as one piece of a binding.
    public struct Segment: Hashable, Sendable, Codable {
        /// The source's id.
        public var source: String
        public var chapters: ChapterSpan?

        public init(source: String, chapters: ChapterSpan? = nil) {
            self.source = source
            self.chapters = chapters
        }
    }

    /// Chapters `from` to `to`, inclusive, by their index from one.
    public struct ChapterSpan: Hashable, Sendable, Codable {
        public var from: Int
        public var to: Int

        public init(from: Int, to: Int) {
            self.from = from
            self.to = to
        }
    }
}

/// A ruleset applied to a binding: which ruleset — the binding's library's standard when nil — at
/// which version — the latest when nil — and which of its outputs to make — every one when nil.
public struct Application: Hashable, Sendable, Codable {
    public var ruleset: String?
    public var version: Int?
    public var outputs: [OutputChoice]?

    public init(ruleset: String? = nil, version: Int? = nil, outputs: [OutputChoice]? = nil) {
        self.ruleset = ruleset
        self.version = version
        self.outputs = outputs
    }

    /// One of a ruleset's outputs, named by its profile; `{}` names the unqualified one.
    public struct OutputChoice: Hashable, Sendable, Codable {
        public var profile: String?

        public init(profile: String? = nil) {
            self.profile = profile
        }
    }
}

// MARK: - The joined media

/// A binding's segments, joined: the first segment's input spec describes every stream, since the
/// segments share a layout, and each segment is placed in seconds as a `TimedSegment` — named so,
/// not `Span`, so as not to shadow the standard library's `Span` inside this type.
public struct JoinedMedia: Hashable, Sendable {
    public var spec: InputSpec
    public var segments: [TimedSegment]

    /// One of a binding's segments placed in seconds: from `start`, to `end` or the source's end when
    /// that is unknown.
    public struct TimedSegment: Hashable, Sendable {
        public var source: String
        public var start: Double
        public var end: Double?
        /// Whether the segment is its whole source, so needs no cutting.
        public var isWhole: Bool
    }

    /// The joined segments' length, or nil when any segment's end is unknown.
    public var duration: Double? {
        var total = 0.0
        for segment in segments {
            guard let end = segment.end else { return nil }
            total += end - segment.start
        }
        return total
    }

    /// Joins segments, given the input spec of each source they name. Refused, naming why, when a
    /// source is unknown, a span names a chapter its source does not have or runs backwards, or the
    /// segments do not describe the same streams.
    public init(_ segments: [Binding.Segment], specs: [String: InputSpec]) throws(BindingError) {
        guard !segments.isEmpty else { throw .noSegments }
        var timed: [TimedSegment] = []
        var first: InputSpec?
        for (position, segment) in segments.enumerated() {
            guard let spec = specs[segment.source] else { throw .unknownSource(segment.source) }
            if let first {
                try Self.compare(first, spec, segment: position + 1)
            } else {
                first = spec
            }
            guard let span = segment.chapters else {
                timed.append(TimedSegment(source: segment.source, start: 0, end: spec.duration, isWhole: true))
                continue
            }
            guard span.to >= span.from else { throw .spanBackwards(source: segment.source, from: span.from, to: span.to) }
            guard let start = spec.chapters.first(where: { $0.index == span.from }) else {
                throw .unknownChapter(source: segment.source, chapter: span.from)
            }
            guard spec.chapters.contains(where: { $0.index == span.to }) else {
                throw .unknownChapter(source: segment.source, chapter: span.to)
            }
            let after = spec.chapters.first { $0.index > span.to }
            timed.append(TimedSegment(source: segment.source, start: start.start, end: after?.start ?? spec.duration, isWhole: false))
        }
        self.spec = first!
        self.segments = timed
    }

    /// Segments are joined as the concat demuxer joins them, so a stream's index must mean the same
    /// in each: the same kind and codec at every index.
    private static func compare(_ first: InputSpec, _ other: InputSpec, segment: Int) throws(BindingError) {
        let a = Dictionary(first.streams.map { ($0.index, $0) }, uniquingKeysWith: { lhs, _ in lhs })
        let b = Dictionary(other.streams.map { ($0.index, $0) }, uniquingKeysWith: { lhs, _ in lhs })
        for index in Set(a.keys).union(b.keys).sorted() {
            let x = a[index], y = b[index]
            guard x?.kind == y?.kind, x?.codec == y?.codec else {
                throw .layoutDiffers(segment: segment, stream: index, first: x.map { "\($0.kind.rawValue) \($0.codec)" }, other: y.map { "\($0.kind.rawValue) \($0.codec)" })
            }
        }
    }
}

public enum BindingError: Error, Hashable, Sendable, CustomStringConvertible {
    case noSegments
    case unknownSource(String)
    case unknownChapter(source: String, chapter: Int)
    case spanBackwards(source: String, from: Int, to: Int)
    case layoutDiffers(segment: Int, stream: Int, first: String?, other: String?)

    public var description: String {
        switch self {
        case .noSegments: "a binding needs at least one segment"
        case .unknownSource(let source): "no source \(source)"
        case .unknownChapter(let source, let chapter): "source \(source) has no chapter \(chapter)"
        case .spanBackwards(let source, let from, let to): "the span of source \(source) runs backwards, from chapter \(from) to \(to)"
        case .layoutDiffers(let segment, let stream, let first, let other):
            "segments cannot be joined: segment \(segment)'s stream \(stream) is \(other ?? "missing"), where segment 1's is \(first ?? "missing")"
        }
    }
}

// MARK: - Facts from an input spec

extension SourceFacts {
    /// The facts a rule tests, derived in one place from what a producer observed, what the binding
    /// knows of the entry — its kind and the role each mapped audio stream takes from its feature —
    /// and the output being made. `Ingestion.md`: observed by the producer, derived by the silo.
    public init(input spec: InputSpec, roles: [Int: AudioRole] = [:], kind: EntryType? = nil, profile: String? = nil, duration: Double? = nil) {
        var hints = spec.notes.map { FactHint(stream: $0.stream, text: $0.text) }

        let videos = spec.streams.filter { $0.kind == .video }
        if videos.count > 1 {
            hints.append(FactHint(text: "the file has \(videos.count) video streams; only the first is described"))
        }
        let video = videos.first.map { stream in
            let hdr: HDRKind? = switch stream.transfer {
            case "smpte2084": .hdr10
            case "arib-std-b67": .hlg
            default: nil
            }
            return VideoFacts(
                absoluteIndex: stream.index,
                codec: stream.codec,
                width: stream.width ?? 0,
                height: stream.height ?? 0,
                frameRate: stream.frameRate?.value,
                interlaced: stream.interlaced ?? false,
                hdr: hdr,
                bitDepth: stream.bitDepth
            )
        }

        let audio = spec.streams.filter { $0.kind == .audio }.enumerated().map { position, stream -> AudioFacts in
            let index = position + 1
            let role = roles[index] ?? (stream.marks.contains(.commentary) ? .commentary : stream.marks.contains(.descriptive) ? .descriptive : .main)
            if role == .main, let title = stream.title, title.range(of: "commentary", options: .caseInsensitive) != nil {
                hints.append(FactHint(stream: stream.index, text: "titled \"\(title)\" but nothing marks it a commentary; assign it to a feature if it is one"))
            }
            return AudioFacts(
                index: index,
                absoluteIndex: stream.index,
                codec: stream.codec,
                profile: stream.profile,
                lossless: AudioFacts.isLossless(codec: stream.codec, profile: stream.profile),
                channels: stream.channels ?? 0,
                layout: stream.layout,
                language: stream.language?.language,
                script: stream.language?.script,
                region: stream.language?.region,
                role: role,
                core: stream.coreOf != nil,
                title: stream.title
            )
        }

        let subtitles = spec.streams.filter { $0.kind == .subtitle }.enumerated().map { position, stream -> SubtitleFacts in
            SubtitleFacts(
                index: position + 1,
                absoluteIndex: stream.index,
                codec: stream.codec,
                language: stream.language?.language,
                script: stream.language?.script,
                region: stream.language?.region,
                forced: stream.marks.contains(.forced),
                hearingImpaired: stream.marks.contains(.hearingImpaired),
                title: stream.title
            )
        }

        self.init(
            kind: kind,
            profile: profile,
            format: spec.medium,
            duration: duration ?? spec.duration,
            video: video,
            audio: audio,
            subtitles: subtitles,
            hints: hints
        )
    }
}
