// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation

/// A recipe as the silo keeps it: the resolution of one output of one binding through its stack.
/// Resolved until a job is made from it, when it is committed and never changes again — it is then
/// what the job ran and what the presentation was made by. A recipe is always what its stack decided:
/// a person's decision about the entry is a rule in the binding's own rules, not a change to a recipe.
public struct StoredRecipe: Hashable, Sendable, Codable {
    public enum State: String, Hashable, Sendable, Codable {
        case resolved, committed
    }

    /// A lowercased UUID, minted by the silo.
    public var id: String
    /// The binding it resolves.
    public var binding: String
    public var state: State
    /// The facts the stack was resolved against.
    public var facts: SourceFacts
    public var recipe: Recipe
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString.lowercased(),
        binding: String,
        facts: SourceFacts,
        recipe: Recipe,
        createdAt: Date = .now
    ) {
        self.id = id
        self.binding = binding
        self.state = .resolved
        self.facts = facts
        self.recipe = recipe
        self.createdAt = createdAt
    }
}
