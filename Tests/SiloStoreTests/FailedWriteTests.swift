// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloKit
import Testing

@testable import SiloStore

/// A change a store cannot write is not held: memory changes only once the file is written, so what
/// a store answers after a failed write is what a restart would read. Each test takes a store's
/// folder away, which fails every write into it whoever runs the tests.
struct FailedWriteTests {
    /// A temporary folder holding one folder per store.
    struct State {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FailedWrite-\(UUID().uuidString)")

        func folder(_ name: String) -> URL { root.appendingPathComponent(name) }

        /// Takes a store's folder away, so that writing into it fails.
        func takeAway(_ name: String) throws { try FileManager.default.removeItem(at: folder(name)) }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    @Test func aRecordWhoseWriteFailsIsNotHeld() throws {
        let state = State()
        defer { state.remove() }
        let recipes = try RecipeStore(folder: state.folder("recipes"))
        let bindings = try BindingStore(folder: state.folder("bindings"))
        let checks = try CheckStore(folder: state.folder("checks"))
        let kept = RecipeStoreTests.resolved()
        try recipes.insert([kept])
        let check = CheckRecord(
            job: "j",
            recipe: kept.id,
            checkedAgainst: CheckedStack(ruleset: RulesetRef(name: "household", version: 1), layers: []),
            outcome: .current
        )
        try checks.record(check)
        for name in ["recipes", "bindings", "checks"] { try state.takeAway(name) }

        let refused = RecipeStoreTests.resolved()
        #expect(throws: (any Error).self) { try recipes.insert([refused]) }
        #expect(recipes.recipe(refused.id) == nil, "an insert that was not written")
        #expect(throws: (any Error).self) { try recipes.commit(kept.id) }
        #expect(recipes.recipe(kept.id)?.state == .resolved, "an update that was not written")

        let binding = Binding(library: "main", containers: [], item: "part1", segments: [Binding.Segment(source: "s")])
        #expect(throws: (any Error).self) { try bindings.insert(binding) }
        #expect(bindings.binding(binding.id) == nil)

        var outOfDate = check
        outOfDate.outcome = .outOfDate
        #expect(throws: (any Error).self) { try checks.record(outOfDate) }
        #expect(checks.check(of: "j")?.outcome == .current, "a check replaced in place, not written")
        var other = check
        other.job = "k"
        #expect(throws: (any Error).self) { try checks.record(other) }
        #expect(checks.check(of: "k") == nil, "a check of a new job, not written")
    }

    @Test func aJobWhoseWriteFailsIsAsItWas() throws {
        let state = State()
        defer { state.remove() }
        let jobs = try JobStore(folder: state.folder("jobs"))
        try jobs.insert(Job(id: "first", recipe: "r"))
        try state.takeAway("jobs")

        #expect(throws: (any Error).self) { try jobs.insert(Job(id: "second", recipe: "r")) }
        #expect(jobs.job("second") == nil)
        #expect(throws: (any Error).self) { try jobs.update("first") { $0.state = .claimed } }
        #expect(jobs.job("first")?.state == .pending, "an update")
        #expect(throws: (any Error).self) {
            try jobs.updateFirst(where: { $0.state == .pending }, sortedBy: { $0.createdAt < $1.createdAt }) {
                $0.state = .claimed
            }
        }
        #expect(jobs.job("first")?.state == .pending, "a claim")
        #expect(throws: (any Error).self) { try jobs.updateAll(where: { _ in true }) { $0.state = .claimed } }
        #expect(jobs.job("first")?.state == .pending, "a change to every job")
        #expect(try JobStore(folder: state.folder("jobs")).all().isEmpty, "and a restart reads none of it")
    }

    @Test func aSourceWhoseWriteFailsIsAsItWas() throws {
        let state = State()
        defer { state.remove() }
        let sources = try SourceStore(folder: state.folder("sources"))
        let (kept, _) = try sources.register(
            SourceStoreTests.spec,
            key: SourceStoreTests.discTitle,
            copy: SourceStoreTests.copy(on: "ripper")
        )
        try state.takeAway("sources")

        #expect(throws: (any Error).self) { try sources.register(SourceStoreTests.spec, key: nil, copy: nil) }
        #expect(sources.all().map(\.id) == [kept.id], "a new source")
        #expect(throws: (any Error).self) {
            try sources.register(
                SourceStoreTests.spec,
                key: SourceStoreTests.discTitle,
                copy: SourceStoreTests.copy(on: "laptop")
            )
        }
        #expect(sources.source(kept.id)?.copies.map(\.holder) == ["ripper"], "a copy of the source a key found")
        #expect(throws: (any Error).self) {
            try sources.update(kept.id) { $0.hold(SourceStoreTests.copy(on: "laptop")) }
        }
        #expect(sources.source(kept.id)?.copies.map(\.holder) == ["ripper"], "an update")
    }

    @Test func aNodeWhoseWriteFailsIsAsItWas() throws {
        let state = State()
        defer { state.remove() }
        let nodes = try NodeStore(folder: state.folder("nodes"))
        try nodes.insert(NodeStore.Stored(node: Node(id: "box", name: "Box", platform: "linux"), secretHash: "h"))
        try state.takeAway("nodes")

        let other = NodeStore.Stored(node: Node(id: "other", name: "Other", platform: "linux"), secretHash: "h")
        #expect(throws: (any Error).self) { try nodes.insert(other) }
        #expect(nodes.stored("other") == nil)
        #expect(throws: (any Error).self) { try nodes.update("box") { $0.tokenHash = "t" } }
        #expect(nodes.stored("box")?.tokenHash == nil, "a token whose hash was not written is not one the silo holds")
    }

    /// A file that cannot be deleted keeps its record: a folder that cannot be written to, which only
    /// holds for a user other than root.
    @Test(.enabled(if: getuid() != 0)) func aRemovalWhoseFileCannotBeDeletedKeepsTheRecord() throws {
        let state = State()
        defer {
            for name in ["recipes", "jobs"] {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: state.folder(name).path
                )
            }
            state.remove()
        }
        let recipes = try RecipeStore(folder: state.folder("recipes"))
        let jobs = try JobStore(folder: state.folder("jobs"))
        let recipe = RecipeStoreTests.resolved()
        try recipes.insert([recipe])
        try jobs.insert(Job(id: "trial", recipe: "r", trial: true))
        for name in ["recipes", "jobs"] {
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: state.folder(name).path)
        }

        #expect(throws: (any Error).self) { try recipes.discard(recipe.id) }
        #expect(recipes.recipe(recipe.id) != nil)
        #expect(throws: (any Error).self) { try jobs.remove("trial") }
        #expect(jobs.job("trial") != nil)
    }

    /// A record whose file is already gone is removed: the removal wanted it gone, and it is.
    @Test func aRemovalWhoseFileIsAlreadyGoneRemovesTheRecord() throws {
        let state = State()
        defer { state.remove() }
        let recipes = try RecipeStore(folder: state.folder("recipes"))
        let jobs = try JobStore(folder: state.folder("jobs"))
        let recipe = RecipeStoreTests.resolved()
        try recipes.insert([recipe])
        try jobs.insert(Job(id: "trial", recipe: "r", trial: true))
        try state.takeAway("recipes")
        try state.takeAway("jobs")

        #expect(try recipes.discard(recipe.id)?.id == recipe.id)
        #expect(recipes.recipe(recipe.id) == nil)
        try jobs.remove("trial")
        #expect(jobs.job("trial") == nil)
    }
}
