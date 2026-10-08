// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloKit
import SiloStore
import Testing
@testable import SiloApp

/// An application naming a branch takes its head; naming none, the standard's.
struct BranchApplicationTests {
    @Test func anApplicationOnABranchTakesItsHead() throws {
        let bench = try JobServiceTests.Bench()
        defer { bench.remove() }
        let rulesets = try RulesetStore(folder: bench.root.appendingPathComponent("State/rulesets"))
        let household = Data(JobServiceTests.Bench.household.utf8)
        _ = try rulesets.startBranch("trial", of: "household", from: 1)
        #expect(try rulesets.store(household, as: "household", branch: "trial") == 2)
        let source = try bench.sources.register(JobServiceTests.Bench.input, key: nil, copy: try bench.copy()).source
        let binding = try bench.bindingService.make(Binding(library: "main", containers: JobServiceTests.Bench.containers, item: "part3", segments: [Binding.Segment(source: source.id)]))
        let unqualified = [Application.OutputChoice()]

        #expect(try bench.bindingService.apply(Application(ruleset: "household", branch: "trial", outputs: unqualified), to: binding.id).first?.recipe.ruleset.version == 2)
        #expect(try bench.bindingService.apply(Application(ruleset: "household", outputs: unqualified), to: binding.id).first?.recipe.ruleset.version == 1, "naming no branch, the standard's head")

        #expect(throws: BadApplication.self) { try bench.bindingService.apply(Application(ruleset: "household", branch: "nowhere"), to: binding.id) }
        let wrong = #expect(throws: BadApplication.self) { try bench.bindingService.apply(Application(ruleset: "household", branch: "trial", version: 1), to: binding.id) }
        #expect(wrong?.reason == "household@1 is on standard, not trial")

        _ = try rulesets.promote("trial", of: "household")
        let closed = #expect(throws: ClosedBranch.self) { try bench.bindingService.apply(Application(ruleset: "household", branch: "trial"), to: binding.id) }
        #expect(closed?.reason == "household's branch trial has been promoted, and is closed")
        #expect(try bench.bindingService.apply(Application(ruleset: "household", outputs: unqualified), to: binding.id).first?.recipe.ruleset.version == 3, "the promoted head is the standard's")
    }
}
