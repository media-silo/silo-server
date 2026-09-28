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

/// Says where the silo is, through Bonjour, while the advertising setting is on. Convenience, not
/// mechanism: a node or the tool given a URL never needs it, and a machine without the tool is told
/// so once. The advertisement names the server and carries its id always, and `b=1` while the silo
/// is in bootstrap, so what browses can tell a server waiting on its person from one that has one.
///
/// It follows the silo while it runs: what it should say — whether to advertise at all, under which
/// name, and whether the silo is in bootstrap — is read every couple of seconds, and a change drops
/// the advertisement and starts the one that says it. So turning the setting off or on, renaming the
/// silo, and a confirmed setup ending bootstrap all reach the network without a restart.
@Singleton
@BackgroundService
package final class Advertiser: Service, Sendable {
    private let config: SiloConfig
    private let server: ServerService
    private let settings: SettingsStore
    private let interval: Duration
    private let logger = Logger(label: "silo.bonjour")

    @Inject
    package convenience init(config: SiloConfig, server: ServerService, settings: SettingsStore) {
        self.init(config: config, server: server, settings: settings, interval: .seconds(2))
    }

    /// The timing seam, for tests.
    package init(config: SiloConfig, server: ServerService, settings: SettingsStore, interval: Duration) {
        self.config = config
        self.server = server
        self.settings = settings
        self.interval = interval
    }

    /// What the advertisement should say right now, or `nil` when there should be none.
    package struct Announcement: Hashable, Sendable {
        package var name: String
        package var txt: [String: String]
    }

    package var announcement: Announcement? {
        guard settings.current.advertise else { return nil }
        var txt = ["v": "1", "id": server.identity.id]
        if server.isInBootstrap { txt["b"] = "1" }
        return Announcement(name: server.name, txt: txt)
    }

    package func run() async throws {
        await cancelWhenGracefulShutdown { [self] in
            await follow()
        }
    }

    /// The loop, until cancelled; the advertisement it holds is dropped when it ends.
    package func follow() async {
        var current: (announcement: Announcement, advertisement: Discovery.Advertisement)?
        var said: Announcement?
        var unavailableLogged = false
        defer { current?.advertisement.stop() }
        while !Task.isCancelled {
            let wanted = announcement
            if wanted != said {
                current?.advertisement.stop()
                current = nil
                said = wanted
                if let wanted {
                    if !Discovery.isAvailable {
                        if !unavailableLogged { logger.warning("not advertising: \(Discovery.unavailable)") }
                        unavailableLogged = true
                    } else {
                        do {
                            current = (wanted, try Discovery.advertise(name: wanted.name, port: config.port, txt: wanted.txt))
                            logger.info("advertising \"\(wanted.name)\" on port \(config.port)")
                        } catch {
                            logger.warning("not advertising: \(error)")
                        }
                    }
                } else {
                    logger.info("not advertising: the setting is off")
                }
            }
            try? await Task.sleep(for: interval)
        }
    }
}
