// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import BasicContainers
import Foundation
import HTTPAPIs
import HTTPTypes

/// One byte range of a file, as a `Range` header asks for it. `bytes=a-b`, `bytes=a-` and
/// `bytes=-n` are honoured, one range at a time; anything else is the whole file, and a range the
/// file cannot satisfy is what a 416 answers.
public enum ByteRange: Hashable, Sendable {
    case whole
    case part(Int64, Int64)
    case unsatisfiable

    public static func parse(_ header: String?, size: Int64) -> ByteRange {
        guard let header, header.hasPrefix("bytes=") else { return .whole }
        let spec = header.dropFirst("bytes=".count)
        guard !spec.contains(","), let dash = spec.firstIndex(of: "-") else { return .whole }
        let first = spec[..<dash].trimmingCharacters(in: .whitespaces)
        let last = spec[spec.index(after: dash)...].trimmingCharacters(in: .whitespaces)
        if first.isEmpty {
            guard let suffix = Int64(last), suffix > 0 else { return .whole }
            guard size > 0 else { return .unsatisfiable }
            return .part(max(0, size - suffix), size - 1)
        }
        guard let start = Int64(first) else { return .whole }
        guard start < size else { return .unsatisfiable }
        let end = last.isEmpty ? size - 1 : (Int64(last).map { min($0, size - 1) } ?? size - 1)
        guard end >= start else { return .unsatisfiable }
        return .part(start, end)
    }
}

/// Sends a file, or a range of it, through the proposal's response sender: the head with the
/// range headers, then the bytes a chunk at a time, then the finish. The one place a file
/// becomes an HTTP response, used by the silo's media route and by every node that serves what
/// it holds.
public enum FileResponse {
    /// How much of a file goes to the writer at a time.
    public static let chunkSize = 1 << 20

    public static func send<Sender: HTTPResponseSender & ~Copyable>(
        file url: URL,
        method: HTTPRequest.Method,
        rangeHeader: String?,
        contentType: String,
        to responseSender: consuming Sender
    ) async throws where Sender.Writer: ~Copyable {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.int64Value,
              let handle = try? FileHandle(forReadingFrom: url)
        else {
            try await responseSender.sendAndFinish(HTTPResponse(status: .notFound))
            return
        }
        defer { try? handle.close() }
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        var headers: HTTPFields = [.acceptRanges: "bytes", .eTag: "\"\(size)-\(Int64(modified))\"", .contentType: contentType]

        let status: HTTPResponse.Status
        let start: Int64
        let end: Int64
        switch ByteRange.parse(rangeHeader, size: size) {
        case .whole:
            status = .ok
            start = 0
            end = size - 1
        case .part(let from, let to):
            status = .partialContent
            start = from
            end = to
            headers[.contentRange] = "bytes \(from)-\(to)/\(size)"
        case .unsatisfiable:
            headers[.contentRange] = "bytes */\(size)"
            try await responseSender.sendAndFinish(HTTPResponse(status: .rangeNotSatisfiable, headerFields: headers))
            return
        }
        let length = size == 0 ? 0 : end - start + 1
        headers[.contentLength] = String(length)

        if method == .head || length == 0 {
            try await responseSender.sendAndFinish(HTTPResponse(status: status, headerFields: headers))
            return
        }

        try handle.seek(toOffset: UInt64(start))
        var writer = try await responseSender.send(HTTPResponse(status: status, headerFields: headers))
        var remaining = length
        while remaining > 0 {
            let wanted = Int(min(Int64(chunkSize), remaining))
            guard let data = try handle.read(upToCount: wanted), !data.isEmpty else { break }
            var chunk = UniqueArray<UInt8>(copying: Array(data))
            try await writer.write(buffer: &chunk)
            remaining -= Int64(data.count)
        }
        var closing = UniqueArray<UInt8>()
        try await writer.finish(buffer: &closing, finalElement: nil)
    }

    public static func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mkv": "video/x-matroska"
        case "mp4", "m4v": "video/mp4"
        default: "application/octet-stream"
        }
    }
}
