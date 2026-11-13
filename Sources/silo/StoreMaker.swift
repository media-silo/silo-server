// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import ServiceLifecycle
import SiloApp
import Wire
import WireMVC

/// The making of stores, run while the silo runs: every store under way when the silo stopped, from
/// the step it was making, and then each store as it is taken. Stopping the silo ends each store once
/// the step it is making is made, and the next start makes the rest. `Stores.md`, *A record kept, and
/// a store resumed*.
@Singleton
@BackgroundService
package final class StoreMaker: Service, Sendable {
    private let stores: StoreService

    @Inject
    package init(stores: StoreService) {
        self.stores = stores
    }

    package func run() async throws {
        await cancelWhenGracefulShutdown { [self] in
            await stores.run()
        }
    }
}
