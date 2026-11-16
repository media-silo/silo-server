// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloKit
import SiloStore
import SmdKit
import SmdSidecar
import Testing

@testable import SiloApp

/// Requests sent again, because their answers were lost, answered with what the first made rather
/// than making it twice. Proposal 0022.
struct RepeatTests {
    typealias Bench = JobServiceTests.Bench

    /// Part three of *Pyramids of Mars*, bound to a source or a span of it.
    static func binding(
        source: String,
        chapters: Binding.ChapterSpan? = nil,
        containers: [String] = Bench.containers
    ) -> Binding {
        Binding(
            library: "main",
            containers: containers,
            item: "part3",
            tracks: [TrackMapping(feature: "commentary1", audio: 2)],
            chapters: [Chapter(index: 1, title: "Opening")],
            segments: [Binding.Segment(source: source, chapters: chapters)]
        )
    }

    @Test func aBindingSentAgainIsTheBindingThereIs() throws {
        let bench = try Bench()
        defer { bench.remove() }
        let source = try bench.sources.register(Bench.input, key: Bench.key(), copy: try bench.copy()).source

        let first = try bench.bindingService.make(Self.binding(source: source.id))
        let again = try bench.bindingService.make(Self.binding(source: source.id))
        #expect(first.created)
        #expect(!again.created, "a binding sent again")
        #expect(again.binding == first.binding, "is the binding the first made")

        let span = try bench.bindingService.make(
            Self.binding(source: source.id, chapters: Binding.ChapterSpan(from: 2, to: 2))
        )
        #expect(span.created, "another span of the same source is another binding")
        #expect(span.binding.id != first.binding.id)

        var edited = Fixture.serial
        edited.outline = "Sutekh the Destroyer, freed from his pyramid."
        let newer = [Fixture.series, edited].map { String(decoding: ContainerFile.data(for: $0), as: UTF8.self) }
        let resent = try bench.bindingService.make(Self.binding(source: source.id, containers: newer))
        #expect(!resent.created, "a newer copy of the container's document")
        #expect(resent.binding.id == first.binding.id, "is the same entry")
        #expect(resent.binding.containers == Bench.containers, "answered as it was made")
    }

    @Test func anApplicationSentAgainIsAnsweredWithTheRecipesTheFirstMade() throws {
        let bench = try Bench()
        defer { bench.remove() }
        let source = try bench.sources.register(Bench.input, key: Bench.key(), copy: try bench.copy()).source
        let binding = try bench.bindingService.make(Self.binding(source: source.id)).binding
        let household = Application(ruleset: "household")

        let first = try bench.bindingService.apply(household, to: binding.id)
        let again = try bench.bindingService.apply(household, to: binding.id)
        #expect(first.created)
        #expect(first.recipes.map(\.recipe.output.profile) == [nil, "mobile"])
        #expect(!again.created, "an application sent again")
        #expect(again.recipes == first.recipes, "is answered with the recipes the first made")
        #expect(bench.recipes.recipes(of: binding.id).count == 2, "and stores nothing")

        let unqualified = first.recipes[0]
        _ = try bench.service.make(from: unqualified.id)
        let afterCommit = try bench.bindingService.apply(
            Application(ruleset: "household", outputs: [Application.OutputChoice()]),
            to: binding.id
        )
        #expect(!afterCommit.created)
        #expect(afterCommit.recipes.map(\.id) == [unqualified.id], "an application after its recipe was committed")
        #expect(afterCommit.recipes.map(\.state) == [.committed])

        _ = try bench.rulesets.store(
            Data(Bench.household.replacingOccurrences(of: "</ruleset>", with: "<!-- moved --></ruleset>").utf8),
            as: "household",
            basedOn: 1
        )
        let moved = try bench.bindingService.apply(household, to: binding.id)
        #expect(moved.created, "an application after the head moved")
        #expect(moved.recipes.map(\.recipe.ruleset.version) == [2, 2], "makes recipes of the new head")
        #expect(bench.recipes.recipes(of: binding.id).count == 4)
    }

    @Test func anApplicationOfOneOutputHeldAndOneNotMakesTheOther() throws {
        let bench = try Bench()
        defer { bench.remove() }
        let source = try bench.sources.register(Bench.input, key: Bench.key(), copy: try bench.copy()).source
        let binding = try bench.bindingService.make(Self.binding(source: source.id)).binding

        let held = try bench.bindingService.apply(
            Application(ruleset: "household", outputs: [Application.OutputChoice()]),
            to: binding.id
        )
        let both = try bench.bindingService.apply(Application(ruleset: "household"), to: binding.id)
        #expect(both.created, "one output is made")
        #expect(both.recipes.count == 2)
        #expect(both.recipes[0] == held.recipes[0], "and the one held is answered")
        #expect(both.recipes[1].recipe.output.profile == "mobile")
        #expect(bench.recipes.recipes(of: binding.id).count == 2, "one recipe is stored")
    }
}
