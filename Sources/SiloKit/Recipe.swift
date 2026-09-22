// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation

/// The fully resolved instructions for turning one source file into one presentation: one decision
/// per source stream, each naming the rule that made it, and the layout of streams the output will
/// have. Followed exactly by the encoder, and read afterwards to see what was done.
/// `Silo.md`, *Recipes*.
public struct Recipe: Hashable, Sendable, Codable {
    public var ruleset: RulesetRef
    /// In source order: the video stream, then each audio stream, then each subtitle stream.
    public var decisions: [StreamDecision]
    public var output: OutputPolicy
    public var layout: OutputLayout
    /// A feature mapped to a stream the recipe drops, and anything else worth a person's eye
    /// before the encode starts. Not errors: a mobile presentation without the isolated score
    /// is a reasonable thing to make.
    public var warnings: [String]

    public init(ruleset: RulesetRef, decisions: [StreamDecision], output: OutputPolicy, layout: OutputLayout, warnings: [String] = []) {
        self.ruleset = ruleset
        self.decisions = decisions
        self.output = output
        self.layout = layout
        self.warnings = warnings
    }

    public var video: StreamDecision? { decisions.first { $0.kind == .video } }
    public var audio: [StreamDecision] { decisions.filter { $0.kind == .audio } }
    public var subtitles: [StreamDecision] { decisions.filter { $0.kind == .subtitle } }

    /// The decisions whose stream survives into the output, in output order.
    public var kept: [StreamDecision] {
        layout.streams.compactMap { stream in
            decisions.first { $0.kind == stream.kind && $0.sourceIndex == stream.sourceIndex }
        }
    }

    /// The encoders the recipe needs, by `ffmpeg`'s names: what a node has to have to claim it.
    public var encoders: Set<String> {
        Set(decisions.compactMap { decision in
            if case .encode(let settings) = decision.action { settings.codec } else { nil }
        })
    }

    /// The assignment's feature map, renumbered to the output: the commentary that was source
    /// audio 3 becomes `audio="2"` when the recipe dropped the surround mix before it. A mapping
    /// whose stream the recipe drops is left out; the resolver already warned about it.
    public func tracks(for mappings: [TrackMapping]) -> [TrackMapping] {
        mappings.compactMap { mapping in
            var renumbered = TrackMapping(feature: mapping.feature)
            if let audio = mapping.audio {
                guard let output = layout.outputIndex(of: .audio, sourceIndex: audio) else { return nil }
                renumbered.audio = output
            }
            if let subtitle = mapping.subtitle {
                guard let output = layout.outputIndex(of: .subtitle, sourceIndex: subtitle) else { return nil }
                renumbered.subtitle = output
            }
            return renumbered
        }
    }
}

/// A ruleset by name and version, as a job records it: `household@7`.
public struct RulesetRef: Hashable, Sendable, Codable, CustomStringConvertible {
    public var name: String
    public var version: Int?

    public init(name: String, version: Int? = nil) {
        self.name = name
        self.version = version
    }

    public init(_ ruleset: Ruleset) {
        self.init(name: ruleset.name, version: ruleset.version)
    }

    public var description: String {
        version.map { "\(name)@\($0)" } ?? name
    }
}

public struct StreamDecision: Hashable, Sendable, Codable {
    public var kind: StreamKind
    /// From one, among source streams of the kind.
    public var sourceIndex: Int
    public var sourceAbsoluteIndex: Int
    /// The rule's id, or its position in the ruleset as `#n` when it has none.
    public var rule: String
    public var action: Action

    public init(kind: StreamKind, sourceIndex: Int, sourceAbsoluteIndex: Int, rule: String, action: Action) {
        self.kind = kind
        self.sourceIndex = sourceIndex
        self.sourceAbsoluteIndex = sourceAbsoluteIndex
        self.rule = rule
        self.action = action
    }

    public var isKept: Bool {
        if case .drop = action { false } else { true }
    }
}

/// The streams the output will have, in order, each pointing back at the source stream it came
/// from. Video first, then the audio streams that survive in source order, then the subtitles.
/// Computed from the recipe, so the new presentation's `<track>` indices are known before the
/// encode; verified against the output afterwards.
public struct OutputLayout: Hashable, Sendable, Codable {
    public var streams: [LayoutStream]

    public init(streams: [LayoutStream]) {
        self.streams = streams
    }

    public init(keeping decisions: [StreamDecision]) {
        var streams: [LayoutStream] = []
        var perKind: [StreamKind: Int] = [:]
        for kind in [StreamKind.video, .audio, .subtitle] {
            for decision in decisions where decision.kind == kind && decision.isKept {
                perKind[kind, default: 0] += 1
                streams.append(LayoutStream(
                    kind: kind,
                    sourceIndex: decision.sourceIndex,
                    sourceAbsoluteIndex: decision.sourceAbsoluteIndex,
                    outputIndex: perKind[kind]!,
                    outputAbsoluteIndex: streams.count
                ))
            }
        }
        self.streams = streams
    }

    public func outputIndex(of kind: StreamKind, sourceIndex: Int) -> Int? {
        streams.first { $0.kind == kind && $0.sourceIndex == sourceIndex }?.outputIndex
    }

    public func streams(of kind: StreamKind) -> [LayoutStream] {
        streams.filter { $0.kind == kind }
    }

    /// The kinds in output order — the shape a probe of the output is compared against.
    public var kinds: [StreamKind] { streams.map(\.kind) }
}

public struct LayoutStream: Hashable, Sendable, Codable {
    public var kind: StreamKind
    public var sourceIndex: Int
    public var sourceAbsoluteIndex: Int
    /// From one, among output streams of the kind.
    public var outputIndex: Int
    /// From zero, across the output: `ffmpeg`'s own count.
    public var outputAbsoluteIndex: Int

    public init(kind: StreamKind, sourceIndex: Int, sourceAbsoluteIndex: Int, outputIndex: Int, outputAbsoluteIndex: Int) {
        self.kind = kind
        self.sourceIndex = sourceIndex
        self.sourceAbsoluteIndex = sourceAbsoluteIndex
        self.outputIndex = outputIndex
        self.outputAbsoluteIndex = outputAbsoluteIndex
    }
}

/// A feature mapped to a file's streams: the sidecar's `<track feature="…" audio="…" subtitle="…"/>`
/// as a value, counted from one among streams of each kind.
public struct TrackMapping: Hashable, Sendable, Codable {
    public var feature: String
    public var audio: Int?
    public var subtitle: Int?

    public init(feature: String, audio: Int? = nil, subtitle: Int? = nil) {
        self.feature = feature
        self.audio = audio
        self.subtitle = subtitle
    }
}
