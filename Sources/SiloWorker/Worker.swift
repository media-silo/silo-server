// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Encoder
import Foundation
import Logging
import SiloKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The node's loop: claim a job, get its source, encode it as the recipe says, probe the result,
/// check the layout, tell the silo where the output is. The same loop whether the node is a
/// process on another machine or the one the silo runs inside itself; only `JobsAPI` differs.
public actor Worker {
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

        public init(nodeID: String, workFolder: URL, pollInterval: Duration = .seconds(5), progressInterval: Duration = .seconds(5), publish: @escaping @Sendable (String, URL) async throws -> FileRef) {
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

    public init(api: any JobsAPI, configuration: Configuration, ffmpeg: FFmpeg, ffprobe: FFprobe, logger: Logger = Logger(label: "silo.worker")) {
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

    /// Runs until cancelled.
    public func run() async {
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
        guard let job = try await api.claim(node: configuration.nodeID, capabilities: capabilities) else { return false }
        logger.info("claimed \(job.id)")
        do {
            try await perform(job)
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

    private func perform(_ job: Job) async throws {
        guard let recipe = job.recipe, let facts = job.facts else {
            throw WorkerError.notReady(job.id)
        }
        try FileManager.default.createDirectory(at: configuration.workFolder, withIntermediateDirectories: true)

        // The source: opened where it is when this node holds it, fetched by range otherwise.
        let source: URL
        if job.source.holder == configuration.nodeID, let path = job.source.path {
            source = URL(fileURLWithPath: path)
        } else if job.source.url.isFileURL {
            source = job.source.url
        } else {
            source = configuration.workFolder.appendingPathComponent("\(job.id).source.\(job.source.url.pathExtension.isEmpty ? "mkv" : job.source.url.pathExtension)")
            try await RangeDownloader.download(job.source, to: source) { [logger] received, total in
                logger.debug("\(job.id): fetched \(received)\(total.map { " of \($0)" } ?? "")")
            }
        }

        let output = configuration.workFolder.appendingPathComponent("\(job.id).\(recipe.output.fileExtension)")
        try? FileManager.default.removeItem(at: output)

        // Progress doubles as heartbeat, and the state that comes back is how a cancel arrives.
        let duration = facts.duration
        let api = self.api
        let interval = configuration.progressInterval
        let latest = ProgressBox()
        let reporter = Task {
            while !Task.isCancelled {
                try await Task.sleep(for: interval)
                let state = try await api.report(job.id, progress: latest.take())
                if state == .cancelling || state == .cancelled {
                    throw Cancelled(reason: "the silo asked")
                }
            }
        }
        defer { reporter.cancel() }

        let encode = Task { [ffmpeg] in
            try await ffmpeg.run(recipe.ffmpegArguments(input: source, output: output)) { progress in
                latest.update(JobProgress(
                    fraction: duration.flatMap { total in progress.seconds.map { min(1, $0 / total) } },
                    seconds: progress.seconds, fps: progress.fps, speed: progress.speed
                ))
            }
        }
        // Whichever finishes first: the encode, or the reporter learning of a cancel.
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await encode.value }
            group.addTask { try await reporter.value }
            defer { encode.cancel(); reporter.cancel() }
            try await group.next()
            group.cancelAll()
        }

        let probed = try await ffprobe.probe(output)
        let mismatches = recipe.verify(against: probed, source: facts)
        let size = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? NSNumber)?.int64Value
        let result = EncodeResult(
            sizeBytes: size,
            streams: probed.streams.filter { [.video, .audio, .subtitle].contains($0.kind) }.map { "\($0.kind.rawValue) \($0.codec)" },
            layoutMatched: mismatches.isEmpty
        )
        guard mismatches.isEmpty else {
            throw WorkerError.layoutMismatch(mismatches.map(\.description))
        }
        let published = try await configuration.publish(job.id, output)
        _ = try await api.complete(job.id, output: published, result: result)
        logger.info("encoded \(job.id) to \(output.lastPathComponent)")
    }
}

final class ProgressBox: Sendable {
    private let box = Synchronization.Mutex(JobProgress())
    func update(_ progress: JobProgress) { box.withLock { $0 = progress } }
    func take() -> JobProgress { box.withLock { $0 } }
}

import Synchronization

public enum WorkerError: Error, CustomStringConvertible {
    case notReady(String)
    case layoutMismatch([String])
    case download(String)

    public var description: String {
        switch self {
        case .notReady(let job): "job \(job) has no recipe to run"
        case .layoutMismatch(let mismatches): "the output's layout is not the recipe's: " + mismatches.joined(separator: "; ")
        case .download(let reason): "fetching the source failed: \(reason)"
        }
    }
}

/// Fetches a file from the node that holds it, by range, resuming from what is already on disk
/// after an interruption.
public enum RangeDownloader {
    public static func download(_ file: FileRef, to destination: URL, progress: @escaping @Sendable (Int64, Int64?) -> Void = { _, _ in }) async throws {
        let existing = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? 0
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
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            delegate.finish = { continuation.resume(with: $0) }
            session.dataTask(with: request).resume()
        }
        if let size = file.sizeBytes {
            let final = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? -1
            guard final == size else { throw WorkerError.download("got \(final) bytes of \(size)") }
        }
    }

    private final class Receiver: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        let handle: FileHandle
        var received: Int64
        var total: Int64?
        let progress: @Sendable (Int64, Int64?) -> Void
        var finish: ((Result<Void, any Error>) -> Void)?
        var status = 0

        init(handle: FileHandle, received: Int64, progress: @escaping @Sendable (Int64, Int64?) -> Void) {
            self.handle = handle
            self.received = received
            self.progress = progress
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 || status == 206 else {
                completionHandler(.cancel)
                return
            }
            if status == 200, received > 0 {
                // The holder ignored the range: start over rather than append.
                try? handle.truncate(atOffset: 0)
                received = 0
            }
            total = received + response.expectedContentLength
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            try? handle.write(contentsOf: data)
            received += Int64(data.count)
            progress(received, total)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
            let outcome: Result<Void, any Error>
            if let error {
                outcome = .failure(error)
            } else if status != 200 && status != 206 {
                outcome = .failure(WorkerError.download("the holder answered \(status)"))
            } else {
                outcome = .success(())
            }
            finish?(outcome)
            finish = nil
        }
    }
}
