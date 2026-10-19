// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import BasicContainers
import FileServing
import Foundation
import HTTPAPIs
import HTTPTypes
import SiloLibrary
import SiloStore
import SmdKit
import Wire
import WireMVC

/// A container's artwork, read, put and removed by kind: images beside its sidecar, which the routes
/// carry as bytes and so are served beside the document rather than in it. Reading is open, as the
/// other read routes are; putting and removing are the operator's.
@Singleton
@Controller("/v1")
package struct ArtworkController {
    private let libraries: Libraries
    private let index: Index

    @Inject
    package init(libraries: Libraries, index: Index) {
        self.libraries = libraries
        self.index = index
    }

    @Get("/libraries/{library}/containers/{id}/artwork/{kind}")
    @RawRoute
    package func artwork<Sender: HTTPResponseSender & ~Copyable & SendableMetatype>(
        request: HTTPRequest,
        pathParameters: [String: Substring],
        responseSender: consuming sending Sender
    ) async throws where Sender.Writer: ~Copyable {
        guard let (folder, kind) = try folder(pathParameters), let file = Artwork.file(of: kind, in: folder) else {
            try await responseSender.sendAndFinish(HTTPResponse(status: .notFound))
            return
        }
        try await FileResponse.send(
            file: file.url, method: request.method, rangeHeader: request.headerFields[.range],
            contentType: file.format.contentType, to: responseSender
        )
    }

    /// The image's bytes, a JPEG or a PNG by their signature, written beside the kind's file and renamed
    /// over it; the kind's file in the other format, if there is one, is removed.
    @Put("/libraries/{library}/containers/{id}/artwork/{kind}")
    @RawRoute
    @Middleware(RouteMiddleware.requireOperator)
    package func putArtwork<Reader: AsyncReader & ~Copyable & SendableMetatype, Sender: HTTPResponseSender & ~Copyable & SendableMetatype>(
        request: HTTPRequest,
        pathParameters: [String: Substring],
        reader: consuming sending Reader,
        responseSender: consuming sending Sender
    ) async throws where Reader.ReadElement == UInt8, Reader.FinalElement == HTTPFields?, Sender.Writer: ~Copyable {
        guard let (folder, kind) = try folder(pathParameters) else {
            try await responseSender.sendAndFinish(HTTPResponse(status: .notFound))
            return
        }
        if let length = request.headerFields[.contentLength].flatMap(Int.init), length > Artwork.maximumSize {
            try await responseSender.sendAndFinish(HTTPResponse(status: .contentTooLarge))
            return
        }
        var buffer = UniqueArray<UInt8>()
        do {
            _ = try await reader.collect(into: &buffer, maximumSize: Artwork.maximumSize)
        } catch {
            try await responseSender.sendAndFinish(HTTPResponse(status: .contentTooLarge))
            return
        }
        let span = buffer.span
        var bytes = [UInt8]()
        bytes.reserveCapacity(span.count)
        for index in 0..<span.count { bytes.append(span[index]) }
        let image = Data(bytes)
        guard let format = Artwork.Format(signatureOf: image) else {
            try await responseSender.sendAndFinish(HTTPResponse(status: .unsupportedMediaType))
            return
        }

        let destination = folder.appendingPathComponent("\(kind).\(format.rawValue)")
        let beside = folder.appendingPathComponent(".\(kind).\(UUID().uuidString).\(format.rawValue)")
        try image.write(to: beside)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: beside)
            } else {
                try FileManager.default.moveItem(at: beside, to: destination)
            }
        } catch {
            try? FileManager.default.removeItem(at: beside)
            throw error
        }
        for other in Artwork.Format.allCases where other != format {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent("\(kind).\(other.rawValue)"))
        }

        var body = UniqueArray<UInt8>(copying: Array(#"{"kind":"\#(kind)","format":"\#(format.rawValue)"}"#.utf8))
        try await responseSender.sendAndFinish(
            HTTPResponse(status: .ok, headerFields: [.contentType: "application/json", .contentLength: String(body.count)]),
            buffer: &body
        )
    }

    @Delete("/libraries/{library}/containers/{id}/artwork/{kind}")
    @RawRoute
    @Middleware(RouteMiddleware.requireOperator)
    package func removeArtwork<Sender: HTTPResponseSender & ~Copyable & SendableMetatype>(
        pathParameters: [String: Substring],
        responseSender: consuming sending Sender
    ) async throws where Sender.Writer: ~Copyable {
        guard let (folder, kind) = try folder(pathParameters), Artwork.file(of: kind, in: folder) != nil else {
            try await responseSender.sendAndFinish(HTTPResponse(status: .notFound))
            return
        }
        for format in Artwork.Format.allCases {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent("\(kind).\(format.rawValue)"))
        }
        try await responseSender.sendAndFinish(HTTPResponse(status: .noContent))
    }

    /// The folder of the container the path names, in the library it names, and the artwork kind it
    /// names; nil for a library the silo does not serve, a container it does not hold, or a kind that
    /// is not one.
    private func folder(_ pathParameters: [String: Substring]) throws -> (URL, String)? {
        guard let library = pathParameters["library"].map(String.init).flatMap(libraries.library),
              let id = pathParameters["id"].flatMap({ ContainerID(String($0)) }),
              let kind = pathParameters["kind"].map(String.init), Artwork.kinds.contains(kind),
              let row = try index.container(id, in: library.id)
        else { return nil }
        return (library.root.appendingPathComponent(row.folder, isDirectory: true), kind)
    }
}
