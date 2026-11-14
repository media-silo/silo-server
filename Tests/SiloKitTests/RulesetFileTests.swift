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
        ruleset.rules.append(
            Rule(
                id: "mobile",
                scope: .video,
                conditions: [
                    Condition(.profile, .equal("mobile")), Condition(.videoFrameRate, .greaterOrEqual(29.97)),
                ],
                action: .encode(
                    EncodeSettings(
                        codec: "libx265",
                        crf: 28,
                        filters: [.scale(width: 1280, height: nil), .custom("hqdn3d")],
                        options: ["x265-params": "log-level=error"]
                    )
                )
            )
        )
        ruleset.rules.append(
            Rule(scope: .subtitle, conditions: [Condition(.subtitleForced, .equal("true"))], action: .drop)
        )
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
        (
            "<when fact=\"video.width\" lt=\"1\"/><copy/>",
            RulesetFileError.factOutOfScope(fact: "video.width", scope: .audio)
        ),
        (
            "<when fact=\"audio.codec\" lt=\"1\"/><copy/>",
            RulesetFileError.notNumeric(fact: "audio.codec", operator: "lt")
        ),
        (
            "<when fact=\"audio.codec\" is=\"a\" ne=\"b\"/><copy/>",
            RulesetFileError.oneTestRequired(rule: "r", fact: "audio.codec")
        ),
        (
            "<when fact=\"audio.channels\" gt=\"many\"/><copy/>",
            RulesetFileError.invalidValue(element: "when", attribute: "gt", value: "many")
        ),
        ("<when fact=\"audio.codec\" is=\"a\"/>", RulesetFileError.noAction(rule: "r")),
        ("<copy/><drop/>", RulesetFileError.multipleActions(rule: "r")),
        ("<encode/>", RulesetFileError.missingAttribute(element: "encode", attribute: "codec")),
        (
            "<encode codec=\"aac\"><deinterlace mode=\"sometimes\"/></encode>",
            RulesetFileError.invalidValue(element: "deinterlace", attribute: "mode", value: "sometimes")
        ),
        ("<unless/><copy/>", RulesetFileError.unknownElement("unless")),
    ])
    func aRuleThatCannotBeReadIsRefused(body: String, expected: RulesetFileError) {
        let xml = "<ruleset format=\"1\" name=\"t\"><audio id=\"r\">\(body)</audio></ruleset>"
        #expect(throws: expected) { try RulesetFile.ruleset(from: Data(xml.utf8)) }
    }

    /// An unnamed rule is refused by the name a recipe would give it: `#n`, its position among the
    /// document's rules of every scope, outputs not counted. A layer's rules count among themselves.
    @Test func anUnnamedRuleIsRefusedByItsPosition() {
        let ruleset = """
            <ruleset format="1" name="t"><video><copy/></video><output container="mkv"/><audio id="named"><copy/></audio>\
            <audio><drop/></audio><subtitle><copy/></subtitle><audio><when fact="audio.codec" is="ac3"/></audio></ruleset>
            """
        let refusal = #expect(throws: RulesetFileError.noAction(rule: "#5")) {
            try RulesetFile.ruleset(from: Data(ruleset.utf8))
        }
        #expect(refusal?.description == "rule #5 has no <copy/>, <drop/> or <encode>")
        let layer = #"<rules><audio><copy/></audio><audio><copy/><drop/></audio></rules>"#
        #expect(throws: RulesetFileError.multipleActions(rule: "#2")) {
            try RulesetFile.layerRules(from: Data(layer.utf8))
        }
    }

    /// A recipe names the rule that decided a stream by its id, so an id names one rule of the
    /// document, whatever its scope, and is never the `#n` an unnamed rule is named by.
    @Test func aRuleIDNamesOneRule() throws {
        func read(_ rules: String) throws -> Ruleset {
            try RulesetFile.ruleset(from: Data(#"<ruleset format="1" name="t">\#(rules)</ruleset>"#.utf8))
        }
        let shared = #expect(throws: RulesetFileError.sharedRuleID("commentary")) {
            try read(#"<audio id="commentary"><drop/></audio><subtitle id="commentary"><copy/></subtitle>"#)
        }
        #expect(shared?.description == "two rules are called commentary")
        let positional = #expect(throws: RulesetFileError.positionalRuleID("#3")) {
            try read(##"<audio id="#3"><copy/></audio>"##)
        }
        #expect(positional?.description == "#3 is how an unnamed rule is named by its position, and cannot be an id")
        #expect(try read(##"<audio id="#main"><copy/></audio><audio id="#"><drop/></audio>"##).rules.count == 2)
        #expect(throws: RulesetFileError.sharedRuleID("keep")) {
            try RulesetFile.layerRules(
                from: Data(#"<rules><video id="keep"><copy/></video><video id="keep"><drop/></video></rules>"#.utf8)
            )
        }
    }

    @Test func aDocumentThatIsNotARulesetIsRefused() {
        #expect(throws: RulesetFileError.notARuleset) { try RulesetFile.ruleset(from: Data("<rules/>".utf8)) }
        #expect(throws: RulesetFileError.unsupportedFormat(2)) {
            try RulesetFile.ruleset(from: Data("<ruleset format=\"2\" name=\"t\"/>".utf8))
        }
        #expect(throws: RulesetFileError.unknownElement("rule")) {
            try RulesetFile.ruleset(from: Data("<ruleset format=\"1\" name=\"t\"><rule/></ruleset>".utf8))
        }
        #expect(
            throws: RulesetFileError.unknownElement("extraction"),
            "what a source keeps is said by drop rules, not an element of its own"
        ) {
            try RulesetFile.ruleset(
                from: Data("<ruleset format=\"1\" name=\"t\"><extraction subtitles=\"false\"/></ruleset>".utf8)
            )
        }
        #expect(throws: RulesetFileError.self) {
            try RulesetFile.ruleset(from: Data("<ruleset format=\"1\" name=\"t\"><audio>".utf8))
        }
    }

    @Test func anAttributeTheReaderDoesNotKnowIsRefused() {
        let misspelt = RulesetFileError.unknownAttribute(element: "encode", attribute: "bitrat")
        #expect(throws: misspelt, "a misspelt bitrate is refused, not read as the codec's default") {
            try RulesetFile.ruleset(
                from: Data(
                    #"<ruleset format="1" name="t"><audio><encode codec="aac" bitrat="96k"/></audio></ruleset>"#.utf8
                )
            )
        }
        #expect(misspelt.description == "bitrat is not an attribute of <encode>")
        #expect(throws: RulesetFileError.unknownAttribute(element: "ruleset", attribute: "verison")) {
            try RulesetFile.ruleset(from: Data(#"<ruleset format="1" name="t" verison="2"/>"#.utf8))
        }
        #expect(throws: RulesetFileError.unknownAttribute(element: "output", attribute: "codec")) {
            try RulesetFile.ruleset(from: Data(#"<ruleset format="1" name="t"><output codec="hevc"/></ruleset>"#.utf8))
        }
        #expect(throws: RulesetFileError.unknownAttribute(element: "rules", attribute: "name")) {
            try RulesetFile.layerRules(from: Data(#"<rules name="x"/>"#.utf8))
        }
        #expect(throws: RulesetFileError.unknownAttribute(element: "scale", attribute: "hieght")) {
            try RulesetFile.layerRules(
                from: Data(
                    #"<rules><video><encode codec="libx265"><scale hieght="720"/></encode></video></rules>"#.utf8
                )
            )
        }
    }

    @Test(arguments: [
        (#"<when fact="video.hdr" is="hdr"/>"#, RulesetFileError.notAValueOf(fact: "video.hdr", value: "hdr")),
        (#"<when fact="extra" ne="yes"/>"#, RulesetFileError.notAValueOf(fact: "extra", value: "yes")),
        (#"<when fact="format" in="dvd, hddvd"/>"#, RulesetFileError.notAValueOf(fact: "format", value: "hddvd")),
    ])
    func aValueItsFactNeverTakesIsRefused(condition: String, expected: RulesetFileError) {
        let xml = #"<ruleset format="1" name="t"><video>\#(condition)<copy/></video></ruleset>"#
        #expect(throws: expected) { try RulesetFile.ruleset(from: Data(xml.utf8)) }
    }

    @Test func aValueItsFactCanTakeIsRead() throws {
        let xml = #"""
            <ruleset format="1" name="t">
            <video><when fact="video.hdr" in="hdr10, hlg"/><when fact="extra" is="false"/><copy/></video>
            <audio><when fact="audio.role" ne="commentary"/><when fact="audio.codec" is="anything"/><copy/></audio>
            </ruleset>
            """#
        #expect(try RulesetFile.ruleset(from: Data(xml.utf8)).rules.count == 2)
        #expect(
            RulesetFileError.notAValueOf(fact: "extra", value: "yes").description
                == #""yes" is not a value "extra" takes: true, false"#
        )
    }

    @Test(arguments: [
        (
            #"<ruleset format="0" name="t"/>"#,
            RulesetFileError.invalidValue(element: "ruleset", attribute: "format", value: "0")
        ),
        (
            #"<ruleset format="-1" name="t"/>"#,
            RulesetFileError.invalidValue(element: "ruleset", attribute: "format", value: "-1")
        ),
        (
            #"<ruleset format="1" name="t"><output container="mp4"/></ruleset>"#,
            RulesetFileError.invalidValue(element: "output", attribute: "container", value: "mp4")
        ),
        (
            #"<ruleset format="1" name="t"><video><encode codec="libx265"><scale/></encode></video></ruleset>"#,
            RulesetFileError.scaleWithoutSize
        ),
        (
            #"<ruleset format="1" name="t"><video><encode codec="libx265"><filter> </filter></encode></video></ruleset>"#,
            RulesetFileError.emptyFilter
        ),
    ])
    func aValueFfmpegWouldFailOnIsRefusedWhenRead(xml: String, expected: RulesetFileError) {
        #expect(throws: expected) { try RulesetFile.ruleset(from: Data(xml.utf8)) }
    }

    @Test func theContainersAreMatroska() throws {
        let xml =
            #"<ruleset format="1" name="t"><output container="mkv"/><output profile="m" container="matroska"/></ruleset>"#
        let outputs = try RulesetFile.ruleset(from: Data(xml.utf8)).outputs
        #expect(outputs.map(\.ffmpegFormat) == ["matroska", "matroska"])
        #expect(outputs.map(\.fileExtension) == ["mkv", "mkv"])
        #expect(RulesetFileError.scaleWithoutSize.description == "<scale> needs a width, a height or both")
        #expect(RulesetFileError.emptyFilter.description == "<filter> has no filter in it")
    }

    @Test func anEmptyRulesetHasTheToolsDefaults() throws {
        let ruleset = try RulesetFile.ruleset(from: Data("<ruleset format=\"1\" name=\"t\"/>".utf8))
        #expect(ruleset.outputs == [OutputPolicy()], "one unqualified mkv")
        #expect(ruleset.rules.isEmpty)
        #expect(ruleset.version == nil)
    }

    @Test func aRulesetMakesEachOutputItDeclares() throws {
        let xml = """
            <ruleset format="1" name="t">
                <output container="mkv"/>
                <video><copy/></video>
                <output profile="mobile" container="matroska"/>
            </ruleset>
            """
        let ruleset = try RulesetFile.ruleset(from: Data(xml.utf8))
        #expect(
            ruleset.outputs == [
                OutputPolicy(container: "mkv"), OutputPolicy(profile: "mobile", container: "matroska"),
            ],
            "in the document's order"
        )
        #expect(
            try RulesetFile.ruleset(from: RulesetFile.data(for: ruleset)).outputs == ruleset.outputs,
            "and they survive the file"
        )
    }

    @Test func anOutputMadeTwiceIsRefused() {
        #expect(throws: RulesetFileError.outputMadeTwice(profile: "mobile")) {
            try RulesetFile.ruleset(
                from: Data(
                    #"<ruleset format="1" name="t"><output profile="mobile"/><output profile="mobile" container="matroska"/></ruleset>"#
                        .utf8
                )
            )
        }
        #expect(throws: RulesetFileError.outputMadeTwice(profile: nil)) {
            try RulesetFile.ruleset(
                from: Data(#"<ruleset format="1" name="t"><output/><output container="matroska"/></ruleset>"#.utf8)
            )
        }
        #expect(RulesetFileError.outputMadeTwice(profile: "mobile").description == "the profile mobile is made twice")
        #expect(RulesetFileError.outputMadeTwice(profile: nil).description == "the unqualified output is made twice")
    }
}
