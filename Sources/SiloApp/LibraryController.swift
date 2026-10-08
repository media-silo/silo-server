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
    private let settings: SettingsStore

    @Inject
    package init(config: SiloConfig, index: Index, settings: SettingsStore) {
        self.config = config
        self.index = index
        self.settings = settings
    }

    @Operation
    package func listLibraries() async throws -> [Components.Schemas.Library] {
        let counts = LibraryCounts(index: index)
        let standards = Dictionary(settings.current.libraries.map { ($0.id, $0.ruleset) }, uniquingKeysWith: { first, _ in first })
        return try config.libraries.map { library in
            Components.Schemas.Library(
                id: library.id, ruleset: standards[library.id] ?? nil,
                containers: try counts.containers(in: library.id), presentations: try counts.presentations(in: library.id)
            )
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

}

/// What a library holds, counted down from its roots through the index.
struct LibraryCounts {
    let index: Index

    func containers(in library: String) throws -> Int {
        var total = 0
        var pending = try index.roots(in: library, listedOnly: false).map(\.containerID)
        while let next = pending.popLast() {
            total += 1
            pending += try index.children(of: next).map(\.containerID)
        }
        return total
    }

    func presentations(in library: String) throws -> Int {
        var total = 0
        var pending = try index.roots(in: library, listedOnly: false).map(\.containerID)
        while let next = pending.popLast() {
            total += try index.presentations(of: next).count
            pending += try index.children(of: next).map(\.containerID)
        }
        return total
    }
}
