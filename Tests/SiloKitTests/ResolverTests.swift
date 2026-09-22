// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import Testing
@testable import SiloKit

struct ResolverTests {
    @Test func theThreeRulesDecideAnEpisode() throws {
        let recipe = try RecipeResolver.resolve(.episode, with: .household)
        #expect(recipe.ruleset.description == "household")
        #expect(recipe.decisions.map(\.rule) == ["#4", "lossless-main", "commentary", "#5", "#6", "#6"])
        #expect(recipe.video?.action == .copy)
        #expect(recipe.audio[0].action == .encode(EncodeSettings(codec: "flac")))
        #expect(recipe.audio[1].action == .encode(EncodeSettings(codec: "aac", bitrate: "160k", channels: 2)))
        #expect(recipe.audio[2].action == .copy)
        #expect(recipe.subtitles.allSatisfy { $0.action == .copy })
        #expect(recipe.layout.kinds == [.video, .audio, .audio, .audio, .subtitle, .subtitle])
        #expect(recipe.layout.streams.map(\.outputAbsoluteIndex) == [0, 1, 2, 3, 4, 5])
        #expect(recipe.encoders == ["flac", "aac"])
        #expect(recipe.warnings.isEmpty)
    }

    @Test func aSmallExtraIsReencoded() throws {
        let recipe = try RecipeResolver.resolve(.featurette, with: .household)
        #expect(recipe.video?.rule == "small-extras")
        #expect(recipe.video?.action == .encode(EncodeSettings(codec: "libx264", preset: "slow", crf: 22, pixelFormat: "yuv420p", filters: [.deinterlace(.auto)])))
        #expect(recipe.audio.map(\.rule) == ["#5"])
    }

    @Test func theFirstMatchingRuleWins() throws {
        // A lossless commentary: lossless-main is written first but excludes commentaries, so
        // the commentary rule decides. Reorder the two and the answer changes, which is the
        // point of order being the only precedence there is.
        var facts = SourceFacts.episode
        facts.audio[1].codec = "truehd"
        facts.audio[1].lossless = true
        let recipe = try RecipeResolver.resolve(facts, with: .household)
        #expect(recipe.audio[1].rule == "commentary")

        var reordered = Ruleset.household
        reordered.rules[1].conditions = [Condition(.audioLossless, .equal("true"))]
        let byLossless = try RecipeResolver.resolve(facts, with: reordered)
        #expect(byLossless.audio[1].rule == "lossless-main")
    }

    @Test func aStreamNoRuleDecidesIsAnError() {
        var ruleset = Ruleset.household
        ruleset.rules.removeLast(3)
        #expect(throws: ResolutionError(kind: .video, sourceIndex: 1, facts: "h264 1920x1080")) {
            try RecipeResolver.resolve(.episode, with: ruleset)
        }
        ruleset.rules.append(Rule(scope: .video, action: .copy))
        #expect(throws: ResolutionError(kind: .audio, sourceIndex: 3, facts: "ac3 2ch eng main")) {
            try RecipeResolver.resolve(.episode, with: ruleset)
        }
    }

    @Test func aDroppedStreamRenumbersWhatFollowsAndWarnsAboutAMappedOne() throws {
        var ruleset = Ruleset.household
        ruleset.rules.insert(Rule(id: "no-lossless", scope: .audio, conditions: [Condition(.audioLossless, .equal("true"))], action: .drop), at: 0)
        ruleset.rules.insert(Rule(id: "no-forced", scope: .subtitle, conditions: [Condition(.subtitleForced, .equal("true"))], action: .drop), at: 0)
        let mappings = [TrackMapping(feature: "commentary1", audio: 2), TrackMapping(feature: "music1", audio: 1), TrackMapping(feature: "signs", subtitle: 2)]
        let recipe = try RecipeResolver.resolve(.episode, with: ruleset, mappings: mappings)
        #expect(recipe.layout.kinds == [.video, .audio, .audio, .subtitle])
        #expect(recipe.layout.outputIndex(of: .audio, sourceIndex: 2) == 1)
        #expect(recipe.layout.outputIndex(of: .audio, sourceIndex: 3) == 2)
        #expect(recipe.layout.outputIndex(of: .audio, sourceIndex: 1) == nil)
        #expect(recipe.tracks(for: mappings) == [TrackMapping(feature: "commentary1", audio: 1)])
        #expect(recipe.warnings == [
            "feature music1 is mapped to audio 1, which this recipe drops",
            "feature signs is mapped to subtitle 2, which this recipe drops",
        ])
        #expect(recipe.kept.map(\.rule) == ["#6", "commentary", "#7", "#8"])
    }

    @Test func aRecipeSurvivesJSON() throws {
        let recipe = try RecipeResolver.resolve(.featurette, with: .household, mappings: [TrackMapping(feature: "c", audio: 1)])
        let data = try JSONEncoder().encode(recipe)
        #expect(try JSONDecoder().decode(Recipe.self, from: data) == recipe)
    }
}
