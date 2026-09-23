// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloAPI
import SiloStore
import Wire
import WireOpenAPI

/// The server's own route: what it is called and whether it still waits on a person. Open, since
/// everything it answers is already in the Bonjour advertisement and none of it is a credential.
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
}
