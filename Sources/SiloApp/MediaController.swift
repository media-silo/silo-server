// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import BasicContainers
import FileServing
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
    private let libraries: Libraries
    private let index: Index

    @Inject
    package init(libraries: Libraries, index: Index) {
        self.libraries = libraries
        self.index = index
    }

    /// Direct play, with `Range`, through the same response every node serves its files with. A
    /// presentation of an unavailable library is 503 — not now, rather than the 404 of not ever. A
    /// file found gone re-reads its container before the 404, so the deletion is noticed at once.
    @Get("/media/{presentation}")
    @RawRoute
    package func media<Sender: HTTPResponseSender & ~Copyable & SendableMetatype>(
        request: HTTPRequest,
        pathParameters: [String: Substring],
        responseSender: consuming sending Sender
    ) async throws where Sender.Writer: ~Copyable {
        guard let id = pathParameters["presentation"].map(String.init),
            let presentation = try index.presentation(id),
            let library = libraries.library(presentation.library)
        else {
            try await responseSender.sendAndFinish(HTTPResponse(status: .notFound))
            return
        }
        guard try await libraries.reach(library) else {
            try await responseSender.sendAndFinish(HTTPResponse(status: .serviceUnavailable))
            return
        }
        let url = library.root.appendingPathComponent(presentation.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            if let container = ContainerID(presentation.container) {
                try await libraries.refresh(container, in: library)
            }
            try await responseSender.sendAndFinish(HTTPResponse(status: .notFound))
            return
        }
        try await FileResponse.send(
            file: url,
            method: request.method,
            rangeHeader: request.headerFields[.range],
            contentType: FileResponse.contentType(for: url),
            to: responseSender
        )
    }

    /// The container as its sidecar: the bytes the index was built from. A container in several
    /// libraries is the first's that holds it, as `GET /v1/containers/{id}` answers it.
    @Get("/containers/{id}/smd")
    @RawRoute
    package func sidecar<Sender: HTTPResponseSender & ~Copyable & SendableMetatype>(
        pathParameters: [String: Substring],
        responseSender: consuming sending Sender
    ) async throws where Sender.Writer: ~Copyable {
        let row = try pathParameters["id"].flatMap { ContainerID(String($0)) }.flatMap { id in
            let held = Dictionary(
                try index.containers(id).map { ($0.library, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            return libraries.all.lazy.compactMap { held[$0.id] }.first
        }
        try await Self.send(row?.document, to: responseSender)
    }

    /// One library's sidecar for a container, whether or not another library holds it too.
    @Get("/libraries/{library}/containers/{id}/smd")
    @RawRoute
    package func librarySidecar<Sender: HTTPResponseSender & ~Copyable & SendableMetatype>(
        pathParameters: [String: Substring],
        responseSender: consuming sending Sender
    ) async throws where Sender.Writer: ~Copyable {
        let library = pathParameters["library"].map(String.init).flatMap(libraries.library)
        let row = try library.flatMap { library in
            try pathParameters["id"].flatMap { ContainerID(String($0)) }.flatMap {
                try index.container($0, in: library.id)
            }
        }
        try await Self.send(row?.document, to: responseSender)
    }

    private static func send<Sender: HTTPResponseSender & ~Copyable & SendableMetatype>(
        _ document: Data?,
        to responseSender: consuming sending Sender
    ) async throws where Sender.Writer: ~Copyable {
        guard let document else {
            try await responseSender.sendAndFinish(HTTPResponse(status: .notFound))
            return
        }
        var body = UniqueArray<UInt8>(copying: Array(document))
        try await responseSender.sendAndFinish(
            HTTPResponse(
                status: .ok,
                headerFields: [.contentType: "application/xml; charset=utf-8", .contentLength: String(document.count)]
            ),
            buffer: &body
        )
    }
}
