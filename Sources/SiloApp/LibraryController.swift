// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import OpenAPIRuntime  // swiftlint:disable:this unused_import
import SiloAPI
import SiloStore
import SmdKit
import SmdSidecar
import Wire
import WireMVC
import WireOpenAPI

/// The read routes: what a client browses. Everything here is answered from the index.
@Singleton
@OpenAPIController(spec: "SiloAPI")
package struct LibraryController {
    private let libraries: Libraries
    private let index: Index
    private let settings: SettingsStore
    private let checks: CheckService

    @Inject
    package init(libraries: Libraries, index: Index, settings: SettingsStore, checks: CheckService) {
        self.libraries = libraries
        self.index = index
        self.settings = settings
        self.checks = checks
    }

    @Operation
    @ErrorResponse(NoSuchLibrary.self, .notFound)
    package func libraryOutOfDate(@Path library: String) async throws -> Components.Schemas.OutOfDateReport {
        let report = try checks.report(library: library)
        return Components.Schemas.OutOfDateReport(
            presentations: try report.outOfDate.map(Mapping.outOfDate), pending: report.pending, placedWithoutJob: report.placedWithoutJob
        )
    }

    @Operation
    package func listLibraries() async throws -> [Components.Schemas.Library] {
        let counts = LibraryCounts(index: index)
        let standards = Dictionary(settings.current.libraries.map { ($0.id, $0.ruleset) }, uniquingKeysWith: { first, _ in first })
        return try libraries.all.map { library in
            Components.Schemas.Library(
                id: library.id, ruleset: standards[library.id] ?? nil,
                containers: try counts.containers(in: library.id), presentations: try counts.presentations(in: library.id),
                available: libraries.availability(of: library)
            )
        }
    }

    @Operation
    package func listContainers(@Query library: String?) async throws -> [Components.Schemas.ContainerSummary] {
        try index.roots(in: library).map(Mapping.summary)
    }

    /// A container in several libraries is answered from the first that holds it, in the order
    /// `settings.json` lists them; the answer names it.
    @Operation
    @ErrorResponse(NoSuchContainer.self, .notFound)
    package func getContainer(@Path id: String, @Query profile: String?) async throws -> Components.Schemas.Container {
        guard let containerID = ContainerID(id) else { throw NoSuchContainer() }
        let held = Dictionary(try index.containers(containerID).map { ($0.library, $0) }, uniquingKeysWith: { first, _ in first })
        guard let row = libraries.all.lazy.compactMap({ held[$0.id] }).first else { throw NoSuchContainer() }
        return try container(row, profile: profile)
    }

    @Operation
    @ErrorResponse(NoSuchLibrary.self, .notFound)
    package func listLibraryContainers(@Path library: String) async throws -> [Components.Schemas.ContainerSummary] {
        guard libraries.library(library) != nil else { throw NoSuchLibrary() }
        return try index.roots(in: library, listedOnly: false).map(Mapping.summary)
    }

    @Operation
    @ErrorResponse(NoSuchLibrary.self, .notFound)
    @ErrorResponse(NoSuchContainer.self, .notFound)
    package func getLibraryContainer(@Path library: String, @Path id: String) async throws -> Components.Schemas.LibraryContainer {
        guard libraries.library(library) != nil else { throw NoSuchLibrary() }
        guard let containerID = ContainerID(id), let row = try index.container(containerID, in: library) else { throw NoSuchContainer() }
        return Components.Schemas.LibraryContainer(
            library: library, path: "\(row.folder)/\(SidecarFile.fileName)", digest: row.digest, container: try container(row, profile: nil)
        )
    }

    /// One library's row for a container as the document's container, with that library's
    /// presentations and children.
    private func container(_ row: IndexedContainer, profile: String?) throws -> Components.Schemas.Container {
        let sidecar = try SidecarFile.sidecar(from: row.document)
        return Mapping.container(
            row, sidecar: sidecar,
            children: try index.children(of: row.containerID, in: row.library),
            presentations: try index.presentations(of: row.containerID, in: row.library),
            profile: profile
        )
    }

    @Operation
    package func lookup(@Query provider: String, @Query value: String) async throws -> [Components.Schemas.ContainerSummary] {
        try index.lookup(provider: Provider(rawValue: provider), value: value).map(Mapping.summary)
    }

    @Operation
    package func search(@Query q: String) async throws -> [Components.Schemas.SearchHit] {
        try index.search(q).map { Components.Schemas.SearchHit(container: $0.container, item: $0.item, title: $0.title) }
    }

}

/// What a library holds, counted down from its roots through the index.
struct LibraryCounts {
    let index: Index

    func containers(in library: String) throws -> Int {
        var total = 0
        var pending = try index.roots(in: library, listedOnly: false).map(\.containerID)
        while let next = pending.popLast() {
            total += 1
            pending += try index.children(of: next, in: library).map(\.containerID)
        }
        return total
    }

    func presentations(in library: String) throws -> Int {
        var total = 0
        var pending = try index.roots(in: library, listedOnly: false).map(\.containerID)
        while let next = pending.popLast() {
            total += try index.presentations(of: next, in: library).count
            pending += try index.children(of: next, in: library).map(\.containerID)
        }
        return total
    }
}
