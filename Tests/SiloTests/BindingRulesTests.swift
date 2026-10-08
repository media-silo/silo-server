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

/// A person's decision about one entry, as the binding's own rules: the nearest layer, kept in the
/// silo until the binding's first file is placed and in the library after.
struct BindingRulesTests {
    static let dropFirst = #"<rules><audio id="drop-the-first"><when fact="audio.index" is="1"/><drop/></audio></rules>"#

    /// A binding of part three, made from a source with one copy.
    static func binding(in bench: JobServiceTests.Bench) throws -> Binding {
        let source = try bench.sources.register(JobServiceTests.Bench.input, key: nil, copy: try bench.copy()).source
        return try bench.bindingService.make(Binding(library: "main", containers: JobServiceTests.Bench.containers, item: "part3", segments: [Binding.Segment(source: source.id)]))
    }

    /// Places a job made from the binding's unqualified output.
    static func place(_ binding: Binding, in bench: JobServiceTests.Bench) async throws {
        let draft = try #require(try bench.bindingService.apply(Application(ruleset: "household", outputs: [Application.OutputChoice()]), to: binding.id).first)
        let job = try bench.service.make(from: draft.id)
        _ = try #require(try await bench.service.claim(node: "box", capabilities: Set(job.requirements)))
        let output = bench.root.appendingPathComponent("encoded-\(job.id).mkv")
        try Fixture.mediaBytes.write(to: output)
        _ = try await bench.service.complete(job.id, output: FileRef(holder: "box", url: output, path: output.path, secret: ""), result: EncodeResult(streams: [], layoutMatched: true))
        _ = try await bench.service.place(job.id)
    }

    @Test func aBindingsRuleSpeaksAheadOfEveryContainers() throws {
        let bench = try JobServiceTests.Bench()
        defer { bench.remove() }
        let folder = try StackTests.placeSerial(in: bench)
        try StackTests.serialRules(#"<rules><audio><copy/></audio></rules>"#, version: 1, in: folder, bench: bench)
        let binding = try Self.binding(in: bench)
        #expect(try bench.bindingService.setRules(Data(Self.dropFirst.utf8), of: binding.id) == 1)

        let draft = try #require(try bench.bindingService.apply(Application(ruleset: "household"), to: binding.id).first)
        #expect(draft.recipe.audio.map(\.action) == [.drop, .copy])
        #expect(draft.recipe.audio[0].layer == .layer(.binding(binding.id)) && draft.recipe.audio[0].rule == "drop-the-first")
        #expect(draft.recipe.audio[1].layer == .layer(.container(Fixture.serial.id.value)), "the rest falls through to the serial's")
        #expect(draft.recipe.layers.map(\.subject) == [.binding(binding.id), .container(Fixture.serial.id.value)], "the binding's layer is nearest")
    }

    @Test func rulesStoredBeforePlacementMoveIntoTheLibraryWithTheFirstFile() async throws {
        let bench = try JobServiceTests.Bench()
        defer { bench.remove() }
        let binding = try Self.binding(in: bench)
        #expect(throws: BadBindingRules.self) { try bench.bindingService.setRules(Data(#"<rules><output container="mp4"/></rules>"#.utf8), of: binding.id) }
        #expect(try bench.bindingService.setRules(Data(#"<rules><audio><copy/></audio></rules>"#.utf8), of: binding.id) == 1)
        #expect(try bench.bindingService.setRules(Data(Self.dropFirst.utf8), of: binding.id) == 2)
        #expect(bench.stagedRules.versions(of: binding.id) == [1, 2], "kept in the silo while nothing is placed")
        let library = bench.config.libraries[0].root
        let folder = library.appendingPathComponent("Doctor Who (1963)/Pyramids of Mars")
        #expect(!FileManager.default.fileExists(atPath: folder.path), "and nothing written to the library")
        #expect(try bench.bindingService.rules(of: binding.id).versions == [1, 2])

        try await Self.place(binding, in: bench)

        let rules = folder.appendingPathComponent("rules/bindings/\(binding.id)")
        #expect(try String(contentsOf: rules.appendingPathComponent("1.xml"), encoding: .utf8).contains("<copy/>"))
        #expect(try String(contentsOf: rules.appendingPathComponent("2.xml"), encoding: .utf8) == Self.dropFirst)
        let sidecar = try SidecarFile.sidecar(from: Data(contentsOf: folder.appendingPathComponent(SidecarFile.fileName)))
        #expect(sidecar.bindingRules["part3"] == [BindingRules(binding: binding.id, rules: SidecarRules(path: "rules/bindings/\(binding.id)", activeVersion: 2))])
        let transform = try #require(sidecar.presentations["part3"]?.first?.transform)
        #expect(transform.layers.first == Transform.Layer(.binding(binding.id), version: 2, digest: RulesLayerFile.digest(of: Data(Self.dropFirst.utf8))), "the file names the version it was made by")
        #expect(bench.stagedRules.versions(of: binding.id).isEmpty, "and the silo keeps them no more")
        #expect(LibraryWalker.walk(library).findings.isEmpty)

        // A later decision goes straight to the library, and the reference moves.
        #expect(try bench.bindingService.setRules(Data(#"<rules><audio><drop/></audio></rules>"#.utf8), of: binding.id) == 3)
        #expect(FileManager.default.fileExists(atPath: rules.appendingPathComponent("3.xml").path))
        #expect(try SidecarFile.sidecar(from: Data(contentsOf: folder.appendingPathComponent(SidecarFile.fileName))).bindingRules["part3"]?.first?.rules.activeVersion == 3)
        #expect(bench.stagedRules.versions(of: binding.id).isEmpty)
        let read = try bench.bindingService.rules(of: binding.id)
        #expect(read.active == 3 && read.versions == [1, 2, 3])
        let draft = try #require(try bench.bindingService.apply(Application(ruleset: "household"), to: binding.id).first)
        #expect(draft.recipe.layers.first?.version == 3, "the next draft is made through the version in force")
    }

    @Test func theWalkReportsABindingsRulesItCannotUseOrThatNothingUses() async throws {
        let bench = try JobServiceTests.Bench()
        defer { bench.remove() }
        let binding = try Self.binding(in: bench)
        _ = try bench.bindingService.setRules(Data(Self.dropFirst.utf8), of: binding.id)
        try await Self.place(binding, in: bench)
        let library = bench.config.libraries[0].root
        let sidecarURL = library.appendingPathComponent("Doctor Who (1963)/Pyramids of Mars/\(SidecarFile.fileName)")

        let other = "9d3f0b6e-1c2a-4f7d-8e5b-a2b4c6d8e0f1"
        try SidecarFile.data(settingRules: SidecarRules(path: "rules/bindings/\(other)", activeVersion: 1), binding: other, item: "part3", in: Data(contentsOf: sidecarURL)).write(to: sidecarURL)
        #expect(LibraryWalker.walk(library).findings.map(\.description) == [
            "error: Doctor Who (1963)/Pyramids of Mars/container.smd: binding \(other): rules version 1 is not there",
            "warning: Doctor Who (1963)/Pyramids of Mars/container.smd: rules for binding \(other), which no presentation of part3 names",
        ])
    }
}
