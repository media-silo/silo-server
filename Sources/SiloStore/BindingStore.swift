// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloKit

/// Bindings as the silo keeps them: one JSON file each under `<state>/bindings`. A binding is never
/// changed once made, so the store adds and reads and does nothing else; an addition of a binding
/// that says what one the store holds says finds that one.
public struct BindingStore: Sendable {
    private let folder: RecordFolder<Binding>

    public init(folder: URL) throws {
        self.folder = try RecordFolder(folder: folder, id: \.id)
    }

    /// In memory only, for tests.
    public init() {
        folder = RecordFolder(id: \.id)
    }

    public func binding(_ id: String) -> Binding? { folder.record(id) }

    /// Keeps a binding, or finds the one the store holds that says what it says. `created` says which.
    @discardableResult
    public func insert(_ binding: Binding) throws -> (binding: Binding, created: Bool) {
        let held = try folder.insert([binding]) { $0.says(whatIsSaidBy: $1) }[0]
        return (held.record, held.inserted)
    }
}

/// Recipes as the silo keeps them: one JSON file each under `<state>/recipes`. A resolved recipe
/// may be committed or discarded; a committed recipe is refused both.
public struct RecipeStore: Sendable {
    private let folder: RecordFolder<StoredRecipe>

    public init(folder: URL) throws {
        self.folder = try RecordFolder(folder: folder, id: \.id)
    }

    /// In memory only, for tests.
    public init() {
        folder = RecordFolder(id: \.id)
    }

    public func recipe(_ id: String) -> StoredRecipe? { folder.record(id) }

    /// A binding's recipes, oldest first.
    public func recipes(of binding: String) -> [StoredRecipe] {
        folder.all.filter { $0.binding == binding }.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    public func insert(_ recipes: [StoredRecipe]) throws { try folder.insert(recipes) }

    /// Keeps each recipe, or finds one its binding holds, resolved or committed, of the same facts
    /// and recipe: the same ruleset version, stack, output and decisions. Answers, for each recipe
    /// given, the recipe held and whether it was kept.
    public func insertUnlessHeld(_ recipes: [StoredRecipe]) throws -> [(recipe: StoredRecipe, created: Bool)] {
        try folder.insert(recipes) { held, given in
            held.binding == given.binding && held.facts == given.facts && held.recipe == given.recipe
        }
        .map { ($0.record, $0.inserted) }
    }

    /// Commits a resolved recipe: the one change a recipe makes after which it makes none.
    public func commit(_ id: String) throws -> StoredRecipe? {
        try folder.update(id) { (recipe: inout StoredRecipe) throws -> Void in
            guard recipe.state == .resolved else { throw RecipeStoreError.committed(id) }
            recipe.state = .committed
        }
    }

    /// Discards a resolved recipe; a committed recipe is the record of what a job ran, and stays.
    public func discard(_ id: String) throws -> StoredRecipe? {
        try folder.remove(id) { (recipe: StoredRecipe) throws -> Void in
            guard recipe.state == .resolved else { throw RecipeStoreError.committed(id) }
        }
    }
}

public enum RecipeStoreError: Error, Equatable, CustomStringConvertible {
    case committed(String)

    public var description: String {
        switch self {
        case .committed(let id): "recipe \(id) is committed, and does not change"
        }
    }
}
