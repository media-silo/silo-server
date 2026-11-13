// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Encoder
import FileServing
import Foundation
import Logging
import ServiceLifecycle
import SiloKit
import SiloWorker
import Testing

/// silo-node's file server and worker, run as it runs them: one service group, so that a server
/// that stops is seen and a stop reaches both.
struct NodeServicesTests {
    /// A silo with no work, ever.
    actor Idle: JobsAPI {
        func claim(node: String, capabilities: Set<String>) async throws -> Claim? { nil }
        func report(_ job: String, progress: JobProgress) async throws -> JobState { .encoding }
        func complete(_ job: String, output: FileRef, result: EncodeResult) async throws -> Job {
            Job(id: job, recipe: "none")
        }
        func fail(_ job: String, reason: String) async throws -> Job { Job(id: job, recipe: "none") }
    }

    /// A worker that asks for work every few milliseconds, with tools that answer anything.
    static func worker(in work: URL) throws -> Worker {
        let echo = URL(fileURLWithPath: "/bin/echo")
        let configuration = Worker.Configuration(nodeID: "box", workFolder: work, pollInterval: .milliseconds(10)) {
            FileRef(holder: "box", url: $1, secret: "")
        }
        return Worker(
            api: Idle(),
            configuration: configuration,
            ffmpeg: try FFmpeg(executable: echo),
            ffprobe: try FFprobe(executable: echo)
        )
    }

    static let work = FileManager.default.temporaryDirectory.appendingPathComponent("silo-node-services")

    /// A server that cannot serve ends the group, worker and all, with its error, rather than
    /// leaving the worker to make outputs nobody can fetch.
    @Test(.timeLimit(.minutes(1))) func aServerThatFailsEndsTheWorkerToo() async throws {
        let holder = try FileServer(host: "127.0.0.1", port: 0, advertisedHost: "127.0.0.1")
        let holding = Task { try await holder.run() }
        defer { holding.cancel() }
        let taken = try await holder.boundPort

        let server = try FileServer(host: "127.0.0.1", port: taken, advertisedHost: "127.0.0.1")
        let group = ServiceGroup(
            services: [server, try Self.worker(in: Self.work)],
            logger: Logger(label: "silo.tests.node")
        )
        await #expect(throws: (any Error).self, "the port is taken") { try await group.run() }
    }

    /// A graceful shutdown, which silo-node's SIGTERM and SIGINT are, stops the worker and then the
    /// server, and the group ends without an error.
    @Test(.timeLimit(.minutes(1))) func aGracefulShutdownStopsTheWorkerAndTheServer() async throws {
        let server = try FileServer(host: "127.0.0.1", port: 0, advertisedHost: "127.0.0.1")
        let group = ServiceGroup(
            services: [server, try Self.worker(in: Self.work)],
            logger: Logger(label: "silo.tests.node")
        )
        try await withThrowingTaskGroup(of: Void.self) { tasks in
            tasks.addTask { try await group.run() }
            _ = try await server.boundPort
            await group.triggerGracefulShutdown()
            try await tasks.waitForAll()
        }
    }
}
