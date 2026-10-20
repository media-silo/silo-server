// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloKit
import Testing

@testable import SiloStore

struct RecipeStoreTests {
    static func resolved(binding: String = "b") -> StoredRecipe {
        let facts = SourceFacts(audio: [
            AudioFacts(index: 1, absoluteIndex: 0, codec: "truehd", lossless: true, channels: 8)
        ])
        let decision = StreamDecision(
            kind: .audio,
            sourceIndex: 1,
            sourceAbsoluteIndex: 0,
            rule: "lossless-main",
            action: .encode(EncodeSettings(codec: "flac"))
        )
        let recipe = Recipe(
            ruleset: RulesetRef(name: "household", version: 3),
            decisions: [decision],
            output: OutputPolicy(),
            layout: OutputLayout(keeping: [decision])
        )
        return StoredRecipe(binding: binding, facts: facts, recipe: recipe)
    }

    @Test func aCommittedRecipeNeverChanges() throws {
        let store = RecipeStore()
        let resolved = Self.resolved()
        try store.insert([resolved])
        #expect(try store.commit(resolved.id)?.state == .committed)
        #expect(throws: RecipeStoreError.committed(resolved.id)) { try store.commit(resolved.id) }
        #expect(throws: RecipeStoreError.committed(resolved.id)) { try store.discard(resolved.id) }
        #expect(store.recipe(resolved.id)?.recipe == resolved.recipe, "and is as it was")
    }

    @Test func aResolvedRecipeIsDiscardedAndTheRestStay() throws {
        let store = RecipeStore()
        let first = Self.resolved()
        let second = Self.resolved()
        try store.insert([first, second])
        #expect(try store.discard(first.id)?.id == first.id)
        #expect(store.recipe(first.id) == nil)
        #expect(store.recipes(of: "b").map(\.id) == [second.id])
        #expect(try store.discard("nothing") == nil)
    }

    @Test func bindingsAndRecipesSurviveARestart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "RecipeStoreTests-\(UUID().uuidString)"
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let binding = Binding(library: "main", containers: [], item: "part1", segments: [Binding.Segment(source: "s")])
        try BindingStore(folder: root.appendingPathComponent("bindings")).insert(binding)
        let resolved = Self.resolved(binding: binding.id)
        try RecipeStore(folder: root.appendingPathComponent("recipes")).insert([resolved])
        #expect(try BindingStore(folder: root.appendingPathComponent("bindings")).binding(binding.id)?.item == "part1")
        let reopened = try RecipeStore(folder: root.appendingPathComponent("recipes"))
        #expect(reopened.recipes(of: binding.id).map(\.id) == [resolved.id])
        _ = try reopened.discard(resolved.id)
        #expect(
            try RecipeStore(folder: root.appendingPathComponent("recipes")).recipe(resolved.id) == nil,
            "a discarded recipe's file goes too"
        )
    }
}
