// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloKit

/// Bindings as the silo keeps them: one JSON file each under `<state>/bindings`. A binding is never
/// changed once made, so the store adds and reads and does nothing else.
public final class BindingStore: Sendable {
    private let folder: RecordFolder<Binding>

    public init(folder: URL) throws {
        self.folder = try RecordFolder(folder: folder, id: \.id)
    }

    /// In memory only, for tests.
    public init() {
        folder = RecordFolder(id: \.id)
    }

    public func binding(_ id: String) -> Binding? { folder.record(id) }

    public func insert(_ binding: Binding) throws { try folder.insert([binding]) }
}

/// Recipes as the silo keeps them: one JSON file each under `<state>/recipes`. A draft's
/// adjustments change and a draft may be discarded; a committed recipe is refused both.
public final class RecipeStore: Sendable {
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

    /// Replaces a draft's adjustments with `adjustments`, applied to what the rules decided.
    public func adjust(_ id: String, _ adjustments: [Adjustment], mappings: [TrackMapping]) throws -> StoredRecipe? {
        try folder.update(id) { (recipe: inout StoredRecipe) throws -> Void in
            guard recipe.state == .draft else { throw RecipeStoreError.committed(id) }
            recipe.recipe = try recipe.resolved.adjusted(by: adjustments, mappings: mappings)
            recipe.adjustments = adjustments
        }
    }

    /// Commits a draft: the one change a recipe makes after which it makes none.
    public func commit(_ id: String) throws -> StoredRecipe? {
        try folder.update(id) { (recipe: inout StoredRecipe) throws -> Void in
            guard recipe.state == .draft else { throw RecipeStoreError.committed(id) }
            recipe.state = .committed
        }
    }

    /// Discards a draft; a committed recipe is the record of what a job ran, and stays.
    public func discard(_ id: String) throws -> StoredRecipe? {
        try folder.remove(id) { (recipe: StoredRecipe) throws -> Void in
            guard recipe.state == .draft else { throw RecipeStoreError.committed(id) }
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
