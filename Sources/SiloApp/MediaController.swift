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
    private let config: SiloConfig
    private let index: Index

    @Inject
    package init(config: SiloConfig, index: Index) {
        self.config = config
        self.index = index
    }

    /// Direct play, with `Range`, through the same response every node serves its files with.
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
        try await FileResponse.send(
            file: url,
            method: request.method,
            rangeHeader: request.headerFields[.range],
            contentType: FileResponse.contentType(for: url),
            to: responseSender
        )
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
}
