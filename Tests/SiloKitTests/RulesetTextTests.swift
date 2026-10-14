// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloKit
import Testing

/// A ruleset's document edited element by element: each edit changes the elements it touches and
/// leaves every other character as the person wrote it.
struct RulesetTextTests {
    static let household = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ruleset format="1" name="household">
          <!-- Keep every lossless main mix as it is. -->
          <audio id="lossless-main"><when fact="audio.role" is="main"/><when fact="audio.lossless" is="true"/><copy/></audio>

          <!-- Commentaries are speech: AAC is plenty. -->
          <audio id='commentary'>
            <when fact="audio.role" is="commentary"/>
            <encode codec="aac" bitrate="160k" channels="2"/>
          </audio>
          <video><copy/></video>

          <!-- Everything else as it came. -->
          <audio><copy/></audio>
          <subtitle><copy/></subtitle>
          <output container="mkv"/>
        </ruleset>

        """

    /// The lines of a text other than those given.
    private func lines(_ text: String, without dropped: Set<String>) -> [String] {
        text.components(separatedBy: "\n").filter { !dropped.contains($0) }
    }

    @Test func everyRuleAndOutputIsFoundWithItsComments() throws {
        let text = try RulesetText(Self.household)
        #expect(text.rules(of: .audio).map(\.rule.id) == ["lossless-main", "commentary", nil])
        #expect(text.outputs.count == 1)
        let commentary = text.rules(of: .audio)[1].element
        let unit = String(decoding: Array(Self.household.utf8)[commentary.unit], as: UTF8.self)
        #expect(unit.hasPrefix("  <!-- Commentaries are speech: AAC is plenty. -->\n  <audio id='commentary'>"), "its comment and its whole lines")
        #expect(unit.hasSuffix("  </audio>\n"))
        #expect(commentary.indentation == "  ")
        let video = text.rules(of: .video)[0].element
        #expect(String(decoding: Array(Self.household.utf8)[video.unit], as: UTF8.self) == "  <video><copy/></video>\n", "no comment of its own")
    }

    @Test func aMoveLeavesEverythingElseAsItWas() throws {
        let moved = try RulesetText(Self.household).movingRule(1, of: .audio, to: 0)
        let read = try RulesetText(moved)
        #expect(read.rules(of: .audio).map(\.rule.id) == ["commentary", "lossless-main", nil], "the two rules swapped")
        #expect(moved.contains("""
              <!-- Commentaries are speech: AAC is plenty. -->
              <audio id='commentary'>
            """), "the comment above the commentary rule still, and its quoting as written")
        #expect(moved.components(separatedBy: "\n").sorted() == Self.household.components(separatedBy: "\n").sorted(), "every line as it was, only their order changed")

        let toTheEnd = try RulesetText(Self.household).movingRule(0, of: .audio, to: 3)
        #expect(try RulesetText(toTheEnd).rules(of: .audio).map(\.rule.id) == ["commentary", nil, "lossless-main"], "after the scope's last rule")
        #expect(toTheEnd.components(separatedBy: "\n").sorted() == Self.household.components(separatedBy: "\n").sorted())
        #expect(try RulesetText(Self.household).movingRule(1, of: .audio, to: 2) == Self.household, "a move to where it is changes nothing")
    }

    @Test func anEditBesideACommentLeavesTheCommentAsItWas() throws {
        let text = try RulesetText(Self.household)
        var rule = text.rules(of: .audio)[1].rule
        rule.action = .encode(EncodeSettings(codec: "aac", bitrate: "96k", channels: 2))
        let edited = text.replacingRule(1, of: .audio, with: rule)
        let read = try RulesetText(edited)
        #expect(read.rules(of: .audio)[1].rule == rule, "the document reads with the change made")
        let before = Self.household.components(separatedBy: "\n")
        let after = edited.components(separatedBy: "\n")
        #expect(after.prefix(5) == before.prefix(5), "the comment above, and the blank line, as they were")
        #expect(after.suffix(8) == before.suffix(8), "and everything after the rule")
        #expect(after.contains(#"  <audio id="commentary"><when fact="audio.role" is="commentary"/><encode codec="aac" bitrate="96k" channels="2"/></audio>"#), "the rule rewritten where it stood: \(after)")
    }

    @Test func anAddedRuleTakesItsNeighboursIndentation() throws {
        let added = try RulesetText(Self.household).addingRule(Rule(scope: .subtitle, conditions: [Condition(.subtitleForced, .equal("true"))], action: .copy))
        #expect(lines(added, without: Set(Self.household.components(separatedBy: "\n"))) == [
            #"  <subtitle><when fact="subtitle.forced" is="true"/><copy/></subtitle>"#,
        ], "one line added")
        #expect(try RulesetText(added).rules(of: .subtitle).count == 2)
        let output = try RulesetText(Self.household).addingOutput(OutputPolicy(profile: "mobile", container: "mp4"))
        #expect(lines(output, without: Set(Self.household.components(separatedBy: "\n"))) == [#"  <output profile="mobile" container="mp4"/>"#])
        #expect(try RulesetText(output).outputs.last?.output == OutputPolicy(profile: "mobile", container: "mp4"))
    }

    @Test func aDeletionTakesItsCommentsWithIt() throws {
        let deleted = try RulesetText(Self.household).deletingRule(0, of: .audio)
        #expect(!deleted.contains("Keep every lossless main mix"), "its comment goes with it")
        #expect(deleted.contains("<!-- Commentaries are speech: AAC is plenty. -->"), "and no other")
        #expect(try RulesetText(deleted).rules(of: .audio).map(\.rule.id) == ["commentary", nil])
    }

    @Test func aDocumentTheReaderRefusesOffersNoEdit() {
        #expect(throws: RulesetFileError.unknownFact("subtitle.forcd")) {
            try RulesetText(Self.household.replacingOccurrences(of: "subtitle.forced", with: "subtitle.forcd").replacingOccurrences(of: "<subtitle><copy/></subtitle>", with: #"<subtitle><when fact="subtitle.forcd" is="true"/><copy/></subtitle>"#))
        }
    }

    @Test func aFactOffersTheTestsAndValuesItTakes() {
        #expect(FactKey.audioChannels.tests == ["is", "ne", "in", "lt", "le", "gt", "ge"])
        #expect(FactKey.audioRole.tests == ["is", "ne", "in"])
        #expect(FactKey.audioRole.values == AudioRole.allCases.map(\.rawValue))
        #expect(FactKey.audioLanguage.values == nil, "a language is open")
        #expect(Condition.Test(attribute: "ge", value: "6") == .greaterOrEqual(6))
        #expect(Condition.Test(attribute: "in", value: "en, fr") == .oneOf(["en", "fr"]))
        #expect(Condition.Test(attribute: "lt", value: "six") == nil, "a comparison needs a number")
    }
}
