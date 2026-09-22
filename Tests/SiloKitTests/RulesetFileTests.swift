// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import Testing
@testable import SiloKit

struct RulesetFileTests {
    @Test func theExampleFileIsTheProposalsRules() throws {
        #expect(try Ruleset.exampleFile() == .household)
    }

    @Test func aRulesetSurvivesTheFile() throws {
        var ruleset = Ruleset.household
        ruleset.version = 7
        ruleset.extraction.includeSubtitles = false
        ruleset.rules.append(Rule(
            id: "mobile", scope: .video,
            conditions: [Condition(.profile, .equal("mobile")), Condition(.videoFrameRate, .greaterOrEqual(29.97))],
            action: .encode(EncodeSettings(codec: "libx265", crf: 28, filters: [.scale(width: 1280, height: nil), .custom("hqdn3d")], options: ["x265-params": "log-level=error"]))
        ))
        ruleset.rules.append(Rule(scope: .subtitle, conditions: [Condition(.subtitleForced, .equal("true"))], action: .drop))
        let data = RulesetFile.data(for: ruleset)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("<ruleset format=\"1\" name=\"household\" version=\"7\">"))
        #expect(text.contains("<when fact=\"video.width\" lt=\"576\"/>"))
        #expect(text.contains("<when fact=\"video.frameRate\" ge=\"29.97\"/>"))
        #expect(text.contains("<scale width=\"1280\"/>"))
        #expect(text.contains("<option name=\"x265-params\" value=\"log-level=error\"/>"))
        #expect(try RulesetFile.ruleset(from: data) == ruleset)
    }

    @Test(arguments: [
        ("<when fact=\"audio.bitrate\" is=\"1\"/><copy/>", RulesetFileError.unknownFact("audio.bitrate")),
        ("<when fact=\"video.width\" lt=\"1\"/><copy/>", RulesetFileError.factOutOfScope(fact: "video.width", scope: .audio)),
        ("<when fact=\"audio.codec\" lt=\"1\"/><copy/>", RulesetFileError.notNumeric(fact: "audio.codec", operator: "lt")),
        ("<when fact=\"audio.codec\" is=\"a\" ne=\"b\"/><copy/>", RulesetFileError.oneTestRequired(rule: "r", fact: "audio.codec")),
        ("<when fact=\"audio.channels\" gt=\"many\"/><copy/>", RulesetFileError.invalidValue(element: "when", attribute: "gt", value: "many")),
        ("<when fact=\"audio.codec\" is=\"a\"/>", RulesetFileError.noAction(rule: "r")),
        ("<copy/><drop/>", RulesetFileError.multipleActions(rule: "r")),
        ("<encode/>", RulesetFileError.missingAttribute(element: "encode", attribute: "codec")),
        ("<encode codec=\"aac\"><deinterlace mode=\"sometimes\"/></encode>", RulesetFileError.invalidValue(element: "deinterlace", attribute: "mode", value: "sometimes")),
        ("<unless/><copy/>", RulesetFileError.unknownElement("unless")),
    ])
    func aRuleThatCannotBeReadIsRefused(body: String, expected: RulesetFileError) {
        let xml = "<ruleset format=\"1\" name=\"t\"><audio id=\"r\">\(body)</audio></ruleset>"
        #expect(throws: expected) { try RulesetFile.ruleset(from: Data(xml.utf8)) }
    }

    @Test func aDocumentThatIsNotARulesetIsRefused() {
        #expect(throws: RulesetFileError.notARuleset) { try RulesetFile.ruleset(from: Data("<rules/>".utf8)) }
        #expect(throws: RulesetFileError.unsupportedFormat(2)) { try RulesetFile.ruleset(from: Data("<ruleset format=\"2\" name=\"t\"/>".utf8)) }
        #expect(throws: RulesetFileError.unknownElement("rule")) { try RulesetFile.ruleset(from: Data("<ruleset format=\"1\" name=\"t\"><rule/></ruleset>".utf8)) }
        #expect(throws: RulesetFileError.self) { try RulesetFile.ruleset(from: Data("<ruleset format=\"1\" name=\"t\"><audio>".utf8)) }
    }

    @Test func anEmptyRulesetHasTheToolsDefaults() throws {
        let ruleset = try RulesetFile.ruleset(from: Data("<ruleset format=\"1\" name=\"t\"/>".utf8))
        #expect(ruleset.extraction == ExtractionPolicy())
        #expect(ruleset.output == OutputPolicy())
        #expect(ruleset.rules.isEmpty)
        #expect(ruleset.version == nil)
    }
}
