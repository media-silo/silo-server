// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation

/// How a node sends a request again when it is lost in transport: after a wait of `first`, doubling
/// each time to at most `cap`, each wait drawn at random from its upper half so that nodes cut off
/// together do not come back together. Only a transport error is sent again — the silo unreachable,
/// or the connection lost before its answer — since the silo answers a request sent again as it
/// answered the first; an answer, a refusal among them, is the answer.
public struct Backoff: Hashable, Sendable {
    public var first: Duration
    public var cap: Duration

    public init(first: Duration = .seconds(1), cap: Duration = .seconds(30)) {
        self.first = first
        self.cap = cap
    }

    /// Whether the error is the transport's rather than the silo's answer. A cancelled request is
    /// not: it was stopped on purpose.
    public static func isTransport(_ error: any Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return error.code != .cancelled
    }

    /// Runs `attempt` until it is answered. A transport error is retried until `deadline`, or
    /// without end when there is none, and is thrown once a retry would wait past it; any other
    /// error is thrown at once. `retrying` is told of each retry before its wait.
    public func retry<T>(
        isolation: isolated (any Actor)? = #isolation,
        until deadline: ContinuousClock.Instant? = nil,
        retrying: (_ error: any Error, _ wait: Duration) -> Void = { _, _ in },
        _ attempt: () async throws -> T
    ) async throws -> T {
        var delay = first
        while true {
            do {
                return try await attempt()
            } catch  where Self.isTransport(error) {
                let wait = delay / 2 + (delay / 2) * Double.random(in: 0...1)
                if let deadline, ContinuousClock.now + wait > deadline { throw error }
                retrying(error, wait)
                try await Task.sleep(for: wait)
                delay = min(delay * 2, cap)
            }
        }
    }
}
