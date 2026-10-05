// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloKit
import Testing
@testable import SiloStore

struct RecipeStoreTests {
    static func draft(binding: String = "b") -> StoredRecipe {
        let facts = SourceFacts(audio: [AudioFacts(index: 1, absoluteIndex: 0, codec: "truehd", lossless: true, channels: 8)])
        let decision = StreamDecision(kind: .audio, sourceIndex: 1, sourceAbsoluteIndex: 0, rule: "lossless-main", action: .encode(EncodeSettings(codec: "flac")))
        let recipe = Recipe(ruleset: RulesetRef(name: "household", version: 3), decisions: [decision], output: OutputPolicy(), layout: OutputLayout(keeping: [decision]))
        return StoredRecipe(binding: binding, facts: facts, resolved: recipe)
    }

    @Test func aDraftIsAdjustedAndRestored() throws {
        let store = RecipeStore()
        let draft = Self.draft()
        try store.insert([draft])
        let adjusted = try #require(try store.adjust(draft.id, [Adjustment(kind: .audio, index: 1, action: .copy)], mappings: []))
        #expect(adjusted.recipe.audio.first?.action == .copy)
        #expect(adjusted.resolved == draft.resolved, "what the rules decided is kept")
        let restored = try #require(try store.adjust(draft.id, [], mappings: []))
        #expect(restored.recipe == draft.resolved)
        #expect(restored.adjustments.isEmpty)
    }

    @Test func aCommittedRecipeNeverChanges() throws {
        let store = RecipeStore()
        let draft = Self.draft()
        try store.insert([draft])
        #expect(try store.commit(draft.id)?.state == .committed)
        #expect(throws: RecipeStoreError.committed(draft.id)) { try store.adjust(draft.id, [Adjustment(kind: .audio, index: 1, action: .copy)], mappings: []) }
        #expect(throws: RecipeStoreError.committed(draft.id)) { try store.commit(draft.id) }
        #expect(throws: RecipeStoreError.committed(draft.id)) { try store.discard(draft.id) }
        #expect(store.recipe(draft.id)?.recipe == draft.resolved, "and is as it was")
    }

    @Test func aDraftIsDiscardedAndTheRestStay() throws {
        let store = RecipeStore()
        let first = Self.draft(), second = Self.draft()
        try store.insert([first, second])
        #expect(try store.discard(first.id)?.id == first.id)
        #expect(store.recipe(first.id) == nil)
        #expect(store.recipes(of: "b").map(\.id) == [second.id])
        #expect(try store.discard("nothing") == nil)
    }

    @Test func bindingsAndRecipesSurviveARestart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RecipeStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let binding = Binding(library: "main", containers: [], item: "part1", segments: [Binding.Segment(source: "s")])
        try BindingStore(folder: root.appendingPathComponent("bindings")).insert(binding)
        let draft = Self.draft(binding: binding.id)
        try RecipeStore(folder: root.appendingPathComponent("recipes")).insert([draft])
        #expect(try BindingStore(folder: root.appendingPathComponent("bindings")).binding(binding.id)?.item == "part1")
        let reopened = try RecipeStore(folder: root.appendingPathComponent("recipes"))
        #expect(reopened.recipes(of: binding.id).map(\.id) == [draft.id])
        _ = try reopened.discard(draft.id)
        #expect(try RecipeStore(folder: root.appendingPathComponent("recipes")).recipe(draft.id) == nil, "a discarded draft's file goes too")
    }
}
