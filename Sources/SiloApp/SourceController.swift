// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import OpenAPIRuntime
import SiloAPI
import SiloKit
import SiloStore
import Wire
import WireMVC
import WireOpenAPI

package struct NoSuchSource: Error {}

/// Sources, read: open, as the queue is. A copy is rendered without its secret, which goes only to
/// a node that claims a job needing the file.
@Singleton
@OpenAPIController(spec: "SiloAPI")
package struct SourceController {
    private let store: SourceStore

    @Inject
    package init(store: SourceStore) {
        self.store = store
    }

    @Operation
    package func listSources() async throws -> [Components.Schemas.Source] {
        try store.all().map(Mapping.source)
    }

    @Operation
    @ErrorResponse(NoSuchSource.self, .notFound)
    package func getSource(@Path id: String) async throws -> Components.Schemas.Source {
        guard let source = store.source(id) else { throw NoSuchSource() }
        return try Mapping.source(source)
    }
}

/// Sources, changed by the operator's side: registered by a producer, and their copies recorded as
/// nodes come to hold a file or let it go. Behind the operator's token.
@Singleton
@OpenAPIController(spec: "SiloAPI")
@Middleware(RouteMiddleware.requireOperator)
package struct SourceOperatorController {
    private let store: SourceStore

    @Inject
    package init(store: SourceStore) {
        self.store = store
    }

    /// Raw, because which success it answers — 201 for a new source, 200 for one the natural key
    /// already names — is decided by the registration, not by the handler's signature.
    @RawOperation
    package func registerSource(_ input: Operations.registerSource.Input) async throws -> Operations.registerSource.Output {
        let body = switch input.body {
        case .json(let body): body
        }
        let document = try JSONEncoder().encode(body.input)
        let spec: InputSpec
        do throws(InputSpecError) {
            spec = try InputSpec.read(from: document)
        } catch {
            return .badRequest(.init(body: .json(Components.Schemas.Problem(detail: error.description))))
        }
        let key: NaturalKey? = try body.key.map { try Mapping.transcode($0) }
        let copy: FileRef? = try body.copy.map { try Mapping.transcode($0) }
        do {
            let (source, created) = try store.register(spec, key: key, copy: copy)
            let rendered = try Mapping.source(source)
            return created ? .created(.init(body: .json(rendered))) : .ok(.init(body: .json(rendered)))
        } catch let error as SourceStoreError {
            return .conflict(.init(body: .json(Components.Schemas.Problem(detail: error.description))))
        }
    }

    @Operation
    @ErrorResponse(NoSuchSource.self, .notFound)
    package func addSourceCopy(@Path id: String, @JSONBody body: Components.Schemas.FileRef) async throws -> Components.Schemas.Source {
        let copy: FileRef = try Mapping.transcode(body)
        guard let source = try store.update(id, { $0.hold(copy) }) else { throw NoSuchSource() }
        return try Mapping.source(source)
    }

    @Operation
    @ErrorResponse(NoSuchSource.self, .notFound)
    package func removeSourceCopy(@Path id: String, @Path node: String) async throws -> Components.Schemas.Source {
        guard let source = try store.update(id, { $0.copies.removeAll { $0.holder == node } }) else { throw NoSuchSource() }
        return try Mapping.source(source)
    }
}

extension Mapping {
    /// A source as the API renders it: its copies without their secrets.
    static func source(_ source: Source) throws -> Components.Schemas.Source {
        try transcode(source)
    }
}
