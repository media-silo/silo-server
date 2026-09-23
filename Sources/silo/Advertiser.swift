// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import Logging
import ServiceLifecycle
import SiloApp
import SiloDiscovery
import SiloStore
import Wire
import WireMVC

/// Says where the silo is, through Bonjour, for as long as it runs. Convenience, not mechanism:
/// a node or the tool given a URL never needs it, and a machine without the tool is told so once.
/// The advertisement names the server's identity and carries its id always, and `b=1` while the
/// silo is in bootstrap, so what browses can tell a server waiting on its person from one that
/// has one.
@Singleton
@BackgroundService
package final class Advertiser: Service, Sendable {
    private let config: SiloConfig
    private let server: ServerService
    private let logger = Logger(label: "silo.bonjour")

    @Inject
    package init(config: SiloConfig, server: ServerService) {
        self.config = config
        self.server = server
    }

    package func run() async throws {
        guard config.advertise else {
            try await gracefulShutdown()
            return
        }
        guard Discovery.isAvailable else {
            logger.warning("not advertising: \(Discovery.unavailable)")
            try await gracefulShutdown()
            return
        }
        var txt = ["v": "1", "id": server.identity.id]
        if server.isInBootstrap { txt["b"] = "1" }
        let advertisement: Discovery.Advertisement
        do {
            advertisement = try Discovery.advertise(name: server.name, port: config.port, txt: txt)
        } catch {
            logger.warning("not advertising: \(error)")
            try await gracefulShutdown()
            return
        }
        logger.info("advertising \"\(server.name)\" on port \(config.port)")
        await withGracefulShutdownHandler {
            try? await gracefulShutdown()
        } onGracefulShutdown: {
            advertisement.stop()
        }
        advertisement.stop()
    }
}
