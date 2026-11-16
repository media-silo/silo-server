// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Encoder
import Foundation
import SiloKit
import SiloWorker
import Testing

@testable import SiloApp

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A node whose requests are lost in transport sends them again rather than losing the encode.
@Suite(.enabled(if: FFmpeg.isAvailable && FFprobe.isAvailable, "ffmpeg and ffprobe are needed"))
struct WorkerRetryTests {
    /// The silo, behind a connection that loses what it is told to: a report or a completion that
    /// never reaches it, or a completion that does and whose answer is lost.
    actor Lossy: JobsAPI {
        let silo: any JobsAPI
        var reportsDropped: Int
        var completionsDropped: Int
        var completionAnswersLost: Int
        private(set) var reports = 0
        private(set) var completions = 0
        private(set) var failures: [String] = []

        init(_ silo: any JobsAPI, reportsDropped: Int = 0, completionsDropped: Int = 0, completionAnswersLost: Int = 0)
        {
            self.silo = silo
            self.reportsDropped = reportsDropped
            self.completionsDropped = completionsDropped
            self.completionAnswersLost = completionAnswersLost
        }

        func claim(node: String, capabilities: Set<String>) async throws -> Claim? {
            try await silo.claim(node: node, capabilities: capabilities)
        }

        func report(_ job: String, progress: JobProgress) async throws -> JobState {
            reports += 1
            guard reportsDropped == 0 else {
                reportsDropped -= 1
                throw URLError(.networkConnectionLost)
            }
            return try await silo.report(job, progress: progress)
        }

        func complete(_ job: String, output: FileRef, result: EncodeResult) async throws -> Job {
            completions += 1
            guard completionsDropped == 0 else {
                completionsDropped -= 1
                throw URLError(.cannotConnectToHost)
            }
            let completed = try await silo.complete(job, output: output, result: result)
            guard completionAnswersLost == 0 else {
                completionAnswersLost -= 1
                throw URLError(.networkConnectionLost)
            }
            return completed
        }

        func fail(_ job: String, reason: String) async throws -> Job {
            failures.append(reason)
            return try await silo.fail(job, reason: reason)
        }
    }

    /// A job of the two-second sample, made and waiting to be claimed.
    static func job(_ bench: JobServiceTests.Bench, ffprobe: FFprobe) async throws -> Job {
        let sample = bench.root.appendingPathComponent("sample.mkv")
        try await WorkerTests.sample(sample, with: try FFmpeg())
        let resolved = try bench.resolved(
            input: InputSpec(probe: try await ffprobe.probe(sample)),
            copy: FileRef(holder: "embedded", url: sample, path: sample.path, secret: ""),
            profile: "mobile"
        )
        return try bench.service.make(from: resolved.id).job
    }

    /// An ffmpeg that answers for its encoders as the real one does, and otherwise sleeps for ten
    /// minutes: an encode that runs until it is stopped.
    static func endless(in bench: JobServiceTests.Bench) throws -> FFmpeg {
        let real = try FFmpeg()
        let script = bench.root.appendingPathComponent("ffmpeg")
        try """
        #!/bin/sh
        case " $* " in *" -encoders "*) exec '\(real.executable.path)' "$@" ;; esac
        exec sleep 600
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return try FFmpeg(executable: script)
    }

    static func worker(
        _ bench: JobServiceTests.Bench,
        api: Lossy,
        ffmpeg: FFmpeg,
        reportPatience: Duration = .seconds(60),
        completionPatience: Duration = .seconds(60)
    ) throws -> Worker {
        Worker(
            api: api,
            configuration: Worker.Configuration(
                nodeID: "embedded",
                workFolder: bench.root.appendingPathComponent("work"),
                progressInterval: .milliseconds(10),
                backoff: Backoff(first: .milliseconds(10), cap: .milliseconds(40)),
                reportPatience: reportPatience,
                completionPatience: completionPatience
            ) { _, file in
                FileRef(holder: "embedded", url: file, path: file.path, secret: "")
            },
            ffmpeg: ffmpeg,
            ffprobe: try FFprobe()
        )
    }

    @Test(.timeLimit(.minutes(1))) func aReportOrACompletionLostInTransportIsSentAgain() async throws {
        let bench = try JobServiceTests.Bench()
        defer { bench.remove() }
        let job = try await Self.job(bench, ffprobe: try FFprobe())
        let api = Lossy(bench.service, reportsDropped: .max, completionAnswersLost: 2)
        let worker = try Self.worker(bench, api: api, ffmpeg: try FFmpeg())

        #expect(try await worker.runOnce() == true)
        #expect(await api.reports > 0, "reports were lost while the encode ran")
        #expect(await api.failures.isEmpty, "and the encode ran on")
        #expect(await api.completions == 3, "a completion whose answer was lost is sent again")
        let encoded = try bench.service.job(job.id)
        #expect(encoded.state == .encoded)
        #expect(encoded.attempts.count == 1, "and made once")
    }

    @Test(.timeLimit(.minutes(1))) func reportsLostPastTheLeaseEndTheEncode() async throws {
        let bench = try JobServiceTests.Bench()
        defer { bench.remove() }
        let job = try await Self.job(bench, ffprobe: try FFprobe())
        let api = Lossy(bench.service, reportsDropped: .max)
        let worker = try Self.worker(
            bench,
            api: api,
            ffmpeg: try Self.endless(in: bench),
            reportPatience: .milliseconds(200)
        )

        #expect(try await worker.runOnce() == true, "the encode is ended rather than run for ten minutes")
        #expect(await api.failures.count == 1)
        #expect(try bench.service.job(job.id).state == .failed)
    }

    @Test(.timeLimit(.minutes(1))) func aCompletionNeverAnsweredIsNotTurnedIntoAFail() async throws {
        let bench = try JobServiceTests.Bench()
        defer { bench.remove() }
        let job = try await Self.job(bench, ffprobe: try FFprobe())
        let api = Lossy(bench.service, completionsDropped: .max)
        let worker = try Self.worker(
            bench,
            api: api,
            ffmpeg: try FFmpeg(),
            completionPatience: .milliseconds(200)
        )

        #expect(try await worker.runOnce() == true)
        #expect(await api.completions > 1, "the completion was sent again")
        #expect(await api.failures.isEmpty, "and, given up, not reported failed")
        #expect(try bench.service.job(job.id).state != .failed, "the job is left for the silo to reclaim")
    }
}
