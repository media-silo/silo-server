// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import OpenAPIRuntime  // swiftlint:disable:this unused_import
import SiloAPI
import SiloStore
import SmdKit
import Wire
import WireMVC
import WireOpenAPI

/// The read routes: what a client browses. Everything here is answered from the index.
@Singleton
@OpenAPIController(spec: "SiloAPI")
package struct LibraryController {
    private let config: SiloConfig
    private let index: Index

    @Inject
    package init(config: SiloConfig, index: Index) {
        self.config = config
        self.index = index
    }

    @Operation
    package func listLibraries() async throws -> [Components.Schemas.Library] {
        try config.libraries.map { library in
            let rows = try index.roots(in: library.id, listedOnly: false)
            let presentations = try rows.reduce(0) { total, root in
                total + (try countPresentations(under: root.containerID))
            }
            return Components.Schemas.Library(id: library.id, containers: try countContainers(under: rows.map(\.containerID)), presentations: presentations)
        }
    }

    @Operation
    package func listContainers(@Query library: String?) async throws -> [Components.Schemas.ContainerSummary] {
        try index.roots(in: library).map(Mapping.summary)
    }

    @Operation
    @ErrorResponse(NoSuchContainer.self, .notFound)
    package func getContainer(@Path id: String, @Query profile: String?) async throws -> Components.Schemas.Container {
        guard let containerID = ContainerID(id), let row = try index.container(containerID), let sidecar = try index.sidecar(containerID) else {
            throw NoSuchContainer()
        }
        return Mapping.container(
            row, sidecar: sidecar,
            children: try index.children(of: containerID),
            presentations: try index.presentations(of: containerID),
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

    private func countContainers(under roots: [ContainerID]) throws -> Int {
        var total = 0
        var pending = roots
        while let next = pending.popLast() {
            total += 1
            pending += try index.children(of: next).map(\.containerID)
        }
        return total
    }

    private func countPresentations(under root: ContainerID) throws -> Int {
        var total = 0
        var pending = [root]
        while let next = pending.popLast() {
            total += try index.presentations(of: next).count
            pending += try index.children(of: next).map(\.containerID)
        }
        return total
    }
}
