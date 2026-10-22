// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import OpenAPIRuntime  // swiftlint:disable:this unused_import
import SiloAPI
import SiloKit
import SiloLibrary
import SiloStore
import SmdKit
import SmdSidecar
import Wire
import WireMVC
import WireOpenAPI

/// The operations that change the silo — adding and removing a library, a placement, making and
/// editing containers, a library's standard, and storing a ruleset — and the one read that names paths inside a library, its last
/// walk. Grouped here so that one
/// middleware on the controller is the whole of the operator gate.
@Singleton
@OpenAPIController(spec: "SiloAPI")
@Middleware(RouteMiddleware.requireOperator)
package struct OperatorController {
    private let libraries: Libraries
    private let index: Index
    private let store: RulesetStore
    private let settings: SettingsStore
    private let checks: CheckSignal
    private let jobs: JobService

    @Inject
    package init(
        libraries: Libraries,
        index: Index,
        store: RulesetStore,
        settings: SettingsStore,
        checks: CheckSignal,
        jobs: JobService
    ) {
        self.jobs = jobs
        self.libraries = libraries
        self.index = index
        self.store = store
        self.settings = settings
        self.checks = checks
    }

    @Operation
    @JSONResponse(status: .created)
    @ErrorResponse(LibraryTaken.self, .conflict, { Components.Schemas.Problem(detail: $0.reason) })
    @ErrorResponse(OutsideTheRoots.self, .forbidden, { Components.Schemas.Problem(detail: $0.reason) })
    @ErrorResponse(BadLibrary.self, .unprocessableContent, { Components.Schemas.Problem(detail: $0.reason) })
    package func addLibrary(@JSONBody body: Components.Schemas.NewLibrary) async throws -> Components.Schemas.Library {
        let library = try await libraries.add(id: body.id, path: body.path, create: body.create ?? false)
        return try listing(library.id, ruleset: library.ruleset)
    }

    /// What `addLibrary` would find and answer for the same body, making and writing nothing.
    @Operation
    package func checkLibrary(
        @JSONBody body: Components.Schemas.NewLibrary
    ) async throws -> Components.Schemas.LibraryCheck {
        let check = libraries.check(id: body.id, path: body.path, create: body.create ?? false)
        return Components.Schemas.LibraryCheck(
            path: check.path,
            components: check.components.map {
                Components.Schemas.PathComponent(path: $0.path, state: .init(rawValue: $0.state.rawValue)!)
            },
            root: check.root,
            creates: check.creates,
            refusal: check.refusal.map { refusal in
                switch refusal {
                case .bad(let detail): Components.Schemas.LibraryRefusal(status: 422, detail: detail)
                case .outside(let detail): Components.Schemas.LibraryRefusal(status: 403, detail: detail)
                case .taken(let detail): Components.Schemas.LibraryRefusal(status: 409, detail: detail)
                }
            }
        )
    }

    /// Forgets a library — its entry in `settings.json` and its rows in the index — and leaves every
    /// file under it where it is. Refused while a job not yet in a final state names it.
    @Operation
    @ResponseStatus(.noContent)
    @ErrorResponse(NoSuchLibrary.self, .notFound)
    @ErrorResponse(LibraryHeld.self, .conflict, { Components.Schemas.Problem(detail: $0.reason) })
    package func removeLibrary(@Path library: String) async throws {
        guard libraries.library(library) != nil else { throw NoSuchLibrary() }
        if let job = jobs.liveJob(in: library) {
            throw LibraryHeld(reason: "job \(job.id) is \(job.state.rawValue) and files into \(library)")
        }
        try await libraries.remove(library)
    }

    /// Names the library's standard, or clears it: written through to `settings.json` at once, so
    /// the next application that names no ruleset takes it.
    @Operation
    @ErrorResponse(NoSuchLibrary.self, .notFound)
    @ErrorResponse(NoSuchRuleset.self, .notFound)
    package func setLibraryRuleset(
        @Path library: String,
        @JSONBody body: Components.Schemas.LibraryRuleset
    ) async throws -> Components.Schemas.Library {
        guard libraries.library(library) != nil else { throw NoSuchLibrary() }
        if let name = body.ruleset {
            guard try store.latestVersion(of: name) != nil else { throw NoSuchRuleset() }
        }
        let updated = try settings.update { settings in
            guard let position = settings.libraries.firstIndex(where: { $0.id == library }) else { return }
            settings.libraries[position].ruleset = body.ruleset
        }
        return try listing(library, ruleset: updated.libraries.first { $0.id == library }?.ruleset)
    }

    private func listing(_ library: String, ruleset: String?) throws -> Components.Schemas.Library {
        let counts = LibraryCounts(index: index)
        return Components.Schemas.Library(
            id: library,
            ruleset: ruleset,
            containers: try counts.containers(in: library),
            presentations: try counts.presentations(in: library),
            available: libraries.isAvailable(library)
        )
    }

    @Operation
    @ErrorResponse(NoSuchLibrary.self, .notFound)
    package func lastWalk(@Path library: String) async throws -> Components.Schemas.LastWalk {
        guard libraries.library(library) != nil, let walk = libraries.lastWalk(of: library) else {
            throw NoSuchLibrary()
        }
        let report = walk.report
        return Components.Schemas.LastWalk(
            walkedAt: walk.walkedAt,
            available: walk.available,
            report: Components.Schemas.ScanReport(
                read: report.read,
                unchanged: report.unchanged,
                removed: report.removed,
                findings: report.findings.map(Mapping.finding)
            )
        )
    }

    /// Makes a tree of containers in one library with no file, beneath a container it holds or at
    /// its top.
    @Operation
    @ErrorResponse(NoSuchLibrary.self, .notFound)
    @ErrorResponse(NoSuchContainer.self, .notFound)
    @ErrorResponse(BadCreate.self, .badRequest, { Components.Schemas.Problem(detail: $0.reason) })
    @ErrorResponse(CreateRefusedResult.self, .unprocessableContent, { $0.result })
    package func createContainers(
        @Path library: String,
        @JSONBody body: Components.Schemas.ContainerCreate
    ) async throws -> Components.Schemas.ContainerCreateResult {
        guard let library = libraries.library(library) else { throw NoSuchLibrary() }
        do {
            let outcome = try await ContainerMaker.create(
                body.documents,
                parent: body.parent,
                attributions: (body.attributions ?? []).map {
                    (
                        container: $0.container,
                        attribution: Attribution(
                            subject: Attribution.Subject(rawValue: $0.subject),
                            provider: Provider(rawValue: $0.provider),
                            value: $0.value
                        )
                    )
                },
                in: library,
                dryRun: body.dryRun ?? false,
                libraries: libraries,
                index: index
            )
            return Mapping.createResult(outcome, in: library)
        } catch let refused as CreateRefused {
            throw CreateRefusedResult(result: Mapping.createResult(refused.outcome, in: library))
        }
    }

    /// Renames every folder in the library not named as the layout names its container, from the
    /// top down, and walks the library in the same turn.
    @Operation
    @ErrorResponse(NoSuchLibrary.self, .notFound)
    @ErrorResponse(LibraryIsUnavailable.self, .serviceUnavailable)
    package func layOutLibrary(
        @Path library: String,
        @JSONBody body: Components.Schemas.LayoutRequest
    ) async throws -> Components.Schemas.LayoutResult {
        guard let library = libraries.library(library) else { throw NoSuchLibrary() }
        guard try await libraries.reach(library) else { throw LibraryIsUnavailable() }
        let dryRun = body.dryRun ?? false
        let outcome = try await libraries.exclusively(
            library,
            walkingAfter: { !dryRun && !$0.moves.isEmpty },
            doing: {
                Relayout.layOut(LibraryWalker.walk(library.root), dryRun: dryRun)
            }
        )
        return Components.Schemas.LayoutResult(
            applied: !dryRun,
            moves: outcome.moves.map(Mapping.move),
            findings: outcome.findings.map(Mapping.finding)
        )
    }

    /// Sets a container's own fields in one library's sidecar, onto the sidecar the editor read.
    @Operation
    @ErrorResponse(NoSuchLibrary.self, .notFound)
    @ErrorResponse(NoSuchContainer.self, .notFound)
    @ErrorResponse(BadEdit.self, .badRequest, { Components.Schemas.Problem(detail: $0.reason) })
    @ErrorResponse(EditConflict.self, .conflict, { Components.Schemas.Problem(detail: $0.reason) })
    @ErrorResponse(EditRefusedResult.self, .unprocessableContent, { $0.result })
    package func editContainer(
        @Path library: String,
        @Path id: String,
        @JSONBody body: Components.Schemas.ContainerEdit
    ) async throws -> Components.Schemas.ContainerEditResult {
        guard let library = libraries.library(library) else { throw NoSuchLibrary() }
        guard let id = ContainerID(id) else { throw NoSuchContainer() }
        do {
            let outcome = try await ContainerEditor.edit(
                id,
                in: library,
                document: body.document,
                basedOn: body.basedOn,
                attributions: body.attributions?.map {
                    Attribution(
                        subject: Attribution.Subject(rawValue: $0.subject),
                        provider: Provider(rawValue: $0.provider),
                        value: $0.value
                    )
                },
                declined: body.declined?.map {
                    ExternalRef(provider: Provider(rawValue: $0.provider), value: $0.value)
                },
                dryRun: body.dryRun ?? false,
                libraries: libraries,
                index: index
            )
            return Mapping.editResult(outcome)
        } catch let refused as EditRefused {
            throw EditRefusedResult(result: Mapping.editResult(refused.outcome))
        }
    }

    @Operation
    @ErrorResponse(NoSuchLibrary.self, .notFound)
    @ErrorResponse(BadPlacement.self, .badRequest, { Components.Schemas.Problem(detail: $0.reason) })
    @ErrorResponse(PlacementRefused.self, .conflict, { $0.result })
    package func placeFile(
        @Path library: String,
        @JSONBody body: Components.Schemas.PlaceRequest
    ) async throws -> Components.Schemas.PlacementResult {
        guard let library = libraries.library(library) else { throw NoSuchLibrary() }
        let lineage: [SmdKit.Container]
        do {
            lineage = try body.containers.map { try ContainerFile.container(from: Data($0.utf8)) }
        } catch {
            throw BadPlacement(reason: "a container document cannot be read: \(error.localizedDescription)")
        }
        var presentation = Presentation(alternative: body.alternative, profile: body.profile, file: "")
        presentation.tracks = (body.tracks ?? []).map {
            TrackMapping(feature: $0.feature, audio: $0.audio, subtitle: $0.subtitle)
        }
        presentation.chapters = (body.chapters ?? []).map { Chapter(index: $0.index, title: $0.title) }
        let request = PlacementRequest(
            library: library.root,
            lineage: lineage,
            item: body.item,
            presentation: presentation,
            source: URL(fileURLWithPath: body.file)
        )
        let placement: Placement
        do {
            placement = try Placer.compute(request)
        } catch let error as PlacementError {
            throw BadPlacement(reason: error.localizedDescription)
        }
        let destination = LibraryWalker.relativePath(of: placement.destination, in: library.root)
        var result = Components.Schemas.PlacementResult(
            applied: false,
            destination: destination,
            presentation: nil,
            writes: placement.describe(relativeTo: library.root),
            findings: placement.findings.map(Mapping.finding)
        )
        guard placement.isApplicable else { throw PlacementRefused(result: result) }
        guard body.dryRun != true else { return result }
        try Placer.apply(placement, move: body.copy != true)
        // What the placement wrote, root first, and nothing else: whatever changed in the library
        // without the server is the walk's to find.
        try await libraries.reread(placement.sidecars, in: library)
        result.applied = true
        result.presentation = IndexedPresentation.id(library: library.id, placed: placement)
        return result
    }

    @Operation
    @ErrorResponse(BadRuleset.self, .badRequest, { Components.Schemas.Problem(detail: $0.reason) })
    @ErrorResponse(BranchConflict.self, .conflict, { Components.Schemas.Problem(detail: $0.reason) })
    package func storeRuleset(
        @Path name: String,
        @JSONBody body: Components.Schemas.RulesetDocument
    ) async throws -> Components.Schemas.RulesetDocument {
        let data = Data(body.document.utf8)
        let version: Int
        do {
            version = try store.store(
                data,
                as: name,
                branch: body.branch,
                upToDateWith: body.upToDateWith,
                basedOn: body.basedOn
            )
            checks.request()
        } catch let error as RulesetFileError {
            throw BadRuleset(reason: error.description)
        } catch let error as RulesetStoreError {
            switch error {
            case .branchClosed, .notTheHead: throw BranchConflict(reason: error.description)
            default: throw BadRuleset(reason: error.description)
            }
        }
        return Components.Schemas.RulesetDocument(
            name: name,
            version: version,
            branch: body.branch ?? RulesetStore.standard,
            document: body.document
        )
    }

    @Operation
    @JSONResponse(status: .created)
    @ErrorResponse(NoSuchRuleset.self, .notFound)
    @ErrorResponse(BadRuleset.self, .badRequest, { Components.Schemas.Problem(detail: $0.reason) })
    @ErrorResponse(BranchConflict.self, .conflict, { Components.Schemas.Problem(detail: $0.reason) })
    package func startBranch(
        @Path name: String,
        @JSONBody body: Components.Schemas.NewBranch
    ) async throws -> Components.Schemas.Branch {
        guard try store.latestVersion(of: name) != nil else { throw NoSuchRuleset() }
        do {
            return Mapping.branch(try store.startBranch(body.name, of: name, from: body.from))
        } catch let error as RulesetStoreError {
            if case .branchExists = error { throw BranchConflict(reason: error.description) }
            throw BadRuleset(reason: error.description)
        }
    }

    @Operation
    @JSONResponse(status: .created)
    @ErrorResponse(NoSuchRuleset.self, .notFound)
    @ErrorResponse(BranchConflict.self, .conflict, { Components.Schemas.Problem(detail: $0.reason) })
    package func promoteBranch(
        @Path name: String,
        @Path branch: String
    ) async throws -> Components.Schemas.RulesetSummary {
        do {
            let version = try store.promote(branch, of: name)
            checks.request()
            return Components.Schemas.RulesetSummary(name: name, version: version)
        } catch let error as RulesetStoreError {
            if case .noSuchBranch = error { throw NoSuchRuleset() }
            throw BranchConflict(reason: error.description)
        }
    }
}
