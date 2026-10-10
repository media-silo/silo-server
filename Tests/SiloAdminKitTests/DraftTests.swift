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
        #expect(read.extraction == ExtractionPolicy())
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
}
