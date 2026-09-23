// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Encoder
import Foundation
import Logging
import ServiceLifecycle
import SiloApp
import SiloKit
import SiloWorker
import Wire
import WireMVC

/// The node the silo runs inside itself, when configured to: the same loop a node on another
/// machine runs, talking to the job service directly rather than over HTTP, so that one machine
/// is the whole pipeline and there is one code path to test. Its outputs are files on the silo's
/// own filesystem, which placement moves rather than fetches.
@Singleton
@BackgroundService
package final class EmbeddedNode: Service, Sendable {
    private let config: SiloConfig
    private let jobs: JobService
    private let logger = Logger(label: "silo.node")

    @Inject
    package init(config: SiloConfig, jobs: JobService) {
        self.config = config
        self.jobs = jobs
    }

    package func run() async throws {
        guard config.embeddedNode else {
            // Nothing to do, but the service must stay up rather than end the group.
            try await gracefulShutdown()
            return
        }
        let ffmpeg: FFmpeg
        let ffprobe: FFprobe
        do {
            ffmpeg = try FFmpeg()
            ffprobe = try FFprobe()
        } catch {
            logger.error("the embedded node cannot run: \(error)")
            try await gracefulShutdown()
            return
        }
        let work = config.stateDirectory.appendingPathComponent("work", isDirectory: true)
        let worker = Worker(
            api: jobs,
            configuration: Worker.Configuration(nodeID: "embedded", workFolder: work) { _, file in
                FileRef(holder: "embedded", url: file, path: file.path, secret: "")
            },
            ffmpeg: ffmpeg, ffprobe: ffprobe, logger: logger
        )
        logger.info("embedded node running; work in \(work.path)")
        await withGracefulShutdownHandler {
            await worker.run()
        } onGracefulShutdown: {
            // The loop checks for cancellation between jobs; an encode in flight is cancelled by
            // the task.
        }
    }
}
