// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import Testing
@testable import SiloKit

/// Rules in layers, nearest first, resolved as one list is: the first rule that matches anywhere in
/// the stack decides.
struct LayerTests {
    static func layer(_ container: String, version: Int = 1, _ rules: [Rule]) -> RulesLayer {
        RulesLayer(subject: .container(container), version: version, digest: "sha256:\(container)-\(version)", rules: rules)
    }

    static let serial = "0000000000000003"
    static let series = "0000000000000001"

    @Test func aContainersRuleSpeaksFirstAndTheRestFallThrough() throws {
        // The serial keeps its lossless main mix; everything else is the household's to decide.
        let keepLossless = Self.layer(Self.serial, version: 4, [Rule(id: "keep-lossless", scope: .audio, conditions: [Condition(.audioLossless, .equal("true"))], action: .copy)])
        let recipe = try RecipeResolver.resolve(.episode, with: .household, layers: [keepLossless])
        let audio = recipe.audio
        #expect(audio[0].action == .copy)
        #expect(audio[0].rule == "keep-lossless")
        #expect(audio[0].layer == .layer(.container(Self.serial)), "the decision names its layer")
        #expect(audio[1].rule == "commentary", "a stream the container's rules do not decide falls through")
        #expect(audio[1].layer == .ruleset("household"))
        #expect(recipe.video?.layer == .ruleset("household"))
        #expect(recipe.layers == [RecipeLayer(subject: .container(Self.serial), version: 4, digest: "sha256:\(Self.serial)-4")], "and the recipe its stack above the ruleset")
        #expect(recipe.ruleset == RulesetRef(name: "household"))
    }

    @Test func theNearerContainerWins() throws {
        let serialCopies = Self.layer(Self.serial, [Rule(scope: .audio, conditions: [Condition(.audioRole, .equal("commentary"))], action: .copy)])
        let seriesDrops = Self.layer(Self.series, [Rule(scope: .audio, conditions: [Condition(.audioRole, .equal("commentary"))], action: .drop)])
        let recipe = try RecipeResolver.resolve(.episode, with: .household, layers: [serialCopies, seriesDrops])
        #expect(recipe.audio[1].action == .copy)
        #expect(recipe.audio[1].layer == .layer(.container(Self.serial)))
        #expect(recipe.audio[1].rule == "#1", "an unnamed rule is named by its place among its own layer's rules")
    }

    @Test func aConditionlessContainerRuleEndsItsScope() throws {
        let neverTouch = Self.layer(Self.serial, [Rule(scope: .audio, action: .copy)])
        let recipe = try RecipeResolver.resolve(.episode, with: .household, layers: [neverTouch])
        #expect(recipe.audio.allSatisfy { $0.action == .copy && $0.layer == .layer(.container(Self.serial)) })
        #expect(recipe.encoders.isEmpty, "no audio rule of the ruleset decided anything")
        #expect(recipe.subtitles.allSatisfy { $0.layer == .ruleset("household") }, "and only its own scope")
    }

    @Test func aRulePicksOneStreamByItsIndex() throws {
        let second = Rule(scope: .audio, conditions: [Condition(.audioIndex, .equal("2"))], action: .drop)
        let ruleset = Ruleset(name: "test", rules: [second, Rule(scope: .video, action: .copy), Rule(scope: .audio, action: .copy), Rule(scope: .subtitle, action: .copy)])
        let recipe = try RecipeResolver.resolve(.episode, with: ruleset)
        #expect(recipe.audio.map(\.action) == [.copy, .drop, .copy])
        #expect(Condition(.subtitleIndex, .greater(1)).holds(SourceFacts.episode.value(.subtitleIndex, for: .subtitle(2))))
        #expect(!Condition(.subtitleIndex, .greater(1)).holds(SourceFacts.episode.value(.subtitleIndex, for: .subtitle(1))))
    }

    @Test func aLayersRulesAreReadAsARulesetsAndNothingElse() throws {
        let rules = try RulesetFile.layerRules(from: Data(#"<rules><video id="keep"><when fact="kind" ne="episode"/><copy/></video></rules>"#.utf8))
        #expect(rules == [Rule(id: "keep", scope: .video, conditions: [Condition(.kind, .notEqual("episode"))], action: .copy)])
        #expect(throws: RulesetFileError.notALayerElement("output")) {
            try RulesetFile.layerRules(from: Data(#"<rules><output container="mp4"/></rules>"#.utf8))
        }
        #expect(RulesetFileError.notALayerElement("output").description == "<output> is not an element of a container's or a binding's rules")
        #expect(throws: RulesetFileError.notALayerElement("extraction")) {
            try RulesetFile.layerRules(from: Data(#"<rules><extraction embeddedAudio="true"/></rules>"#.utf8))
        }
        #expect(throws: RulesetFileError.notLayerRules) { try RulesetFile.layerRules(from: Data(#"<ruleset format="1" name="x"/>"#.utf8)) }
        #expect(throws: RulesetFileError.unknownFact("audio.bitrate")) {
            try RulesetFile.layerRules(from: Data(#"<rules><audio><when fact="audio.bitrate" is="1"/><copy/></audio></rules>"#.utf8))
        }
        #expect(throws: RulesetFileError.self) { try RulesetFile.layerRules(from: Data()) }
    }

    @Test func aStackIsSpeltInJSONAsTheSidecarSpellsIt() throws {
        let layer = RecipeLayer(subject: .binding("5b0e7c1a-3d2f-4e8a-9c41-7f0d2e6a91d2"), version: 2, digest: "sha256:77ab")
        let json = String(decoding: try JSONEncoder().encode(layer), as: UTF8.self)
        #expect(json.contains(#""binding":"5b0e7c1a-3d2f-4e8a-9c41-7f0d2e6a91d2""#) && !json.contains("container"))
        #expect(try JSONDecoder().decode(RecipeLayer.self, from: Data(json.utf8)) == layer)
        #expect(String(decoding: try JSONEncoder().encode(DecisionLayer.ruleset("household")), as: UTF8.self) == #"{"ruleset":"household"}"#)
        let recipe = try RecipeResolver.resolve(.episode, with: .household, layers: [Self.layer(Self.serial, [Rule(scope: .audio, action: .copy)])])
        #expect(try JSONDecoder().decode(Recipe.self, from: JSONEncoder().encode(recipe)) == recipe, "a recipe with its stack survives JSON")
    }
}
