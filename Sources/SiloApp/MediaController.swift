// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import BasicContainers
import Foundation
import HTTPAPIs
import HTTPTypes
import SiloStore
import SmdKit
import Wire
import WireMVC

/// The two routes that stream bytes, outside the document because an operation buffers its body
/// whole: the file a presentation is, and the sidecar a container is.
@Singleton
@Controller("/v1")
package struct MediaController {
    private let config: SiloConfig
    private let index: Index

    /// How much of a file goes to the writer at a time.
    static let chunkSize = 1 << 20

    @Inject
    package init(config: SiloConfig, index: Index) {
        self.config = config
        self.index = index
    }

    /// Direct play, with `Range`. `bytes=a-b`, `bytes=a-` and `bytes=-n` are honoured, one range
    /// at a time; anything else is the whole file. A range the file cannot satisfy is 416 with the
    /// size, as the specification asks.
    @Get("/media/{presentation}")
    @RawRoute
    package func media<Sender: HTTPResponseSender & ~Copyable & SendableMetatype>(
        request: HTTPRequest,
        pathParameters: [String: Substring],
        responseSender: consuming sending Sender
    ) async throws where Sender.Writer: ~Copyable {
        guard let id = pathParameters["presentation"].map(String.init),
              let presentation = try index.presentation(id),
              let library = config.library(presentation.library)
        else {
            try await responseSender.sendAndFinish(HTTPResponse(status: .notFound))
            return
        }
        let url = library.root.appendingPathComponent(presentation.path)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.int64Value,
              let handle = try? FileHandle(forReadingFrom: url)
        else {
            try await responseSender.sendAndFinish(HTTPResponse(status: .notFound))
            return
        }
        defer { try? handle.close() }
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let etag = "\"\(size)-\(Int64(modified))\""
        let contentType = url.pathExtension.lowercased() == "mkv" ? "video/x-matroska" : "application/octet-stream"

        var headers: HTTPFields = [.acceptRanges: "bytes", .eTag: etag, .contentType: contentType]
        let range = Self.range(from: request.headerFields[.range], size: size)
        let status: HTTPResponse.Status
        let start: Int64
        let end: Int64
        switch range {
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

        if request.method == .head || length == 0 {
            try await responseSender.sendAndFinish(HTTPResponse(status: status, headerFields: headers))
            return
        }

        try handle.seek(toOffset: UInt64(start))
        var writer = try await responseSender.send(HTTPResponse(status: status, headerFields: headers))
        var remaining = length
        while remaining > 0 {
            let wanted = Int(min(Int64(Self.chunkSize), remaining))
            guard let data = try handle.read(upToCount: wanted), !data.isEmpty else { break }
            var chunk = UniqueArray<UInt8>(copying: Array(data))
            try await writer.write(buffer: &chunk)
            remaining -= Int64(data.count)
        }
        var closing = UniqueArray<UInt8>()
        try await writer.finish(buffer: &closing, finalElement: nil)
    }

    /// The container as its sidecar: the bytes the index was built from.
    @Get("/containers/{id}/smd")
    @RawRoute
    package func sidecar<Sender: HTTPResponseSender & ~Copyable & SendableMetatype>(
        pathParameters: [String: Substring],
        responseSender: consuming sending Sender
    ) async throws where Sender.Writer: ~Copyable {
        guard let id = pathParameters["id"].flatMap({ ContainerID(String($0)) }), let row = try index.container(id) else {
            try await responseSender.sendAndFinish(HTTPResponse(status: .notFound))
            return
        }
        var body = UniqueArray<UInt8>(copying: Array(row.document))
        try await responseSender.sendAndFinish(
            HTTPResponse(status: .ok, headerFields: [.contentType: "application/xml; charset=utf-8", .contentLength: String(row.document.count)]),
            buffer: &body
        )
    }

    enum Range: Equatable {
        case whole
        case part(Int64, Int64)
        case unsatisfiable
    }

    static func range(from header: String?, size: Int64) -> Range {
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
