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
        _ = try bench.service.make(from: unqualified.id).job
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

    /// A job a node has claimed, with the attempt the claim opened.
    static func claimed(_ id: String) -> Job {
        var job = Job(id: id, state: .claimed, recipe: "r")
        job.attempts = [Attempt(node: "box")]
        return job
    }

    @Test func aJobMadeAgainIsTheJobAsItStands() async throws {
        let bench = try Bench()
        defer { bench.remove() }
        let service = bench.service
        let recipe = try bench.resolved(copy: try bench.copy())

        let made = try service.make(from: recipe.id)
        #expect(made.created)
        let claimed = try #require(try await service.claim(node: "box", capabilities: ["flac", "aac"])).job
        let again = try service.make(from: recipe.id)
        #expect(!again.created, "a job made again")
        #expect(again.job.id == made.job.id && again.job.state == .claimed, "is the job made first, as it stands")
        #expect(again.job == claimed)
        #expect(try service.all().count == 1)

        let tried = try bench.resolved(copy: try bench.copy("b.mkv"))
        let trial = try service.make(from: tried.id, trial: true).job
        let asJob = #expect(throws: CommittedRecipe.self) { try service.make(from: tried.id) }
        #expect(asJob?.reason == "recipe \(tried.id) is committed to trial \(trial.id), which is a trial")
        #expect(try service.all().count == 2, "a trial asked for as a job makes no job")

        try bench.store.remove(trial.id)
        let gone = #expect(throws: CommittedRecipe.self) { try service.make(from: tried.id, trial: true) }
        #expect(gone?.reason == "recipe \(tried.id) is committed, and the job made from it is gone")
        #expect(try service.all().count == 1)
    }

    @Test func eachChangeSentAgainIsAnsweredWithTheJob() async throws {
        let bench = try Bench()
        defer { bench.remove() }
        let service = bench.service
        let output = FileRef(holder: "box", url: URL(fileURLWithPath: "/encoded.mkv"), secret: "")
        let result = EncodeResult(sizeBytes: 1, streams: [], layoutMatched: true)
        func claimed(_ id: String) throws { try bench.store.insert(Self.claimed(id)) }

        try bench.store.insert(Job(id: "waiting", recipe: "r"))
        let cancelled = try service.cancel("waiting")
        #expect(try service.cancel("waiting") == cancelled, "a cancel sent again")
        try claimed("encoding")
        let cancelling = try service.cancel("encoding")
        #expect(try service.cancel("encoding") == cancelling, "and one sent while the node stops")

        let retried = try service.retry("waiting")
        #expect(retried.state == .pending)
        #expect(try service.retry("waiting") == retried, "a retry sent again")
        _ = try #require(try await service.claim(node: "box", capabilities: []))
        let claimedSince = #expect(throws: WrongState.self) { try service.retry("waiting") }
        #expect(claimedSince?.description == "a claimed job cannot be retried", "a retry of a job claimed since")

        try claimed("completed")
        let completed = try await service.complete("completed", output: output, result: result)
        let completedAgain = try await service.complete("completed", output: output, result: result)
        #expect(completedAgain == completed, "a completion sent again")
        #expect(completedAgain.state == .encoded && completedAgain.attempts.count == 1)
        var other = result
        other.sizeBytes = 2
        await #expect(throws: WrongState.self, "a completion of another result") {
            try await service.complete("completed", output: output, result: other)
        }
        #expect(try service.job("completed").result == result, "and the job holds the first")

        try claimed("failed")
        let failed = try await service.fail("failed", reason: "ffmpeg exited 1")
        #expect(try await service.fail("failed", reason: "ffmpeg exited 1") == failed, "a failure sent again")
        await #expect(throws: WrongState.self, "a failure of another reason") {
            try await service.fail("failed", reason: "out of disk")
        }
        _ = try await service.fail("encoding", reason: "cancelled")
        #expect(
            try await service.fail("encoding", reason: "cancelled").state == .cancelled,
            "and one that landed a cancel"
        )
    }

    @Test func oneCompletionSentTwiceAtOnceIsMadeOnceAndAnsweredTwice() async throws {
        let bench = try Bench()
        defer { bench.remove() }
        let service = bench.service
        let output = FileRef(holder: "box", url: URL(fileURLWithPath: "/encoded.mkv"), secret: "")
        let result = EncodeResult(sizeBytes: 1, streams: [], layoutMatched: true)
        var refused: [String] = []
        for round in 0..<100 {
            let id = "race-\(round)"
            try bench.store.insert(Self.claimed(id))
            let answered = try await withThrowingTaskGroup(of: Bool.self) { group in
                for _ in 0..<2 {
                    group.addTask { (try? await service.complete(id, output: output, result: result)) != nil }
                }
                return try await group.reduce(0) { $0 + ($1 ? 1 : 0) }
            }
            if answered != 2 || (try? service.job(id))?.attempts.count != 1 { refused.append(id) }
        }
        #expect(refused.isEmpty, "a completion refused or made twice: \(refused.count) of 100")
    }

    @Test func oneJobAskedForTwiceAtOnceIsMadeOnce() async throws {
        let bench = try Bench()
        defer { bench.remove() }
        let service = bench.service
        var twice: [String] = []
        for round in 0..<30 {
            let recipe = try bench.resolved(copy: try bench.copy("\(round).mkv"))
            let answered = try await withThrowingTaskGroup(of: String?.self) { group in
                for _ in 0..<2 { group.addTask { try? service.make(from: recipe.id).job.id } }
                return try await group.reduce(into: Set<String?>()) { $0.insert($1) }
            }
            if answered.count != 1 || answered.contains(nil) { twice.append(recipe.id) }
        }
        #expect(twice.isEmpty, "a recipe answered with two jobs, or refused: \(twice.count) of 30")
        #expect(try service.all().count == 30)
    }
}
