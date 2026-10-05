// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation

/// A recipe as the silo keeps it: the resolution of one output of one binding. A draft until a job
/// is made from it, when it is committed and never changes again — it is then what the job ran and
/// what the presentation was made by.
public struct StoredRecipe: Hashable, Sendable, Codable {
    public enum State: String, Hashable, Sendable, Codable {
        case draft, committed
    }

    /// A lowercased UUID, minted by the silo.
    public var id: String
    /// The binding it resolves.
    public var binding: String
    public var state: State
    /// The facts the ruleset was resolved against.
    public var facts: SourceFacts
    /// What the rules decided, before any adjustment: kept, so that removing every adjustment gives
    /// it back exactly.
    public var resolved: Recipe
    public var adjustments: [Adjustment]
    /// The recipe as it stands: the rules' decisions with the adjustments applied.
    public var recipe: Recipe
    public var createdAt: Date

    public init(id: String = UUID().uuidString.lowercased(), binding: String, facts: SourceFacts, resolved: Recipe, createdAt: Date = .now) {
        self.id = id
        self.binding = binding
        self.state = .draft
        self.facts = facts
        self.resolved = resolved
        self.adjustments = []
        self.recipe = resolved
        self.createdAt = createdAt
    }
}
