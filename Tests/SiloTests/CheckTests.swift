// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloAPI
import SiloKit
import SiloLibrary
import SiloStore
import SmdKit
import SmdSidecar
import Testing
@testable import SiloApp

/// The background check: each placed presentation resolved again through the rules in force, and
/// what that found recorded; out of date about decisions, not versions.
struct CheckTests {
    typealias Bench = JobServiceTests.Bench

    /// The household ruleset with its commentaries at 96k.
    static let speech96k = Bench.household.replacingOccurrences(of: #"bitrate="160k""#, with: #"bitrate="96k""#)

    /// A film of its own, at the library's root: a lineage that holds none of the serial's rules.
    static let film: Container = {
        var film = Container(id: ContainerID("00000000000000f1")!, type: .movie, title: Title("The Brain of Morbius")!)
        film.sequences = [Sequence(id: "feature", items: [.leaf(Entry.Leaf(id: ItemID("feature")!, type: .movie, title: "Feature"))])]
        return film
    }()

    /// Binds an item to a source of its own, applies the household ruleset's unqualified output as
    /// `application` says, and places a job made from the draft. Answers the job.
    @discardableResult
    static func placed(_ bench: Bench, item: String = "part3", containers: [String] = Bench.containers, application: Application = Application(ruleset: "household"), name: String = UUID().uuidString) async throws -> Job {
        let source = try bench.sources.register(Bench.input, key: nil, copy: try bench.copy("\(name).mkv")).source
        // Audio 2 is the serial's commentary; a film has no such feature.
        let tracks = containers == Bench.containers ? [TrackMapping(feature: "commentary1", audio: 2)] : []
        let binding = try bench.bindingService.make(Binding(library: "main", containers: containers, item: item, tracks: tracks, segments: [Binding.Segment(source: source.id)]))
        var unqualified = application
        unqualified.outputs = [Application.OutputChoice()]
        let draft = try #require(try bench.bindingService.apply(unqualified, to: binding.id).first)
        let job = try bench.service.make(from: draft.id)
        _ = try #require(try await bench.service.claim(node: "box", capabilities: Set(job.requirements)))
        let output = bench.root.appendingPathComponent("encoded-\(name).mkv")
        try Fixture.mediaBytes.write(to: output)
        _ = try await bench.service.complete(job.id, output: FileRef(holder: "box", url: output, path: output.path, secret: ""), result: EncodeResult(streams: [], layoutMatched: true))
        return try await bench.service.place(job.id)
    }

    @Test func aPromotionThatChangesADecisionLeavesThePresentationOutOfDate() async throws {
        let bench = try Bench()
        defer { bench.remove() }
        let job = try await Self.placed(bench)
        #expect(try bench.checkService.pass() == 1)
        #expect(bench.checks.check(of: job.id)?.outcome == .current, "checked against the rules that made it")
        #expect(bench.checks.check(of: job.id)?.checkedAgainst.ruleset == RulesetRef(name: "household", version: 1))

        _ = try bench.rulesets.startBranch("speech-96k", of: "household", from: 1)
        _ = try bench.rulesets.store(Data(Self.speech96k.utf8), as: "household", branch: "speech-96k")
        let impact = try bench.checkService.impact(of: "speech-96k", of: "household")
        #expect(impact.map(\.recipe.id) == [job.recipe], "what promotion would change, before it does")
        #expect(try bench.checkService.pass() == 0, "a store on a branch changes no stack in force")

        #expect(try bench.rulesets.promote("speech-96k", of: "household") == 3)
        #expect(try bench.checkService.pass() == 1)
        let check = try #require(bench.checks.check(of: job.id))
        #expect(check.outcome == .outOfDate)
        #expect(check.checkedAgainst.ruleset == RulesetRef(name: "household", version: 3))
        #expect(check.changes == [StreamChange(
            kind: .audio, index: 2,
            was: .encode(EncodeSettings(codec: "aac", bitrate: "160k", channels: 2)), now: .encode(EncodeSettings(codec: "aac", bitrate: "96k", channels: 2))
        )], "the commentary, from 160k to 96k")
        let report = try bench.checkService.report(library: "main")
        #expect(report.outOfDate.map(\.recipe.id) == impact.map(\.recipe.id), "the impact was the outcome")
        #expect(report.pending == 0)
        #expect(report.outOfDate.first?.sources.first?.copies.count == 1, "with its sources and their copies")
        #expect(try bench.checkService.pass() == 0, "and nothing is checked twice")
    }

    @Test func aPromotionThatChangesNothingForAPresentationLeavesItCurrent() async throws {
        let bench = try Bench()
        defer { bench.remove() }
        _ = try bench.rulesets.startBranch("speech-96k", of: "household", from: 1)
        _ = try bench.rulesets.store(Data(Self.speech96k.utf8), as: "household", branch: "speech-96k")
        let job = try await Self.placed(bench, application: Application(ruleset: "household", branch: "speech-96k"))
        _ = try bench.checkService.pass()
        _ = try bench.rulesets.promote("speech-96k", of: "household")
        #expect(try bench.checkService.pass() == 1, "the branch is promoted, so its presentations meet the standard's head")
        let check = try #require(bench.checks.check(of: job.id))
        #expect(check.outcome == .current)
        #expect(check.checkedAgainst.ruleset == RulesetRef(name: "household", version: 3), "made by version 2, checked against version 3")
    }

    @Test func aContainersRulesReachThePresentationsBelowItAndNoOthers() async throws {
        let bench = try Bench()
        defer { bench.remove() }
        let folder = try StackTests.placeSerial(in: bench)
        let below = try await Self.placed(bench, name: "below")
        let elsewhere = try await Self.placed(bench, item: "feature", containers: [String(decoding: ContainerFile.data(for: Self.film), as: UTF8.self)], name: "elsewhere")
        #expect(try bench.checkService.pass() == 2)
        let before = try #require(bench.checks.check(of: elsewhere.id))

        try StackTests.serialRules(#"<rules><audio><copy/></audio></rules>"#, version: 1, in: folder, bench: bench)
        #expect(try bench.checkService.pass() == 1, "only the presentation below the serial")
        #expect(bench.checks.check(of: below.id)?.outcome == .outOfDate)
        #expect(bench.checks.check(of: below.id)?.checkedAgainst.layers.map(\.subject) == [.container(Fixture.serial.id.value)])
        #expect(bench.checks.check(of: elsewhere.id) == before, "and the film's check is as it was")
        #expect(try bench.checkService.report(library: "main").placedWithoutJob == 1, "the serial's part one was placed by hand")
    }

    @Test func aPersonsDecisionStandsWhenTheRulesBeneathItChange() async throws {
        let bench = try Bench()
        defer { bench.remove() }
        let source = try bench.sources.register(Bench.input, key: nil, copy: try bench.copy()).source
        let binding = try bench.bindingService.make(Binding(library: "main", containers: Bench.containers, item: "part3", tracks: [TrackMapping(feature: "commentary1", audio: 2)], segments: [Binding.Segment(source: source.id)]))
        _ = try bench.bindingService.setRules(Data(#"<rules><audio><when fact="audio.index" is="2"/><copy/></audio></rules>"#.utf8), of: binding.id)
        let draft = try #require(try bench.bindingService.apply(Application(ruleset: "household", outputs: [Application.OutputChoice()]), to: binding.id).first)
        let job = try bench.service.make(from: draft.id)
        _ = try await bench.service.claim(node: "box", capabilities: Set(job.requirements))
        let output = bench.root.appendingPathComponent("encoded.mkv")
        try Fixture.mediaBytes.write(to: output)
        _ = try await bench.service.complete(job.id, output: FileRef(holder: "box", url: output, path: output.path, secret: ""), result: EncodeResult(streams: [], layoutMatched: true))
        _ = try await bench.service.place(job.id)
        _ = try bench.checkService.pass()

        #expect(draft.recipe.audio[1].layer == .layer(.binding(binding.id)), "the commentary is the binding's rule's to decide")
        _ = try bench.rulesets.store(Data(Self.speech96k.utf8), as: "household")
        #expect(try bench.checkService.pass() == 1)
        #expect(bench.checks.check(of: job.id)?.outcome == .current, "and still decided so, whatever the ruleset says of commentaries")
    }

    @Test func aCheckStoppedHalfWayResumesWithWhatIsLeft() async throws {
        let bench = try Bench()
        defer { bench.remove() }
        for item in ["part1", "part2", "part3"] { try await Self.placed(bench, item: item, name: item) }
        _ = try bench.checkService.pass()
        _ = try bench.rulesets.store(Data(Self.speech96k.utf8), as: "household")

        var checked = 0
        #expect(try bench.checkService.pass(stop: { defer { checked += 1 }; return checked == 1 }) == 1, "stopped after one")
        #expect(try bench.checkService.report(library: "main").pending == 2)
        #expect(try bench.checkService.pass() == 2, "the rest, and not the one already done")
        #expect(try bench.checkService.report(library: "main").pending == 0)
        #expect(try bench.checkService.report(library: "main").outOfDate.count == 3)
    }

    @Test func aDraftsImpactIsWhatTheCheckFindsOnceItIsInForce() async throws {
        let bench = try Bench()
        defer { bench.remove() }
        let changed = try await Self.placed(bench, name: "changed")
        _ = try await Self.placed(bench, item: "feature", containers: [String(decoding: ContainerFile.data(for: Self.film), as: UTF8.self)], name: "unchanged")
        _ = try bench.checkService.pass()

        let draft = try bench.rulesets.read(Data(Self.speech96k.utf8), as: "household")
        let impact = try bench.checkService.impact(ofDraft: draft, basedOn: 1, of: "household")
        #expect(impact.map(\.recipe.id) == [changed.recipe], "the film has no commentary for the draft to change")
        #expect(impact.first?.check.changes.map(\.index) == [2])
        #expect(try bench.rulesets.versions(of: "household") == [1], "and nothing is stored")
        #expect(throws: NoSuchRuleset.self) { try bench.checkService.impact(ofDraft: draft, basedOn: 9, of: "household") }

        _ = try bench.rulesets.store(Data(Self.speech96k.utf8), as: "household", basedOn: 1)
        #expect(try bench.checkService.pass() == 2)
        let report = try bench.checkService.report(library: "main")
        #expect(report.outOfDate.map(\.recipe.id) == impact.map(\.recipe.id), "the impact was the outcome")
        #expect(report.outOfDate.first?.check.changes == impact.first?.check.changes)
    }

    @Test func eachVersionReportsThePresentationsItMade() async throws {
        let bench = try Bench()
        defer { bench.remove() }
        for item in ["part1", "part2", "part3"] { try await Self.placed(bench, item: item, name: item) }
        _ = try bench.rulesets.store(Data(Self.speech96k.utf8), as: "household")
        #expect(bench.checkService.made(by: "household") == [1: 3])

        let summary = try #require(try await RulesetController(store: bench.rulesets, checks: bench.checkService).listRulesets().first { $0.name == "household" })
        #expect(summary.versions?.map(\.presentations) == [3, 0], "three made by version 1, none by version 2")
        #expect(summary.versions?.map(\.parent) == [nil, 1])
        #expect(summary.standard == 2)
    }
}
