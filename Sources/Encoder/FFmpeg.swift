// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloKit
import Synchronization

/// `ffmpeg`, as a process: given an argument list, runs it, reports progress, and either returns or
/// throws with the tail of what `ffmpeg` said. Cancelling the task kills the encode.
public struct FFmpeg: Sendable {
    public let executable: URL

    public init(executable: URL? = nil) throws(ToolError) {
        guard let executable = executable ?? Tools.locate("ffmpeg", environmentKey: "FFMPEG_PATH") else {
            throw ToolError.notFound("ffmpeg")
        }
        self.executable = executable
    }

    public static var isAvailable: Bool {
        Tools.locate("ffmpeg", environmentKey: "FFMPEG_PATH") != nil
    }

    public func run(_ arguments: [String], progress: @escaping @Sendable (EncodeProgress) -> Void = { _ in }) async throws {
        let parser = ProgressParser()
        let outcome = try await ProcessRunner.run(executable, arguments: arguments) { line in
            if let report = parser.consume(line) { progress(report) }
        }
        guard outcome.status == 0 else {
            throw ToolError.failed(tool: "ffmpeg", status: outcome.status, stderr: outcome.stderrTail)
        }
    }

    /// The encoders this `ffmpeg` has, by name: what a node reports as its capabilities.
    public func encoders() async throws -> Set<String> {
        let collected = OutputCollector()
        let outcome = try await ProcessRunner.run(executable, arguments: ["-hide_banner", "-encoders"]) { collected.append($0) }
        guard outcome.status == 0 else {
            throw ToolError.failed(tool: "ffmpeg", status: outcome.status, stderr: outcome.stderrTail)
        }
        // Lines after the header look like " V....D libx264              libx264 H.264 / AVC ...".
        var names: Set<String> = []
        var pastHeader = false
        for line in collected.text.split(separator: "\n") {
            if line.hasPrefix(" ------") { pastHeader = true; continue }
            guard pastHeader else { continue }
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            if fields.count >= 2 { names.insert(String(fields[1])) }
        }
        return names
    }
}

/// What `ffmpeg -progress` reports at each step.
public struct EncodeProgress: Hashable, Sendable {
    public var frame: Int?
    public var fps: Double?
    /// Output time so far, in seconds.
    public var seconds: Double?
    /// Encode speed as a multiple of real time.
    public var speed: Double?
    public var finished: Bool

    public init(frame: Int? = nil, fps: Double? = nil, seconds: Double? = nil, speed: Double? = nil, finished: Bool = false) {
        self.frame = frame
        self.fps = fps
        self.seconds = seconds
        self.speed = speed
        self.finished = finished
    }
}

/// `-progress pipe:1` writes blocks of `key=value` lines ending in `progress=continue` or
/// `progress=end`; one report per block.
final class ProgressParser: Sendable {
    private let fields = Mutex<[String: String]>([:])

    func consume(_ line: String) -> EncodeProgress? {
        guard let separator = line.firstIndex(of: "=") else { return nil }
        let key = String(line[line.startIndex..<separator])
        let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
        return fields.withLock { fields in
            fields[key] = value
            guard key == "progress" else { return nil }
            defer { fields.removeAll() }
            let microseconds = fields["out_time_us"].flatMap(Double.init) ?? fields["out_time_ms"].flatMap(Double.init)
            return EncodeProgress(
                frame: fields["frame"].flatMap(Int.init),
                fps: fields["fps"].flatMap(Double.init),
                seconds: microseconds.map { $0 / 1_000_000 },
                speed: fields["speed"].flatMap { Double($0.replacingOccurrences(of: "x", with: "")) },
                finished: value == "end"
            )
        }
    }
}
