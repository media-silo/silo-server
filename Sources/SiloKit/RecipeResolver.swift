// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation

/// Resolves a ruleset against a file's facts. Pure: no `ffmpeg`, no file, and every input is a
/// value, which is what makes the three rules in the proposal testable on a literal.
public enum RecipeResolver {
    /// For the video stream and for each audio and subtitle stream in turn, the first rule in the
    /// scope whose conditions all hold decides. A stream no rule decides is an error naming the
    /// stream and its facts, never a silent copy.
    ///
    /// `layers` are the stack above the ruleset, nearest first: each is tried, layer by layer, before
    /// the ruleset's own rules, and the first rule that matches anywhere decides. The outputs are
    /// the ruleset's alone.
    ///
    /// `mappings` is the binding's feature map, used only to warn when a mapped stream is
    /// dropped; the renumbered map is `recipe.tracks(for:)`.
    public static func resolve(_ facts: SourceFacts, with ruleset: Ruleset, layers: [RulesLayer] = [], mappings: [TrackMapping] = []) throws(ResolutionError) -> Recipe {
        var decisions: [StreamDecision] = []
        let stack = layers.map { (DecisionLayer.layer($0.subject), $0.rules) } + [(DecisionLayer.ruleset(ruleset.name), ruleset.rules)]

        if let video = facts.video {
            decisions.append(try decide(.video, index: 1, absoluteIndex: video.absoluteIndex, selector: .video, facts: facts, stack: stack))
        }
        for audio in facts.audio {
            decisions.append(try decide(.audio, index: audio.index, absoluteIndex: audio.absoluteIndex, selector: .audio(audio.index), facts: facts, stack: stack))
        }
        for subtitle in facts.subtitles {
            decisions.append(try decide(.subtitle, index: subtitle.index, absoluteIndex: subtitle.absoluteIndex, selector: .subtitle(subtitle.index), facts: facts, stack: stack))
        }

        let layout = OutputLayout(keeping: decisions)
        return Recipe(
            ruleset: RulesetRef(ruleset), layers: layers.map(\.reference), decisions: decisions, output: ruleset.output(for: facts.profile), layout: layout,
            warnings: warnings(layout: layout, mappings: mappings, hasVideo: facts.video != nil)
        )
    }

    /// What a person should read before the encode: a feature mapped to a stream the layout drops,
    /// and a source with no video. A function of the layout, so an adjusted recipe warns as the
    /// rules' own would.
    public static func warnings(layout: OutputLayout, mappings: [TrackMapping], hasVideo: Bool) -> [String] {
        var warnings: [String] = []
        for mapping in mappings {
            if let audio = mapping.audio, layout.outputIndex(of: .audio, sourceIndex: audio) == nil {
                warnings.append("feature \(mapping.feature) is mapped to audio \(audio), which this recipe drops")
            }
            if let subtitle = mapping.subtitle, layout.outputIndex(of: .subtitle, sourceIndex: subtitle) == nil {
                warnings.append("feature \(mapping.feature) is mapped to subtitle \(subtitle), which this recipe drops")
            }
        }
        if !hasVideo {
            warnings.append("the source has no video stream")
        }
        return warnings
    }

    private static func decide(
        _ kind: StreamKind, index: Int, absoluteIndex: Int, selector: StreamSelector,
        facts: SourceFacts, stack: [(DecisionLayer, [Rule])]
    ) throws(ResolutionError) -> StreamDecision {
        let scope: Scope = switch kind {
        case .video: .video
        case .audio: .audio
        case .subtitle: .subtitle
        }
        for (layer, rules) in stack {
            // A rule is named by its position among its own layer's rules of every scope, as a
            // ruleset's are.
            for (position, rule) in rules.enumerated() where rule.scope == scope {
                let holds = rule.conditions.allSatisfy { $0.holds(facts.value($0.fact, for: selector)) }
                if holds {
                    return StreamDecision(kind: kind, sourceIndex: index, sourceAbsoluteIndex: absoluteIndex, rule: rule.id ?? "#\(position + 1)", layer: layer, action: rule.action)
                }
            }
        }
        throw ResolutionError(kind: kind, sourceIndex: index, facts: describe(selector, in: facts))
    }

    private static func describe(_ selector: StreamSelector, in facts: SourceFacts) -> String {
        switch selector {
        case .video:
            guard let video = facts.video else { return "no video" }
            return "\(video.codec) \(video.width)x\(video.height)\(video.interlaced ? " interlaced" : "")\(video.hdr.map { " \($0.rawValue)" } ?? "")"
        case .audio(let index):
            guard let audio = facts.audio.first(where: { $0.index == index }) else { return "audio \(index)" }
            return "\(audio.codec)\(audio.profile.map { " \($0)" } ?? "") \(audio.channels)ch \(audio.languageTag ?? "und") \(audio.role.rawValue)\(audio.lossless ? " lossless" : "")\(audio.core ? " core" : "")"
        case .subtitle(let index):
            guard let subtitle = facts.subtitles.first(where: { $0.index == index }) else { return "subtitle \(index)" }
            return "\(subtitle.codec) \(subtitle.languageTag ?? "und")\(subtitle.forced ? " forced" : "")"
        }
    }
}

/// A stream no rule decided. Carries enough to write the rule that would.
public struct ResolutionError: Error, Hashable, Sendable, CustomStringConvertible {
    public var kind: StreamKind
    public var sourceIndex: Int
    public var facts: String

    public init(kind: StreamKind, sourceIndex: Int, facts: String) {
        self.kind = kind
        self.sourceIndex = sourceIndex
        self.facts = facts
    }

    public var description: String {
        "no rule decides \(kind.rawValue) \(sourceIndex) (\(facts))"
    }
}
