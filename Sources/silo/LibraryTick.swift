// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Logging
import ServiceLifecycle
import SiloApp
import Wire
import WireMVC

/// The five-minute walk, run while the silo runs: every library walked regardless, which is what
/// notices `silo-ctl place`, a sidecar corrected by hand, another machine writing to a share, and a
/// folder that has come back. Five minutes is a decision, not a setting: a number the operator must
/// tune is a cadence the design has not chosen. `Libraries.md`, *What starts a walk*.
@Singleton
@BackgroundService
package final class LibraryTick: Service, Sendable {
    private let libraries: Libraries
    private let interval: Duration

    @Inject
    package convenience init(libraries: Libraries) {
        self.init(libraries: libraries, interval: .seconds(300))
    }

    /// The timing seam, for tests.
    package init(libraries: Libraries, interval: Duration) {
        self.libraries = libraries
        self.interval = interval
    }

    package func run() async throws {
        await cancelWhenGracefulShutdown { [self] in
            await follow()
        }
    }

    /// The loop, until cancelled. The boot has walked every library already, so the first tick is
    /// one interval in.
    package func follow() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: interval)
            } catch {
                return
            }
            await libraries.walkEvery()
        }
    }
}
