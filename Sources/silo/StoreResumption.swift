// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import ServiceLifecycle
import SiloApp
import Wire
import WireMVC

/// Every store under way when the silo stopped, made from the step it was making once the silo has
/// started again. `Stores.md`, *A record kept, and a store resumed*.
@Singleton
@BackgroundService
package final class StoreResumption: Service, Sendable {
    private let stores: StoreService

    @Inject
    package init(stores: StoreService) {
        self.stores = stores
    }

    package func run() async throws {
        await stores.resume()
    }
}
