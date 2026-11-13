// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import SiloAPI
import SiloStore
import Wire
import WireMVC
import WireOpenAPI

/// A library's stores: handed to the silo whole under a key, answered at once, and said at a route of
/// their own as the silo makes them. Behind the operator's token. `Stores.md`.
@Singleton
@OpenAPIController(spec: "SiloAPI")
@Middleware(RouteMiddleware.requireOperator)
package struct StoreController {
    private let libraries: Libraries
    private let stores: StoreService

    @Inject
    package init(libraries: Libraries, stores: StoreService) {
        self.libraries = libraries
        self.stores = stores
    }

    /// Raw, because which success it answers — 202 for a store taken, 200 for one the key already
    /// names — is decided by the key, not by the handler's signature.
    @RawOperation
    package func createStore(_ input: Operations.createStore.Input) async throws -> Operations.createStore.Output {
        let body =
            switch input.body {
            case .json(let body): body
            }
        guard let library = libraries.library(input.path.library) else { return .notFound(.init()) }
        do {
            let steps = try body.steps.map { try Mapping.transcode($0, to: StoreStep.self) }
            let taken = try stores.take(steps, key: body.key, in: library)
            let record = try Self.record(taken.record)
            return taken.added ? .accepted(.init(body: .json(record))) : .ok(.init(body: .json(record)))
        } catch let taken as StoreKeyTaken {
            return .conflict(.init(body: .json(Components.Schemas.Problem(detail: taken.reason))))
        } catch let bad as BadStoreKey {
            return .badRequest(.init(body: .json(Components.Schemas.Problem(detail: bad.reason))))
        } catch DecodingError.dataCorrupted(let context) {
            return .badRequest(.init(body: .json(Components.Schemas.Problem(detail: context.debugDescription))))
        }
    }

    @Operation
    @ErrorResponse(NoSuchLibrary.self, .notFound)
    @ErrorResponse(NoSuchStore.self, .notFound)
    package func getStore(@Path library: String, @Path key: String) async throws -> Components.Schemas.StoreRecord {
        guard let library = libraries.library(library) else { throw NoSuchLibrary() }
        return try Self.record(try stores.record(key, in: library))
    }

    static func record(_ record: StoreRecord) throws -> Components.Schemas.StoreRecord {
        Components.Schemas.StoreRecord(
            key: record.key,
            state: try Mapping.transcode(record.state),
            made: record.made,
            steps: record.steps.count,
            step: record.step,
            reason: record.reason,
            findings: try record.findings.map { try Mapping.transcode($0) }
        )
    }
}
