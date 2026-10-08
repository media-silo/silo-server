// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloKit
import SiloLibrary
import SiloStore
import SmdKit
import SmdSidecar
import Testing
@testable import SiloApp

/// An application resolved through the rules a library keeps beside its sidecars, and a placement
/// that records in the sidecar what it was made from and by.
struct StackTests {
    /// The serial's folder once a file of it has been placed, and the index told of it.
    static func placeSerial(in bench: JobServiceTests.Bench) throws -> URL {
        let library = bench.config.libraries[0]
        let file = bench.root.appendingPathComponent("part1.mkv")
        try Data("video".utf8).write(to: file)
        try Placer.apply(try Placer.compute(PlacementRequest(library: library.root, lineage: [Fixture.series, Fixture.serial], item: "part1", presentation: Presentation(file: ""), source: file)))
        _ = try Indexer.scan(library, into: bench.index)
        return library.root.appendingPathComponent("Doctor Who (1963)/Pyramids of Mars")
    }

    /// Gives the serial rules at `version`, and tells the index.
    static func serialRules(_ document: String, version: Int, in folder: URL, bench: JobServiceTests.Bench) throws {
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("rules"), withIntermediateDirectories: true)
        try Data(document.utf8).write(to: folder.appendingPathComponent("rules/\(version).xml"))
        let sidecar = folder.appendingPathComponent(SidecarFile.fileName)
        try SidecarFile.data(settingRules: SidecarRules(activeVersion: version), in: Data(contentsOf: sidecar)).write(to: sidecar)
        _ = try Indexer.scan(bench.config.libraries[0], into: bench.index)
    }

    @Test func anApplicationResolvesThroughTheLineagesRulesInForce() throws {
        let bench = try JobServiceTests.Bench()
        defer { bench.remove() }
        let folder = try Self.placeSerial(in: bench)
        let document = #"<rules><audio id="keep-every-mix"><copy/></audio></rules>"#
        try Self.serialRules(document, version: 1, in: folder, bench: bench)

        let draft = try bench.draft(copy: try bench.copy())
        #expect(draft.recipe.audio.allSatisfy { $0.rule == "keep-every-mix" && $0.layer == .layer(.container(Fixture.serial.id.value)) }, "the serial's rule speaks first")
        #expect(draft.recipe.video?.layer == .ruleset("household"), "and what it does not decide falls through")
        #expect(draft.recipe.layers == [RecipeLayer(subject: .container(Fixture.serial.id.value), version: 1, digest: RulesLayerFile.digest(of: Data(document.utf8)))])

        // The rules move on; a draft already made keeps what it was resolved through.
        try Self.serialRules(#"<rules><audio><drop/></audio></rules>"#, version: 2, in: folder, bench: bench)
        #expect(bench.recipes.recipe(draft.id)?.recipe.layers.first?.version == 1)
        #expect(try bench.draft(copy: try bench.copy("again.mkv")).recipe.layers.first?.version == 2)
    }

    @Test func aContainersRulesThatCannotBeReadRefuseTheApplication() throws {
        let bench = try JobServiceTests.Bench()
        defer { bench.remove() }
        let folder = try Self.placeSerial(in: bench)
        try Self.serialRules(#"<rules><audio><copy/></audio></rules>"#, version: 1, in: folder, bench: bench)
        try FileManager.default.removeItem(at: folder.appendingPathComponent("rules/1.xml"))
        let refusal = #expect(throws: Unresolvable.self) { try bench.draft(copy: try bench.copy()) }
        #expect(refusal?.reason == "the rules of container \(Fixture.serial.id.value): rules version 1 is not there")
    }

    @Test func anApplicationNamingNoRulesetTakesTheLibrarysStandard() throws {
        let bench = try JobServiceTests.Bench()
        defer { bench.remove() }
        let source = try bench.sources.register(JobServiceTests.Bench.input, key: nil, copy: try bench.copy()).source
        let binding = try bench.bindingService.make(Binding(library: "main", containers: JobServiceTests.Bench.containers, item: "part3", segments: [Binding.Segment(source: source.id)]))

        let none = #expect(throws: BadApplication.self) { try bench.bindingService.apply(Application(), to: binding.id) }
        #expect(none?.reason == "the application names no ruleset, and library main has none of its own")

        try bench.settings.update { $0.libraries[0].ruleset = "household" }
        let drafts = try bench.bindingService.apply(Application(), to: binding.id)
        #expect(drafts.map(\.recipe.ruleset) == [RulesetRef(name: "household", version: 1), RulesetRef(name: "household", version: 1)], "both of its outputs")
    }

    @Test func aPlacedPresentationRecordsItsBindingAndTheRulesThatMadeIt() async throws {
        let bench = try JobServiceTests.Bench()
        defer { bench.remove() }
        let folder = try Self.placeSerial(in: bench)
        let document = #"<rules><audio><copy/></audio></rules>"#
        try Self.serialRules(document, version: 3, in: folder, bench: bench)

        let key = SiloKit.NaturalKey(scheme: "discTitle", value: "3F1AC2E9/00004.mpls")
        let source = try bench.sources.register(JobServiceTests.Bench.input, key: key, copy: try bench.copy()).source
        let binding = try bench.bindingService.make(Binding(
            library: "main", containers: JobServiceTests.Bench.containers, item: "part3",
            segments: [Binding.Segment(source: source.id, chapters: Binding.ChapterSpan(from: 2, to: 3))]
        ))
        let draft = try #require(try bench.bindingService.apply(Application(ruleset: "household"), to: binding.id).first)
        let job = try bench.service.make(from: draft.id)
        _ = try #require(try await bench.service.claim(node: "box", capabilities: Set(job.requirements)))
        let output = bench.root.appendingPathComponent("encoded.mkv")
        try Fixture.mediaBytes.write(to: output)
        _ = try await bench.service.complete(job.id, output: FileRef(holder: "box", url: output, path: output.path, secret: ""), result: EncodeResult(streams: [], layoutMatched: true))
        _ = try await bench.service.place(job.id)

        let sidecar = try SidecarFile.sidecar(from: Data(contentsOf: folder.appendingPathComponent(SidecarFile.fileName)))
        let presentation = try #require(sidecar.presentations["part3"]?.first)
        #expect(presentation.source == PresentationSource(binding: binding.id, segments: [
            .init(key: SmdSidecar.NaturalKey(scheme: "discTitle", value: "3F1AC2E9/00004.mpls"), chapters: SmdSidecar.ChapterSpan(from: 2, to: 3)),
        ]))
        #expect(presentation.transform == Transform(ruleset: "household", version: 1, layers: [
            Transform.Layer(.container(Fixture.serial.id), version: 3, digest: RulesLayerFile.digest(of: Data(document.utf8))),
        ]))
        #expect(sidecar.rules == SidecarRules(activeVersion: 3), "and the serial's own rules as they were")
    }
}
