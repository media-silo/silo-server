// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import Synchronization
import Testing
@testable import Encoder

struct ProcessRunnerTests {
    static let shell = URL(fileURLWithPath: "/bin/sh")

    @Test func aRunReturnsTheToolsLinesStatusAndErrorTail() async throws {
        let lines = Mutex<[String]>([])
        let outcome = try await ProcessRunner.run(Self.shell, arguments: ["-c", "printf 'one\\ntwo'; printf 'went wrong' >&2; exit 3"]) { line in
            lines.withLock { $0.append(line) }
        }
        #expect(lines.withLock { $0 } == ["one", "two"], "the last line is delivered without a newline after it")
        #expect(outcome.status == 3)
        #expect(outcome.stderrTail == "went wrong")
    }

    /// Many short tools beside longer ones, all at once, as a node's tests and a busy node run them:
    /// every run ends, with all its output, however the others are spawned around it.
    @Test(.timeLimit(.minutes(1))) func manyToolsAtOnceAllFinish() async throws {
        let outcomes = try await withThrowingTaskGroup(of: (lines: [String], status: Int32).self) { group in
            for round in 0..<40 {
                group.addTask {
                    let outcome = try await ProcessRunner.run(Self.shell, arguments: ["-c", "sleep 2"]) { _ in }
                    return ([], outcome.status)
                }
                group.addTask {
                    let lines = Mutex<[String]>([])
                    let outcome = try await ProcessRunner.run(Self.shell, arguments: ["-c", "seq 1 2000; echo run \(round) >&2"]) { line in
                        lines.withLock { $0.append(line) }
                    }
                    return (lines.withLock { $0 }, outcome.status)
                }
            }
            var all: [(lines: [String], status: Int32)] = []
            for try await outcome in group { all.append(outcome) }
            return all
        }
        #expect(outcomes.count == 80)
        #expect(outcomes.allSatisfy { $0.status == 0 })
        let printed = outcomes.filter { !$0.lines.isEmpty }
        #expect(printed.count == 40)
        #expect(printed.allSatisfy { $0.lines == (1...2000).map(String.init) }, "each run's output arrives whole")
    }
}
