// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloKit
import Synchronization

/// `ffprobe`, as a process. Its JSON is reduced to a `ProbedSource`; the reduction is a pure
/// function of the JSON, so it is tested on a captured document with no `ffprobe` present.
public struct FFprobe: Sendable {
    public let executable: URL

    public init(executable: URL? = nil) throws(ToolError) {
        guard let executable = executable ?? Tools.locate("ffprobe", environmentKey: "FFPROBE_PATH") else {
            throw ToolError.notFound("ffprobe")
        }
        self.executable = executable
    }

    public static var isAvailable: Bool {
        Tools.locate("ffprobe", environmentKey: "FFPROBE_PATH") != nil
    }

    public func probe(_ file: URL) async throws -> ProbedSource {
        let arguments = ["-v", "error", "-print_format", "json", "-show_format", "-show_streams", "-show_chapters", file.path]
        let collected = OutputCollector()
        let outcome = try await ProcessRunner.run(executable, arguments: arguments) { collected.append($0) }
        guard outcome.status == 0 else {
            throw ToolError.failed(tool: "ffprobe", status: outcome.status, stderr: outcome.stderrTail)
        }
        return try ProbedSource(ffprobeJSON: Data(collected.text.utf8))
    }
}

/// Collects the lines a tool wrote, for a tool whose output is one document rather than a stream.
package final class OutputCollector: Sendable {
    private let lines = Mutex<[String]>([])

    package init() {}

    package func append(_ line: String) {
        lines.withLock { $0.append(line) }
    }

    package var text: String {
        lines.withLock { $0.joined(separator: "\n") }
    }
}

extension ProbedSource {
    /// The reduction of `ffprobe -print_format json -show_format -show_streams -show_chapters`.
    public init(ffprobeJSON data: Data) throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let document: FFprobeDocument
        do {
            document = try decoder.decode(FFprobeDocument.self, from: data)
        } catch {
            throw ToolError.unreadableOutput(tool: "ffprobe", reason: String(describing: error))
        }
        let streams = document.streams.map { stream -> ProbedStream in
            let kind: ProbedStream.Kind = switch stream.codecType {
            case "video": .video
            case "audio": .audio
            case "subtitle": .subtitle
            case "data": .data
            case "attachment": .attachment
            default: .other
            }
            let dispositions = Set((stream.disposition ?? [:]).filter { $0.value != 0 }.keys)
            return ProbedStream(
                absoluteIndex: stream.index,
                kind: kind,
                codec: stream.codecName ?? "unknown",
                profile: stream.profile,
                width: stream.width,
                height: stream.height,
                frameRate: stream.avgFrameRate.flatMap(FrameRate.init) ?? stream.rFrameRate.flatMap(FrameRate.init),
                fieldOrder: stream.fieldOrder,
                colorTransfer: stream.colorTransfer,
                pixelFormat: stream.pixFmt,
                bitsPerRawSample: stream.bitsPerRawSample.flatMap(Int.init),
                channels: stream.channels,
                channelLayout: stream.channelLayout,
                language: stream.tags?["language"] ?? stream.tags?["LANGUAGE"],
                title: stream.tags?["title"] ?? stream.tags?["TITLE"],
                dispositions: dispositions
            )
        }
        let chapters = (document.chapters ?? []).compactMap { chapter -> ProbedChapter? in
            guard let start = chapter.startTime.flatMap(Double.init) else { return nil }
            return ProbedChapter(start: start, title: chapter.tags?["title"] ?? chapter.tags?["TITLE"])
        }
        self.init(duration: document.format?.duration.flatMap(Double.init), streams: streams, chapters: chapters)
    }
}

private struct FFprobeDocument: Decodable {
    var streams: [Stream]
    var format: Format?
    var chapters: [Chapter]?

    struct Stream: Decodable {
        var index: Int
        var codecType: String
        var codecName: String?
        var profile: String?
        var width: Int?
        var height: Int?
        var rFrameRate: String?
        var avgFrameRate: String?
        var fieldOrder: String?
        var colorTransfer: String?
        var pixFmt: String?
        var bitsPerRawSample: String?
        var channels: Int?
        var channelLayout: String?
        var tags: [String: String]?
        var disposition: [String: Int]?
    }

    struct Format: Decodable {
        var duration: String?
    }

    struct Chapter: Decodable {
        var startTime: String?
        var tags: [String: String]?
    }
}
