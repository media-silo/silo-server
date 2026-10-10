// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import Synchronization
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

/// Where the tools are. An environment variable first, so a node can point at a build of its own;
/// then `PATH`; then the places package managers put them, for a launchd or GUI process whose
/// `PATH` is the system's.
public enum Tools {
    public static func locate(_ name: String, environmentKey: String) -> URL? {
        let environment = ProcessInfo.processInfo.environment
        if let path = environment[environmentKey], FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        let searchPath = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let fallbacks = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        for folder in searchPath + fallbacks {
            let candidate = (folder as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }
}

public enum ToolError: Error, CustomStringConvertible {
    case notFound(String)
    case failed(tool: String, status: Int32, stderr: String)
    case unreadableOutput(tool: String, reason: String)

    public var description: String {
        switch self {
        case .notFound(let name):
            "\(name) was not found; set \(name.uppercased())_PATH or put it on PATH"
        case .failed(let tool, let status, let stderr):
            "\(tool) exited with status \(status)\(stderr.isEmpty ? "" : ":\n\(stderr)")"
        case .unreadableOutput(let tool, let reason):
            "\(tool) produced output this reader could not parse: \(reason)"
        }
    }
}

/// Runs a tool, streaming its standard output a line at a time and keeping the tail of its
/// standard error for the failure message. Cancelling the task terminates the process.
package enum ProcessRunner {
    package struct Outcome: Sendable {
        package var status: Int32
        package var stderrTail: String
    }

    package static func run(
        _ executable: URL,
        arguments: [String],
        onLine: @escaping @Sendable (String) -> Void
    ) async throws -> Outcome {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        let state = Mutex(State())
        let lines = LineSplitter()

        process.terminationHandler = { process in
            state.withLock { $0.status = process.terminationStatus }
            State.resumeIfDone(state)
        }
        let exited: @Sendable () -> Bool = { state.withLock { $0.status != nil } }

        let box = ProcessBox(process)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Outcome, any Error>) in
                state.withLock { $0.continuation = continuation }
                do {
                    try process.run()
                    // Read only once it runs: `run()` closes this process's copies of the write ends.
                    PipeReader.start(stdout.fileHandleForReading, exited: exited) { data in
                        for line in lines.append(data) { onLine(line) }
                    } onEnd: {
                        for line in lines.finish() { onLine(line) }
                        state.withLock { $0.stdoutClosed = true }
                        State.resumeIfDone(state)
                    }
                    PipeReader.start(stderr.fileHandleForReading, exited: exited) { data in
                        state.withLock { $0.appendStderr(data) }
                    } onEnd: {
                        state.withLock { $0.stderrClosed = true }
                        State.resumeIfDone(state)
                    }
                } catch {
                    let taken = state.withLock { state -> CheckedContinuation<Outcome, any Error>? in
                        defer { state.continuation = nil }
                        return state.continuation
                    }
                    taken?.resume(throwing: error)
                }
            }
        } onCancel: {
            box.terminate()
        }
    }

    private struct State {
        var status: Int32?
        var stdoutClosed = false
        var stderrClosed = false
        var stderrTail = Data()
        var continuation: CheckedContinuation<Outcome, any Error>?

        mutating func appendStderr(_ data: Data) {
            stderrTail.append(data)
            let limit = 8 * 1024
            if stderrTail.count > limit {
                stderrTail = stderrTail.suffix(limit)
            }
        }

        static func resumeIfDone(_ state: borrowing Mutex<State>) {
            let outcome: (CheckedContinuation<Outcome, any Error>, Outcome)? = state.withLock { state in
                guard let status = state.status, state.stdoutClosed, state.stderrClosed, let continuation = state.continuation else {
                    return nil
                }
                state.continuation = nil
                let tail = String(decoding: state.stderrTail, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                return (continuation, Outcome(status: status, stderrTail: tail))
            }
            if let (continuation, result) = outcome {
                continuation.resume(returning: result)
            }
        }
    }

    /// `Process` is not Sendable; the cancellation handler only ever asks it to terminate.
    private struct ProcessBox: @unchecked Sendable {
        let process: Process
        init(_ process: Process) { self.process = process }
        func terminate() {
            if process.isRunning { process.terminate() }
        }
    }
}

/// Reads one pipe on a thread of its own until it ends: at end-of-file, or once the tool has exited
/// and the pipe has stayed empty for a further poll, so a write end held open anywhere but the tool
/// cannot keep a run waiting. Not `readabilityHandler`, which on Linux can lose the end-of-file when
/// several tools run at once: every tool exits and its pipe holds nothing more, but the handler is
/// never called with the end, and the run waits forever.
enum PipeReader {
    static func start(
        _ handle: FileHandle,
        exited: @escaping @Sendable () -> Bool,
        onData: @escaping @Sendable (Data) -> Void,
        onEnd: @escaping @Sendable () -> Void
    ) {
        let reading = ReadingHandle(handle)
        Thread.detachNewThread {
            let descriptor = reading.handle.fileDescriptor
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            var lastLook = false
            while true {
                var poller = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
                let ready = poll(&poller, 1, 100)
                if ready > 0 {
                    let count = buffer.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
                    if count > 0 {
                        onData(Data(buffer[0..<count]))
                        continue
                    }
                    if count < 0 && (errno == EINTR || errno == EAGAIN) { continue }
                    break
                }
                if ready < 0 && errno != EINTR { break }
                // Empty for a whole poll: if the tool had already exited before it, everything it
                // wrote has been read.
                if lastLook { break }
                lastLook = exited()
            }
            onEnd()
        }
    }

    /// `FileHandle` is not Sendable; the reading thread is the only one that touches it, and holding
    /// it keeps its descriptor open until the thread is done.
    private struct ReadingHandle: @unchecked Sendable {
        let handle: FileHandle
        init(_ handle: FileHandle) { self.handle = handle }
    }
}

/// Splits a byte stream into lines, holding the partial last one between calls. `ffmpeg` writes
/// progress with `\n`; a carriage return, which some builds use for status lines, ends a line too.
package final class LineSplitter: Sendable {
    private let buffer = Mutex(Data())

    func append(_ data: Data) -> [String] {
        buffer.withLock { buffer in
            buffer.append(data)
            var lines: [String] = []
            while let end = buffer.firstIndex(where: { $0 == UInt8(ascii: "\n") || $0 == UInt8(ascii: "\r") }) {
                let line = buffer[buffer.startIndex..<end]
                lines.append(String(decoding: line, as: UTF8.self))
                buffer.removeSubrange(buffer.startIndex...end)
            }
            return lines
        }
    }

    func finish() -> [String] {
        buffer.withLock { buffer in
            defer { buffer.removeAll() }
            return buffer.isEmpty ? [] : [String(decoding: buffer, as: UTF8.self)]
        }
    }
}
