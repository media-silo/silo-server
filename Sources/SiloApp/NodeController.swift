// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import OpenAPIRuntime  // swiftlint:disable:this unused_import
import SiloAPI
import SiloKit
import Wire
import WireMVC
import WireOpenAPI

/// A node's own routes: register, and poll for approval with its secret. Open, since a node has
/// nothing yet; the secret is what a later call has to know.
@Singleton
@OpenAPIController(spec: "SiloAPI")
package struct NodeController {
    private let service: NodeService

    @Inject
    package init(service: NodeService) {
        self.service = service
    }

    @Operation
    @ErrorResponse(WrongSecret.self, .forbidden)
    package func registerNode(@JSONBody body: Components.Schemas.NodeRegistration) async throws -> Components.Schemas.Node {
        let registration: NodeRegistration = try Mapping.transcode(body)
        return try Mapping.transcode(try service.register(registration))
    }

    @Operation
    @ErrorResponse(NoSuchNode.self, .notFound)
    @ErrorResponse(WrongSecret.self, .forbidden)
    package func nodeStatus(@Path id: String, @Header("x-silo-node-secret") secret: String) async throws -> Components.Schemas.NodeStatus {
        try Mapping.transcode(try service.status(id, secret: secret))
    }
}

/// The operator's side of nodes: the list, and the two decisions.
@Singleton
@OpenAPIController(spec: "SiloAPI")
@Middleware(RouteMiddleware.requireOperator)
package struct NodeOperatorController {
    private let service: NodeService

    @Inject
    package init(service: NodeService) {
        self.service = service
    }

    @Operation
    package func listNodes() async throws -> [Components.Schemas.Node] {
        try Mapping.transcode(service.all())
    }

    @Operation
    @ErrorResponse(NoSuchNode.self, .notFound)
    package func approveNode(@Path id: String) async throws -> Components.Schemas.Node {
        try Mapping.transcode(try service.approve(id))
    }

    @Operation
    @ErrorResponse(NoSuchNode.self, .notFound)
    package func revokeNode(@Path id: String) async throws -> Components.Schemas.Node {
        try Mapping.transcode(try service.revoke(id))
    }
}
