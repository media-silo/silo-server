// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloClient
import SiloKit

/// A ruleset being changed: its document's text as the operator edits it, and the version it was made
/// from, its base, which a store names so that the silo can refuse one that would land on a head the
/// operator never saw. A draft is the console's working copy, kept on this Mac by a `DraftStore`
/// until it is stored or discarded; the silo holds versions, and never a draft.
public struct Draft: Hashable, Sendable, Identifiable, Codable {
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
    /// When the text last changed.
    public var edited: Date

    public init(ruleset: String, base: Int?, baseBranch: String?, baseText: String, text: String, upToDateWith: Int? = nil, edited: Date = .now) {
        self.id = UUID()
        self.edited = edited
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

    /// A new ruleset from the starter: a rule copying every stream of each scope, and the default
    /// output — a document that decides every stream, to change from.
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

    /// The branch it is listed under: its base's, the standard for a draft of a new ruleset.
    public var branch: String { baseBranch ?? "standard" }

    /// Whether its base is no longer its branch's head, as the silo's list of rulesets says: a store
    /// would be refused, so it is to be re-based first. A new ruleset's draft is never behind.
    public func isBehind(in rulesets: [SiloClient.RulesetSummary]) -> Bool {
        guard let base, let summary = rulesets.first(where: { $0.name == ruleset }) else { return false }
        let head = (summary.versions ?? []).filter { $0.branch == branch }.map(\.version).max()
        return head.map { $0 != base } ?? false
    }

    /// The draft read by this console with the reader the silo runs: the rules and outputs, named by
    /// the ruleset it is stored as, or the reader's refusal in its words. What only the silo can say —
    /// whether the name is free and the base still the head — waits for the silo.
    public var reading: DraftReading {
        do {
            let read = try RulesetFile.ruleset(from: Data(text.utf8))
            return .reading(SiloClient.RulesetReading(
                name: ruleset,
                rules: read.rules.enumerated().map { position, rule in
                    SiloClient.RuleReading(
                        name: rule.id ?? "#\(position + 1)",
                        scope: rule.scope,
                        conditions: rule.conditions.map { condition in
                            let (test, value) = condition.test.attribute
                            return SiloClient.ConditionReading(fact: condition.fact.rawValue, test: test, value: value)
                        },
                        action: rule.action
                    )
                },
                outputs: read.outputs
            ))
        } catch {
            return .refused(String(describing: error))
        }
    }

    /// The text's difference from its base, line by line.
    public var difference: [LineDifference.Line] { LineDifference.lines(from: baseText, to: text) }

    public static func starterText(named name: String) -> String {
        """
        <ruleset format="1" name="\(name)">
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

/// What the console makes of a draft's text itself.
public enum DraftReading: Hashable, Sendable {
    case reading(SiloClient.RulesetReading)
    case refused(String)
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
