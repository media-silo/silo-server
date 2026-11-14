// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Encoder
import Foundation
import Logging
import ServiceLifecycle
import SiloKit
import Synchronization

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The node's loop: claim a job, reach its segments, encode them as the recipe says, probe the result,
/// check the layout, tell the silo where the output is. The same loop whether the node is a
/// process on another machine or the one the silo runs inside itself; only `JobsAPI` differs.
public actor Worker: Service {
    public struct Configuration: Sendable {
        public var nodeID: String
        public var workFolder: URL
        /// How often to ask for work when there was none.
        public var pollInterval: Duration
        /// How often to report progress, which is also how often the lease is renewed.
        public var progressInterval: Duration
        /// Where a finished file is reachable from: the node's file server, or for the embedded
        /// node a `file://` URL the silo reads directly.
        public var publish: @Sendable (_ job: String, _ file: URL) async throws -> FileRef

        public init(
            nodeID: String,
            workFolder: URL,
            pollInterval: Duration = .seconds(5),
            progressInterval: Duration = .seconds(5),
            publish: @escaping @Sendable (String, URL) async throws -> FileRef
        ) {
            self.nodeID = nodeID
            self.workFolder = workFolder
            self.pollInterval = pollInterval
            self.progressInterval = progressInterval
            self.publish = publish
        }
    }

    private let api: any JobsAPI
    private let configuration: Configuration
    private let ffmpeg: FFmpeg
    private let ffprobe: FFprobe
    private let logger: Logger
    private var capabilities: Set<String>?

    public init(
        api: any JobsAPI,
        configuration: Configuration,
        ffmpeg: FFmpeg,
        ffprobe: FFprobe,
        logger: Logger = Logger(label: "silo.worker")
    ) {
        self.api = api
        self.configuration = configuration
        self.ffmpeg = ffmpeg
        self.ffprobe = ffprobe
        self.logger = logger
    }

    /// The encoders this node's `ffmpeg` has, found once.
    public func capabilities() async throws -> Set<String> {
        if let capabilities { return capabilities }
        let found = try await ffmpeg.encoders()
        capabilities = found
        return found
    }

    /// Runs until cancelled, or until its service group shuts down gracefully. A stop cancels the
    /// job in flight, as it does the silo's embedded node.
    public func run() async {
        await cancelWhenGracefulShutdown { [self] in
            await loop()
        }
    }

    private func loop() async {
        while !Task.isCancelled {
            do {
                if try await runOnce() { continue }
            } catch {
                logger.error("\(error)")
            }
            try? await Task.sleep(for: configuration.pollInterval)
        }
    }

    /// Claims and does one job. Returns whether there was one.
    @discardableResult
    public func runOnce() async throws -> Bool {
        let capabilities = try await capabilities()
        guard let claim = try await api.claim(node: configuration.nodeID, capabilities: capabilities) else {
            return false
        }
        let job = claim.job
        logger.info("claimed \(job.id)")
        do {
            try await perform(claim)
        } catch is CancellationError {
            _ = try? await api.fail(job.id, reason: "cancelled")
        } catch let error as Cancelled {
            logger.info("\(job.id) cancelled: \(error.reason)")
            _ = try? await api.fail(job.id, reason: "cancelled")
        } catch {
            logger.error("\(job.id) failed: \(error)")
            _ = try? await api.fail(job.id, reason: String(describing: error))
        }
        return true
    }

    struct Cancelled: Error {
        var reason: String
    }

    private func perform(_ claim: Claim) async throws {
        let job = claim.job
        guard let stored = claim.recipe, !claim.segments.isEmpty else {
            throw WorkerError.notReady(job.id)
        }
        let recipe = stored.recipe
        let facts = stored.facts
        try FileManager.default.createDirectory(at: configuration.workFolder, withIntermediateDirectories: true)

        let reached = try await reachSources(of: claim)
        let input = try encodeInput(for: claim, reached: reached)

        let output = configuration.workFolder.appendingPathComponent("\(job.id).\(recipe.output.fileExtension)")
        try? FileManager.default.removeItem(at: output)

        do {
            try await encode(job.id, recipe.ffmpegArguments(input: input, output: output), duration: facts.duration)
        } catch  where Task.isCancelled {
            // A stop from outside terminates ffmpeg, which then exits failing. That is a cancel, not
            // a failure, whichever of the encode and the reporter saw it first.
            throw CancellationError()
        }

        let probed = try await ffprobe.probe(output)
        let mismatches = recipe.verify(against: probed, source: facts)
        let size = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? NSNumber)?.int64Value
        let result = EncodeResult(
            sizeBytes: size,
            streams: probed.streams.filter { [.video, .audio, .subtitle].contains($0.kind) }.map {
                "\($0.kind.rawValue) \($0.codec)"
            },
            layoutMatched: mismatches.isEmpty
        )
        guard mismatches.isEmpty else {
            throw WorkerError.layoutMismatch(mismatches.map(\.description))
        }
        let published = try await configuration.publish(job.id, output)
        _ = try await api.complete(job.id, output: published, result: result)
        logger.info("encoded \(job.id) to \(output.lastPathComponent)")
    }

    /// ffmpeg run beside the progress reports, until the first of them ends: the encode finishing,
    /// or the reporter learning of a cancel. Progress doubles as heartbeat, and the state that comes
    /// back is how a cancel arrives. Both are the group's own children, so cancelling the task that
    /// runs this cancels the encode too, which terminates ffmpeg.
    private func encode(_ job: String, _ arguments: [String], duration: Double?) async throws {
        let api = self.api
        let ffmpeg = self.ffmpeg
        let interval = configuration.progressInterval
        let latest = ProgressBox()
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await ffmpeg.run(arguments) { progress in
                    latest.update(
                        JobProgress(
                            fraction: duration.flatMap { total in progress.seconds.map { min(1, $0 / total) } },
                            seconds: progress.seconds,
                            fps: progress.fps,
                            speed: progress.speed
                        )
                    )
                }
            }
            group.addTask {
                // Never ends of itself: once the group is cancelled, the sleep throws.
                while true {
                    try await Task.sleep(for: interval)
                    let state = try await api.report(job, progress: latest.take())
                    if state == .cancelling || state == .cancelled {
                        throw Cancelled(reason: "the silo asked")
                    }
                }
            }
            try await group.next()
            group.cancelAll()
        }
    }

    /// Each segment's source, reached once however many segments it has: opened where it is when
    /// this node holds it, fetched by range otherwise.
    private func reachSources(of claim: Claim) async throws -> [String: URL] {
        let job = claim.job
        var reached: [String: URL] = [:]
        for (position, segment) in claim.segments.enumerated() where reached[segment.source] == nil {
            let copy = segment.copy
            if copy.holder == configuration.nodeID, let path = copy.path {
                reached[segment.source] = URL(fileURLWithPath: path)
            } else if copy.url.isFileURL {
                reached[segment.source] = copy.url
            } else {
                let fetched = configuration.workFolder.appendingPathComponent(
                    "\(job.id).\(position + 1).source.\(copy.url.pathExtension.isEmpty ? "mkv" : copy.url.pathExtension)"
                )
                try await RangeDownloader.download(copy, to: fetched) { [logger] received, total in
                    logger.debug("\(job.id): fetched \(received)\(total.map { " of \($0)" } ?? "")")
                }
                reached[segment.source] = fetched
            }
        }
        return reached
    }

    /// One whole segment is its file; several, or a span of one, are one concat input.
    private func encodeInput(for claim: Claim, reached: [String: URL]) throws -> EncodeInput {
        let job = claim.job
        if claim.segments.count == 1, claim.segments[0].isWhole {
            return .file(reached[claim.segments[0].source]!)
        } else {
            let list = configuration.workFolder.appendingPathComponent("\(job.id).concat")
            let pieces = claim.segments.map {
                ConcatList.Piece(file: reached[$0.source]!, inpoint: $0.start, outpoint: $0.end)
            }
            try ConcatList(pieces).text.write(to: list, atomically: true, encoding: .utf8)
            return .concat(list: list)
        }
    }
}

final class ProgressBox: Sendable {
    private let box = Synchronization.Mutex(JobProgress())
    func update(_ progress: JobProgress) { box.withLock { $0 = progress } }
    func take() -> JobProgress { box.withLock { $0 } }
}

public enum WorkerError: Error, CustomStringConvertible {
    case notReady(String)
    case layoutMismatch([String])
    case download(String)

    public var description: String {
        switch self {
        case .notReady(let job): "job \(job) has no recipe to run"
        case .layoutMismatch(let mismatches):
            "the output's layout is not the recipe's: " + mismatches.joined(separator: "; ")
        case .download(let reason): "fetching a source failed: \(reason)"
        }
    }
}

/// Fetches a file from the node that holds it, by range, resuming from what is already on disk
/// after an interruption.
public enum RangeDownloader {
    public static func download(
        _ file: FileRef,
        to destination: URL,
        progress: @escaping @Sendable (Int64, Int64?) -> Void = { _, _ in }
    ) async throws {
        let existing =
            (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? 0
        if let size = file.sizeBytes, existing == size, size > 0 { return }
        var request = URLRequest(url: file.url)
        request.setValue(file.secret, forHTTPHeaderField: "x-silo-secret")
        if existing > 0 { request.setValue("bytes=\(existing)-", forHTTPHeaderField: "Range") }

        let handle: FileHandle
        if existing > 0, FileManager.default.fileExists(atPath: destination.path) {
            handle = try FileHandle(forWritingTo: destination)
            try handle.seekToEnd()
        } else {
            FileManager.default.createFile(atPath: destination.path, contents: nil)
            handle = try FileHandle(forWritingTo: destination)
        }
        defer { try? handle.close() }

        let delegate = Receiver(handle: handle, received: existing, progress: progress)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                    delegate.start(session.dataTask(with: request), finish: continuation)
                }
            } onCancel: {
                delegate.cancel()
            }
        } catch let error as URLError where error.code == .cancelled && Task.isCancelled {
            // What has arrived stays on disk, for the next attempt to resume from.
            throw CancellationError()
        }
        if let size = file.sizeBytes {
            let final =
                (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value
                ?? -1
            guard final == size else { throw WorkerError.download("got \(final) bytes of \(size)") }
        }
    }

    /// What a `Receiver` has seen of its transfer, and how to end it.
    private struct ReceiverState {
        var received: Int64
        var total: Int64?
        var status = 0
        var task: URLSessionDataTask?
        var finish: CheckedContinuation<Void, any Error>?
        /// Set by the cancellation handler, which may run before the task is started.
        var cancelled = false
    }

    /// The data task's delegate, which writes what arrives to the file and resumes the waiting
    /// task with how the transfer ended. Its state is behind one lock: the session's delegate
    /// queue writes it, and the cancellation handler reaches the data task through it.
    private final class Receiver: NSObject, URLSessionDataDelegate, Sendable {
        private let handle: FileHandle
        private let progress: @Sendable (Int64, Int64?) -> Void
        private let state: Mutex<ReceiverState>

        init(handle: FileHandle, received: Int64, progress: @escaping @Sendable (Int64, Int64?) -> Void) {
            self.handle = handle
            self.progress = progress
            state = Mutex(ReceiverState(received: received))
        }

        /// Starts the task unless the waiting task was cancelled first, which throws
        /// `CancellationError` without starting it.
        func start(_ task: URLSessionDataTask, finish: CheckedContinuation<Void, any Error>) {
            let cancelled = state.withLock { state -> Bool in
                guard !state.cancelled else { return true }
                state.task = task
                state.finish = finish
                return false
            }
            if cancelled {
                finish.resume(throwing: CancellationError())
            } else {
                task.resume()
            }
        }

        /// Cancels the task, which then ends with `URLError.cancelled`; before it starts, keeps it
        /// from starting.
        func cancel() {
            let task = state.withLock { state -> URLSessionDataTask? in
                state.cancelled = true
                return state.task
            }
            task?.cancel()
        }

        func urlSession(
            _ session: URLSession,
            dataTask: URLSessionDataTask,
            didReceive response: URLResponse,
            completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
        ) {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 || status == 206 else {
                state.withLock { $0.status = status }
                completionHandler(.cancel)
                return
            }
            let restart = state.withLock { state -> Bool in
                state.status = status
                // The holder ignored the range: start over rather than append.
                let restart = status == 200 && state.received > 0
                if restart { state.received = 0 }
                state.total = state.received + response.expectedContentLength
                return restart
            }
            if restart { try? handle.truncate(atOffset: 0) }
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            try? handle.write(contentsOf: data)
            let (received, total) = state.withLock { state in
                state.received += Int64(data.count)
                return (state.received, state.total)
            }
            progress(received, total)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
            let (status, finish) = state.withLock { state in
                defer { state.finish = nil }
                return (state.status, state.finish)
            }
            if let error, status == 0 {
                // No answer at all: the transport's error is why.
                finish?.resume(throwing: error)
            } else if status != 200 && status != 206 {
                // A status refused is answered by cancelling the task, which then ends with
                // `URLError.cancelled`: the status, not that, is why it failed.
                finish?.resume(throwing: WorkerError.download("the holder answered \(status)"))
            } else if let error {
                finish?.resume(throwing: error)
            } else {
                finish?.resume()
            }
        }
    }
}
