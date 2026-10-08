// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Wire

/// A change of rules, told to the background check: a ruleset stored or promoted, a binding's rules
/// moved, a library scanned or a file placed. Requests coalesce — the check has one thing to do,
/// whatever asked, which is to bring every placed presentation up to the rules in force.
@Singleton
package final class CheckSignal: Sendable {
    package let requests: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    @Inject
    package init() {
        (requests, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    }

    package func request() {
        continuation.yield()
    }
}
