// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloClient

/// A ruleset being changed: its document's text as the operator edits it, and the version it was made
/// from, its base, which a store names so that the silo can refuse one that would land on a head the
/// operator never saw. A draft is the console's alone until it is stored or discarded.
public struct Draft: Hashable, Sendable, Identifiable {
    public let id: UUID
    /// The ruleset it is stored as.
    public var ruleset: String
    /// The version it was made from, nil for a ruleset the silo does not hold yet.
    public var base: Int?
    /// The base's branch, nil for a new ruleset.
    public var baseBranch: String?
    /// The base's text, what the draft's difference is read against; empty for a new ruleset.
    public var baseText: String
    public var text: String
    /// The standard version the draft takes in, when it is stored on a branch catching up with it.
    public var upToDateWith: Int?

    public init(ruleset: String, base: Int?, baseBranch: String?, baseText: String, text: String, upToDateWith: Int? = nil) {
        self.id = UUID()
        self.ruleset = ruleset
        self.base = base
        self.baseBranch = baseBranch
        self.baseText = baseText
        self.text = text
        self.upToDateWith = upToDateWith
    }

    /// A change from a version on screen, which is its base.
    public static func change(_ version: SiloClient.RulesetDocument) -> Draft {
        Draft(ruleset: version.name, base: version.version, baseBranch: version.branch, baseText: version.document, text: version.document)
    }

    /// A new ruleset from a copy of any version. The copy's `name` attribute is changed to the new
    /// name, as an edit the operator sees in the text and its difference.
    public static func copy(of version: SiloClient.RulesetDocument, as name: String) -> Draft {
        Draft(ruleset: name, base: nil, baseBranch: nil, baseText: version.document, text: renamed(version.document, to: name))
    }

    /// A new ruleset from the starter: the default extraction policy, a rule copying every stream of
    /// each scope, and the default output — a document that decides every stream, to change from.
    public static func starter(named name: String) -> Draft {
        Draft(ruleset: name, base: nil, baseBranch: nil, baseText: "", text: starterText(named: name))
    }

    /// A going back: an earlier version's document as a draft based on the head of its branch, so
    /// that storing it makes a new version saying what the earlier one said.
    public static func goingBack(to earlier: SiloClient.RulesetDocument, head: SiloClient.RulesetDocument) -> Draft {
        Draft(ruleset: head.name, base: head.version, baseBranch: head.branch, baseText: head.document, text: earlier.document)
    }

    /// The draft re-based on a version that landed since: its text as it is, read against the new base.
    public func rebased(on landed: SiloClient.RulesetDocument) -> Draft {
        var rebased = self
        rebased.base = landed.version
        rebased.baseBranch = landed.branch
        rebased.baseText = landed.document
        return rebased
    }

    /// Whether the text says anything other than its base.
    public var isChanged: Bool { text != baseText }

    /// The text's difference from its base, line by line.
    public var difference: [LineDifference.Line] { LineDifference.lines(from: baseText, to: text) }

    public static func starterText(named name: String) -> String {
        """
        <ruleset format="1" name="\(name)">
          <extraction embeddedAudio="false" subtitles="true" embeddedSubtitles="true"/>
          <video><copy/></video>
          <audio><copy/></audio>
          <subtitle><copy/></subtitle>
          <output container="mkv"/>
        </ruleset>

        """
    }

    /// The text with the root element's `name` attribute made `name`; untouched when it has none.
    static func renamed(_ text: String, to name: String) -> String {
        guard let root = text.range(of: "<ruleset\\b[^>]*>", options: .regularExpression),
              let attribute = text.range(of: #"\bname="[^"]*""#, options: .regularExpression, range: root)
        else { return text }
        var renamed = text
        renamed.replaceSubrange(attribute, with: #"name="\#(name)""#)
        return renamed
    }
}

/// Two texts' difference, line by line: what a store would change, shown before it is made.
public enum LineDifference {
    public struct Line: Hashable, Sendable {
        public enum Kind: Hashable, Sendable {
            case same, removed, added
        }

        public var kind: Kind
        public var text: String
    }

    /// Every line of both texts in order, each the same in both, removed from the first or added in
    /// the second.
    public static func lines(from old: String, to new: String) -> [Line] {
        let before = old.isEmpty ? [] : old.components(separatedBy: "\n")
        let after = new.isEmpty ? [] : new.components(separatedBy: "\n")
        let difference = after.difference(from: before)
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        var lines: [Line] = []
        var oldIndex = 0
        var newIndex = 0
        while oldIndex < before.count || newIndex < after.count {
            if oldIndex < before.count, removed.contains(oldIndex) {
                lines.append(Line(kind: .removed, text: before[oldIndex]))
                oldIndex += 1
            } else if newIndex < after.count, inserted.contains(newIndex) {
                lines.append(Line(kind: .added, text: after[newIndex]))
                newIndex += 1
            } else {
                if newIndex < after.count { lines.append(Line(kind: .same, text: after[newIndex])) }
                oldIndex += 1
                newIndex += 1
            }
        }
        return lines
    }

    /// Only the lines that changed.
    public static func changes(from old: String, to new: String) -> [Line] {
        lines(from: old, to: new).filter { $0.kind != .same }
    }
}
