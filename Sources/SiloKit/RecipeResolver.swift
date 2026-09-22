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
    /// `mappings` is the assignment's feature map, used only to warn when a mapped stream is
    /// dropped; the renumbered map is `recipe.tracks(for:)`.
    public static func resolve(_ facts: SourceFacts, with ruleset: Ruleset, mappings: [TrackMapping] = []) throws(ResolutionError) -> Recipe {
        var decisions: [StreamDecision] = []

        if let video = facts.video {
            decisions.append(try decide(.video, index: 1, absoluteIndex: video.absoluteIndex, selector: .video, facts: facts, ruleset: ruleset))
        }
        for audio in facts.audio {
            decisions.append(try decide(.audio, index: audio.index, absoluteIndex: audio.absoluteIndex, selector: .audio(audio.index), facts: facts, ruleset: ruleset))
        }
        for subtitle in facts.subtitles {
            decisions.append(try decide(.subtitle, index: subtitle.index, absoluteIndex: subtitle.absoluteIndex, selector: .subtitle(subtitle.index), facts: facts, ruleset: ruleset))
        }

        let layout = OutputLayout(keeping: decisions)
        var warnings: [String] = []
        for mapping in mappings {
            if let audio = mapping.audio, layout.outputIndex(of: .audio, sourceIndex: audio) == nil {
                warnings.append("feature \(mapping.feature) is mapped to audio \(audio), which this recipe drops")
            }
            if let subtitle = mapping.subtitle, layout.outputIndex(of: .subtitle, sourceIndex: subtitle) == nil {
                warnings.append("feature \(mapping.feature) is mapped to subtitle \(subtitle), which this recipe drops")
            }
        }
        if facts.video == nil {
            warnings.append("the source has no video stream")
        }

        return Recipe(ruleset: RulesetRef(ruleset), decisions: decisions, output: ruleset.output, layout: layout, warnings: warnings)
    }

    private static func decide(
        _ kind: StreamKind, index: Int, absoluteIndex: Int, selector: StreamSelector,
        facts: SourceFacts, ruleset: Ruleset
    ) throws(ResolutionError) -> StreamDecision {
        let scope: Scope = switch kind {
        case .video: .video
        case .audio: .audio
        case .subtitle: .subtitle
        }
        for (position, rule) in ruleset.rules(in: scope) {
            let holds = rule.conditions.allSatisfy { $0.holds(facts.value($0.fact, for: selector)) }
            if holds {
                return StreamDecision(kind: kind, sourceIndex: index, sourceAbsoluteIndex: absoluteIndex, rule: rule.id ?? "#\(position)", action: rule.action)
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
            return "\(audio.codec)\(audio.profile.map { " \($0)" } ?? "") \(audio.channels)ch \(audio.language ?? "und") \(audio.role.rawValue)\(audio.lossless ? " lossless" : "")\(audio.core ? " core" : "")"
        case .subtitle(let index):
            guard let subtitle = facts.subtitles.first(where: { $0.index == index }) else { return "subtitle \(index)" }
            return "\(subtitle.codec) \(subtitle.language ?? "und")\(subtitle.forced ? " forced" : "")"
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
