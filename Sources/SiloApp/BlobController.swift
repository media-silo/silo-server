// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import BasicContainers
import Foundation
import HTTPAPIs
import HTTPTypes
import SiloLibrary
import SiloStore
import Wire
import WireMVC

/// Images held by their digest for a store to put, sent before the store so that its request is small
/// and an image is sent once however often the store is. The routes carry bytes, and so are served
/// beside the document rather than in it. Both are the operator's. `Stores.md`, *Images sent before
/// the store*.
@Singleton
@Controller("/v1")
package struct BlobController {
    private let blobs: BlobStore

    @Inject
    package init(blobs: BlobStore) {
        self.blobs = blobs
    }

    /// Whether the silo holds the blob: its digest and size, or 404.
    @Get("/blobs/{digest}")
    @RawRoute
    @Middleware(RouteMiddleware.requireOperator)
    package func blob<Sender: HTTPResponseSender & ~Copyable & SendableMetatype>(
        pathParameters: [String: Substring],
        responseSender: consuming sending Sender
    ) async throws where Sender.Writer: ~Copyable {
        blobs.sweep()
        guard let digest = pathParameters["digest"].map(String.init), let data = blobs.data(of: digest) else {
            try await responseSender.sendAndFinish(HTTPResponse(status: .notFound))
            return
        }
        var body = UniqueArray<UInt8>(copying: Array(#"{"digest":"\#(digest)","size":\#(data.count)}"#.utf8))
        try await responseSender.sendAndFinish(
            HTTPResponse(
                status: .ok,
                headerFields: [.contentType: "application/json", .contentLength: String(body.count)]
            ),
            buffer: &body
        )
    }

    /// The image's bytes, a JPEG or a PNG by their signature and no larger than artwork may be, held
    /// under the digest the path names when it is theirs. Held already, they are answered as put.
    @Put("/blobs/{digest}")
    @RawRoute
    @Middleware(RouteMiddleware.requireOperator)
    package func putBlob<
        Reader: AsyncReader & ~Copyable & SendableMetatype,
        Sender: HTTPResponseSender & ~Copyable & SendableMetatype
    >(
        request: HTTPRequest,
        pathParameters: [String: Substring],
        reader: consuming sending Reader,
        responseSender: consuming sending Sender
    ) async throws where Reader.ReadElement == UInt8, Reader.FinalElement == HTTPFields?, Sender.Writer: ~Copyable {
        guard let digest = pathParameters["digest"].map(String.init), BlobStore.isDigest(digest) else {
            try await responseSender.sendAndFinish(HTTPResponse(status: .badRequest))
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
        guard Artwork.Format(signatureOf: image) != nil else {
            try await responseSender.sendAndFinish(HTTPResponse(status: .unsupportedMediaType))
            return
        }
        guard BlobStore.digest(of: image) == digest else {
            try await responseSender.sendAndFinish(HTTPResponse(status: .badRequest))
            return
        }
        _ = try blobs.put(image)
        blobs.sweep()
        try await responseSender.sendAndFinish(HTTPResponse(status: .noContent))
    }
}
