// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloAPI
import SiloStore
import Wire
import WireMVC
import WireOpenAPI

/// The server's own routes: what it is called and whether it still waits on a person, and — while
/// it does — the setup pair that ends the wait. Open, since everything they answer is already in
/// the Bonjour advertisement and none of it is a credential; the staged passkey travels one way
/// only, inward, and never leaves the server's memory unconfirmed.
@Singleton
@OpenAPIController(spec: "SiloAPI")
package struct ServerController {
    private let service: ServerService

    @Inject
    package init(service: ServerService) {
        self.service = service
    }

    @Operation
    package func getServer() async throws -> Components.Schemas.ServerInfo {
        Components.Schemas.ServerInfo(id: service.identity.id, name: service.name, bootstrap: service.isInBootstrap)
    }

    /// The verify-access route: its whole job is the gate. Where /server is open and says nothing
    /// about a bearer, and /nodes would entangle the operator's credential with the node
    /// subsystem's health, this answers the operator's token alone — 401 names the token, and a
    /// 200 answers the server as /server would have.
    @Operation
    @Middleware(RouteMiddleware.requireOperator)
    package func getOperator() async throws -> Components.Schemas.ServerInfo {
        Components.Schemas.ServerInfo(id: service.identity.id, name: service.name, bootstrap: service.isInBootstrap)
    }

    @Operation
    @ErrorResponse(EmptyPasskey.self, .badRequest)
    @ErrorResponse(StagePending.self, .conflict, { Components.Schemas.SetupConflict(confirmBy: $0.confirmBy) })
    @ErrorResponse(SetupGone.self, .gone)
    package func stageSetup(@JSONBody body: Components.Schemas.SetupRequest) async throws -> Components.Schemas.SetupStage {
        let staged = try service.stageSetup(passkey: body.passkey, name: body.name)
        return Components.Schemas.SetupStage(id: service.identity.id, name: staged.name, confirmBy: staged.confirmBy)
    }

    /// Runs only once the route's middleware has spent the staged passkey: the document cannot
    /// declare an `Authorization` header parameter — OpenAPI reserves it — so it documents the
    /// bearer with `security`, and the middleware reads the header and confirms. What is left
    /// here is the answer once bootstrap has ended.
    @Operation
    @Middleware(RouteMiddleware.confirmSetup)
    package func confirmSetup() async throws -> Components.Schemas.ServerInfo {
        Components.Schemas.ServerInfo(id: service.identity.id, name: service.name, bootstrap: service.isInBootstrap)
    }
}
