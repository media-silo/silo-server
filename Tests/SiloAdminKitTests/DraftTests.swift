// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloAdminKit
import SiloClient
import SiloKit
import Testing

/// Drafts as the console starts them, and their difference from their base.
struct DraftTests {
    /// A version as the silo sends it.
    static func version(_ number: Int, branch: String = "standard", document: String) throws -> SiloClient.RulesetDocument {
        let object: [String: Any] = ["name": "household", "version": number, "branch": branch, "document": document]
        return try SiloClient.decoder.decode(SiloClient.RulesetDocument.self, from: JSONSerialization.data(withJSONObject: object))
    }

    static let household = """
        <ruleset format="1" name="household">
          <audio id="commentary"><when fact="audio.role" is="commentary"/><encode codec="aac" bitrate="160k" channels="2"/></audio>
          <audio><copy/></audio>
        </ruleset>
        """

    @Test func aChangeIsBasedOnTheVersionItWasMadeFrom() throws {
        var draft = Draft.change(try Self.version(3, document: Self.household))
        #expect(draft.base == 3 && draft.baseBranch == "standard" && !draft.isChanged)
        draft.text = draft.text.replacingOccurrences(of: #"bitrate="160k""#, with: #"bitrate="96k""#)
        let changes = draft.difference.filter { $0.kind != .same }
        #expect(changes.map(\.kind) == [.removed, .added], "the one line that changed")
        #expect(changes.last?.text.contains("96k") == true)
    }

    @Test func aCopyIsRenamedAsAnEditInTheText() throws {
        let draft = Draft.copy(of: try Self.version(3, document: Self.household), as: "trial")
        #expect(draft.ruleset == "trial" && draft.base == nil, "a new ruleset, based on nothing")
        #expect(draft.text.hasPrefix(#"<ruleset format="1" name="trial">"#))
        #expect(LineDifference.changes(from: draft.baseText, to: draft.text).map(\.text) == [
            #"<ruleset format="1" name="household">"#, #"<ruleset format="1" name="trial">"#,
        ], "the rename is the only difference, and shown")
    }

    @Test func theStarterDecidesEveryStreamWithTheDefaults() throws {
        let draft = Draft.starter(named: "fresh")
        let read = try RulesetFile.ruleset(from: Data(draft.text.utf8))
        #expect(read.name == "fresh")
        #expect(read.rules == Scope.allCases.map { Rule(scope: $0, action: .copy) })
        #expect(read.outputs == [OutputPolicy()])
    }

    @Test func goingBackIsAnEarlierDocumentBasedOnTheHead() throws {
        let earlier = try Self.version(1, document: "<one/>")
        let head = try Self.version(3, document: Self.household)
        let draft = Draft.goingBack(to: earlier, head: head)
        #expect(draft.base == 3 && draft.text == "<one/>" && draft.baseText == Self.household)
        let landed = try Self.version(4, document: "<four/>")
        let rebased = draft.rebased(on: landed)
        #expect(rebased.base == 4 && rebased.baseText == "<four/>" && rebased.text == "<one/>", "the text kept, the base moved")
    }

    /// The list of rulesets as the silo sends it, `household` with versions on the standard and a branch.
    static func summaries(standard: [Int], trial: [Int] = []) throws -> [SiloClient.RulesetSummary] {
        let versions = standard.map { ["version": $0, "branch": "standard", "presentations": 0] as [String: Any] }
            + trial.map { ["version": $0, "branch": "trial", "presentations": 0] as [String: Any] }
        let object: [[String: Any]] = [["name": "household", "version": (standard + trial).max() ?? 0, "standard": standard.max() as Any, "versions": versions]]
        return try SiloClient.decoder.decode([SiloClient.RulesetSummary].self, from: JSONSerialization.data(withJSONObject: object))
    }

    @Test func aDraftIsBehindOnceItsBranchHasMoved() throws {
        let draft = Draft.change(try Self.version(3, document: Self.household))
        #expect(!draft.isBehind(in: try Self.summaries(standard: [1, 2, 3])), "based on the head")
        #expect(draft.isBehind(in: try Self.summaries(standard: [1, 2, 3, 4])), "version 4 stored on the standard since")
        #expect(!draft.isBehind(in: try Self.summaries(standard: [1, 2, 3], trial: [4])), "a version on another branch moves nothing")
        #expect(!Draft.starter(named: "fresh").isBehind(in: try Self.summaries(standard: [1])), "a new ruleset's draft is never behind")
    }

    @Test func aDraftIsReadByTheConsoleWithTheSilosReader() throws {
        var draft = Draft.change(try Self.version(3, document: Self.household))
        guard case .reading(let reading) = draft.reading else { Issue.record("the version reads"); return }
        #expect(reading.rules.map(\.name) == ["commentary", "#2"], "named as a recipe calls them")
        #expect(reading.rules.first?.conditions.first?.text == "audio.role is commentary")
        #expect(reading.rules.last?.action == .copy)

        draft.text = draft.text.replacingOccurrences(of: #"<audio><copy/></audio>"#, with: #"<audio<copy/></audio>"#)
        guard case .refused(let reason) = draft.reading else { Issue.record("the text no longer reads"); return }
        #expect(reason.hasPrefix("malformed XML: line ") && reason.contains(", column "), "naming where reading stopped: \(reason)")
    }

    @Test func draftsOutliveTheStoreThatKeptThem() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "drafts-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        var draft = Draft.change(try Self.version(3, document: Self.household))
        let store = DraftStore(file: file)
        try store.save(draft, for: "s1")
        draft.text += "<!-- edited -->"
        try store.save(draft, for: "s1")
        try store.save(Draft.starter(named: "fresh"), for: "s1")

        let reopened = DraftStore(file: file)
        #expect(reopened.drafts(of: "s1").map(\.ruleset) == ["fresh", "household"], "both kept, by ruleset")
        #expect(reopened.draft(draft.id, of: "s1")?.text.hasSuffix("<!-- edited -->") == true, "the later save over the earlier")
        #expect(reopened.draft(draft.id, of: "s1")?.base == 3)
        try reopened.remove(draft.id, of: "s1")
        #expect(DraftStore(file: file).drafts(of: "s1").map(\.ruleset) == ["fresh"])
    }
}
