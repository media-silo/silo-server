// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation

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
    /// Why the rules would make the presentation otherwise, beyond its streams: the output, or no
    /// recipe at all.
    public var reason: String?

    public init(job: String, recipe: String, checkedAgainst: CheckedStack, checkedAt: Date = .now, outcome: Outcome, changes: [StreamChange] = [], reason: String? = nil) {
        self.job = job
        self.recipe = recipe
        self.checkedAgainst = checkedAgainst
        self.checkedAt = checkedAt
        self.outcome = outcome
        self.changes = changes
        self.reason = reason
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
            guard let now = other.decisions.first(where: { $0.kind == decision.kind && $0.sourceIndex == decision.sourceIndex }), now.action != decision.action else {
                return nil
            }
            return StreamChange(kind: decision.kind, index: decision.sourceIndex, was: decision.action, now: now.action)
        }
    }
}
