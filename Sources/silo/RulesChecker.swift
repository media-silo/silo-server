// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import Logging
import ServiceLifecycle
import SiloApp
import Wire
import WireMVC

/// The background check, run while the silo runs: a pass at start, and another whenever a change of
/// rules asks for one, each bringing every placed presentation up to the rules in force. A pass
/// records each check as it finishes, so stopping the silo part way loses only the one in flight,
/// and the next pass picks up what is left. `LayeredRulesets.md`, *The background check*.
@Singleton
@BackgroundService
package final class RulesChecker: Service, Sendable {
    private let service: CheckService
    private let signal: CheckSignal
    private let logger = Logger(label: "silo.checks")

    @Inject
    package init(service: CheckService, signal: CheckSignal) {
        self.service = service
        self.signal = signal
    }

    package func run() async throws {
        await cancelWhenGracefulShutdown { [self] in
            await follow()
        }
    }

    package func follow() async {
        signal.request()
        for await _ in signal.requests {
            if Task.isCancelled { return }
            do {
                try service.pass()
            } catch {
                logger.error("the check stopped: \(error)")
            }
        }
    }
}
