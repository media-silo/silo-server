// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Encoder
import Foundation
import Logging
import ServiceLifecycle
import SiloApp
import SiloKit
import SiloStore
import SiloWorker
import Synchronization
import Wire
import WireMVC

/// The node the silo runs inside itself, while the embedded node setting is on: the same loop a
/// node on another machine runs, talking to the job service directly rather than over HTTP, so that
/// one machine is the whole pipeline and there is one code path to test. Its outputs are files on
/// the silo's own filesystem, which placement moves rather than fetches.
///
/// It follows the setting while the silo runs. The setting is read between jobs, so turning it on
/// starts claiming within one poll, and turning it off stops claiming while the job in flight runs
/// to completion — a setting change is not a reason to throw away an encode.
@Singleton
@BackgroundService
package final class EmbeddedNode: Service, Sendable {
    private let config: SiloConfig
    private let jobs: JobService
    private let settings: SettingsStore
    private let pollInterval: Duration
    private let progressInterval: Duration
    private let logger = Logger(label: "silo.node")
    /// The worker, made the first time the setting is on and the tools are there; `nil` until then.
    private let worker = Mutex<Worker?>(nil)

    @Inject
    package convenience init(config: SiloConfig, jobs: JobService, settings: SettingsStore) {
        self.init(config: config, jobs: jobs, settings: settings, pollInterval: .seconds(5), progressInterval: .seconds(5))
    }

    /// The timing seams, for tests.
    package init(config: SiloConfig, jobs: JobService, settings: SettingsStore, pollInterval: Duration, progressInterval: Duration) {
        self.config = config
        self.jobs = jobs
        self.settings = settings
        self.pollInterval = pollInterval
        self.progressInterval = progressInterval
    }

    package func run() async throws {
        // Cancelled at shutdown like any task; an encode in flight is cancelled with it.
        await cancelWhenGracefulShutdown { [self] in
            await follow()
        }
    }

    /// The loop, until cancelled: claim and encode while the setting is on, idle while it is off.
    package func follow() async {
        var running = false
        var toolsMissingLogged = false
        while !Task.isCancelled {
            guard settings.current.embeddedNode else {
                if running {
                    logger.info("embedded node stopped: the setting is off")
                    running = false
                }
                try? await Task.sleep(for: pollInterval)
                continue
            }
            guard let worker = makeWorker(logMissingTools: !toolsMissingLogged) else {
                toolsMissingLogged = true
                try? await Task.sleep(for: pollInterval)
                continue
            }
            if !running {
                logger.info("embedded node running; work in \(config.stateDirectory.appendingPathComponent("work").path)")
                running = true
            }
            do {
                if try await worker.runOnce() { continue }
            } catch {
                logger.error("\(error)")
            }
            try? await Task.sleep(for: pollInterval)
        }
    }

    /// The worker, made once. When the encode tools cannot be started the node logs the lack —
    /// once, not at every poll — and idles rather than stopping the silo.
    private func makeWorker(logMissingTools: Bool) -> Worker? {
        if let made = worker.withLock({ $0 }) { return made }
        let ffmpeg: FFmpeg
        let ffprobe: FFprobe
        do {
            ffmpeg = try FFmpeg()
            ffprobe = try FFprobe()
        } catch {
            if logMissingTools { logger.error("the embedded node cannot run: \(error)") }
            return nil
        }
        let made = Worker(
            api: jobs,
            configuration: Worker.Configuration(
                nodeID: "embedded",
                workFolder: config.stateDirectory.appendingPathComponent("work", isDirectory: true),
                pollInterval: pollInterval,
                progressInterval: progressInterval
            ) { _, file in
                FileRef(holder: "embedded", url: file, path: file.path, secret: "")
            },
            ffmpeg: ffmpeg, ffprobe: ffprobe, logger: logger
        )
        worker.withLock { $0 = made }
        return made
    }
}
