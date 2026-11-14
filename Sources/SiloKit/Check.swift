// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SmdKit

/// A stack as a check records it: the ruleset at its version, and the layers above it, nearest
/// first. Two equal stacks resolve a recipe's facts alike, which is what lets a check be skipped.
public struct CheckedStack: Hashable, Sendable, Codable {
    public var ruleset: RulesetRef
    public var layers: [RecipeLayer]

    public init(ruleset: RulesetRef, layers: [RecipeLayer]) {
        self.ruleset = ruleset
        self.layers = layers
    }
}

/// What a check read of a presentation's item from its container: the facts that come from the
/// lineage, which an edit of the container can change, rather than from the sources, which do not.
/// A check is made again when these differ from the ones it was last made with, as when its stack
/// differs.
public struct CheckedItem: Hashable, Sendable, Codable {
    public var kind: EntryType?
    public var extra: Bool?
    /// Each audio stream's role, in the file's audio order.
    public var roles: [AudioRole]

    public init(kind: EntryType?, extra: Bool?, roles: [AudioRole]) {
        self.kind = kind
        self.extra = extra
        self.roles = roles
    }

    /// What moved from this to another, a line each: `kind: featurette → trailer`, say.
    public func moves(to other: CheckedItem) -> [String] {
        var moves: [String] = []
        if kind != other.kind {
            moves.append("kind: \(kind?.rawValue ?? "none") → \(other.kind?.rawValue ?? "none")")
        }
        if extra != other.extra {
            moves.append("extra: \(extra.map(String.init) ?? "none") → \(other.extra.map(String.init) ?? "none")")
        }
        for (position, (was, now)) in zip(roles, other.roles).enumerated() where was != now {
            moves.append("audio \(position + 1) role: \(was.rawValue) → \(now.rawValue)")
        }
        return moves
    }
}

extension SourceFacts {
    /// The facts of these that come from the lineage.
    public var item: CheckedItem {
        CheckedItem(kind: kind, extra: extra, roles: audio.map(\.role))
    }
}

/// One stream a check found the rules would now decide otherwise: what it got, and what it would get.
public struct StreamChange: Hashable, Sendable, Codable {
    public var kind: StreamKind
    public var index: Int
    public var was: Action
    public var now: Action

    public init(kind: StreamKind, index: Int, was: Action, now: Action) {
        self.kind = kind
        self.index = index
        self.was = was
        self.now = now
    }
}

/// The silo's latest check of one placed presentation: the stack it was resolved through again,
/// when, and what that found. Kept beside the committed recipe, which never changes.
/// `LayeredRulesets.md`, *The background check*.
public struct CheckRecord: Hashable, Sendable, Codable {
    public enum Outcome: String, Hashable, Sendable, Codable {
        /// The rules in force decide every stream, and the output, as the recipe recorded.
        case current
        /// They decide some stream, or the output, otherwise.
        case outOfDate
        /// They make no recipe for the presentation at all.
        case unresolvable
    }

    /// The job that placed the presentation; the record's key.
    public var job: String
    public var recipe: String
    public var checkedAgainst: CheckedStack
    public var checkedAt: Date
    public var outcome: Outcome
    public var changes: [StreamChange]
    /// Why the rules would make the presentation otherwise, beyond its streams: the output, what
    /// moved in the item's container, or no recipe at all.
    public var reason: String?
    /// The item as the check read it from its container; nil in a record made before checks read
    /// it, which is therefore checked again.
    public var item: CheckedItem?

    public init(
        job: String,
        recipe: String,
        checkedAgainst: CheckedStack,
        checkedAt: Date = .now,
        outcome: Outcome,
        changes: [StreamChange] = [],
        reason: String? = nil,
        item: CheckedItem? = nil
    ) {
        self.job = job
        self.recipe = recipe
        self.checkedAgainst = checkedAgainst
        self.checkedAt = checkedAt
        self.outcome = outcome
        self.changes = changes
        self.reason = reason
        self.item = item
    }
}

extension Recipe {
    /// The stack the recipe was resolved through.
    public var stack: CheckedStack {
        CheckedStack(ruleset: ruleset, layers: layers)
    }

    /// What another resolution of the same facts decides otherwise, stream by stream: which rule or
    /// layer decided is not compared, only what is done with the stream.
    public func changes(to other: Recipe) -> [StreamChange] {
        decisions.compactMap { decision in
            guard
                let now = other.decisions.first(where: {
                    $0.kind == decision.kind && $0.sourceIndex == decision.sourceIndex
                }), now.action != decision.action
            else {
                return nil
            }
            return StreamChange(kind: decision.kind, index: decision.sourceIndex, was: decision.action, now: now.action)
        }
    }
}
