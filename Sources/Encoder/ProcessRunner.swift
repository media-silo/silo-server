// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import Synchronization

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

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                for line in lines.finish() { onLine(line) }
                state.withLock { $0.stdoutClosed = true }
                State.resumeIfDone(state)
            } else {
                for line in lines.append(data) { onLine(line) }
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                state.withLock { $0.stderrClosed = true }
                State.resumeIfDone(state)
            } else {
                state.withLock { $0.appendStderr(data) }
            }
        }
        process.terminationHandler = { process in
            state.withLock { $0.status = process.terminationStatus }
            State.resumeIfDone(state)
        }

        let box = ProcessBox(process)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Outcome, any Error>) in
                state.withLock { $0.continuation = continuation }
                do {
                    try process.run()
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
