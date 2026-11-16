// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloWorker
import Synchronization
import Testing

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A request lost in transport is sent again, waiting longer each time; an answer is the answer.
struct BackoffTests {
    static let lost = URLError(.networkConnectionLost)
    static let backoff = Backoff(first: .milliseconds(10), cap: .milliseconds(40))

    /// Counts the attempts made, throwing `error` for the first `failing` of them.
    final class Attempts: Sendable {
        let made = Mutex(0)
        let failing: Int
        let error: any Error
        init(failing: Int, error: any Error = BackoffTests.lost) {
            self.failing = failing
            self.error = error
        }
        func attempt() throws -> String {
            let count = made.withLock { made -> Int in
                made += 1
                return made
            }
            if count <= failing { throw error }
            return "answered"
        }
    }

    @Test func aTransportErrorIsSentAgainWaitingLongerEachTime() async throws {
        let attempts = Attempts(failing: 4)
        var waits: [Duration] = []
        let answer = try await Self.backoff.retry(retrying: { _, wait in waits.append(wait) }) {
            try attempts.attempt()
        }
        #expect(answer == "answered")
        #expect(attempts.made.withLock { $0 } == 5)
        let bounds: [(Duration, Duration)] = [(5, 10), (10, 20), (20, 40), (20, 40)].map {
            (.milliseconds($0.0), .milliseconds($0.1))
        }
        #expect(waits.count == 4)
        for (wait, bound) in zip(waits, bounds) {
            #expect(wait >= bound.0 && wait <= bound.1, "each wait is in the upper half of its delay, capped")
        }
    }

    struct Refused: Error {}

    @Test func anAnswerIsNotSentAgain() async throws {
        let refused = Attempts(failing: 1, error: Refused())
        await #expect(throws: Refused.self) { try await Self.backoff.retry { try refused.attempt() } }
        #expect(refused.made.withLock { $0 } == 1, "a refusal is the silo's answer")

        let stopped = Attempts(failing: 1, error: URLError(.cancelled))
        await #expect(throws: URLError.self) { try await Self.backoff.retry { try stopped.attempt() } }
        #expect(stopped.made.withLock { $0 } == 1, "and a request cancelled was stopped on purpose")
    }

    @Test func aRetryThatWouldWaitPastTheDeadlineIsNotMade() async throws {
        let attempts = Attempts(failing: .max)
        let start = ContinuousClock.now
        let thrown = await #expect(throws: URLError.self) {
            try await Self.backoff.retry(until: start + .milliseconds(100)) { try attempts.attempt() }
        }
        #expect(thrown?.code == .networkConnectionLost, "the transport's error is thrown")
        #expect(ContinuousClock.now - start < .seconds(5), "it gives up near the deadline, not after retrying on")
        #expect(attempts.made.withLock { $0 } > 1)
    }

    @Test(.timeLimit(.minutes(1))) func aCancelEndsTheWaiting() async throws {
        let attempts = Attempts(failing: .max)
        let retrying = Task { try await Backoff(first: .seconds(60)).retry { try attempts.attempt() } }
        while attempts.made.withLock({ $0 }) == 0 { try await Task.sleep(for: .milliseconds(5)) }
        retrying.cancel()
        await #expect(throws: CancellationError.self) { try await retrying.value }
    }
}
