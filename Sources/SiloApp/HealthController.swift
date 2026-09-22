// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Wire
import WireMVC

/// An operational endpoint, outside the document on purpose: it is for the machine that runs the
/// silo, not for a client of it.
@Singleton
@Controller("/health")
package struct HealthController {
    @Inject package init() {}

    @Get
    @ResponseStatus(.ok)
    package func health() {}
}
