// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import Logging
import ServiceLifecycle
import SiloApp
import SiloDiscovery
import Wire
import WireMVC

/// Says where the silo is, through Bonjour, for as long as it runs. Convenience, not mechanism:
/// a node or the tool given a URL never needs it, and a machine without the tool is told so once.
@Singleton
@BackgroundService
package final class Advertiser: Service, Sendable {
    private let config: SiloConfig
    private let logger = Logger(label: "silo.bonjour")

    @Inject
    package init(config: SiloConfig) {
        self.config = config
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
        let advertisement: Discovery.Advertisement
        do {
            advertisement = try Discovery.advertise(name: config.name, port: config.port, txt: ["v": "1"])
        } catch {
            logger.warning("not advertising: \(error)")
            try await gracefulShutdown()
            return
        }
        logger.info("advertising \"\(config.name)\" on port \(config.port)")
        await withGracefulShutdownHandler {
            try? await gracefulShutdown()
        } onGracefulShutdown: {
            advertisement.stop()
        }
        advertisement.stop()
    }
}
