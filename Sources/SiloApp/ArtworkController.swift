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
import SmdSidecar
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
        guard let target = try target(pathParameters), let file = Artwork.file(of: target.kind, in: target.folder)
        else {
            try await responseSender.sendAndFinish(HTTPResponse(status: .notFound))
            return
        }
        try await FileResponse.send(
            file: file.url,
            method: request.method,
            rangeHeader: request.headerFields[.range],
            contentType: file.format.contentType,
            to: responseSender
        )
    }

    /// The image's bytes, a JPEG or a PNG by their signature, written beside the kind's file and renamed
    /// over it; the kind's file in the other format, if there is one, is removed. With `provider` and
    /// `value`, the sidecar records whose the image is, and without them it records none, since the
    /// image is the operator's own. The sidecar is written first when it gains an attribution and last
    /// when it loses one, so an interrupted put credits the provider for too much rather than leaving
    /// its image uncredited. `Tmdb.md`, *Attributions on artwork*.
    @Put("/libraries/{library}/containers/{id}/artwork/{kind}")
    @RawRoute
    @Middleware(RouteMiddleware.requireOperator)
    package func putArtwork<
        Reader: AsyncReader & ~Copyable & SendableMetatype,
        Sender: HTTPResponseSender & ~Copyable & SendableMetatype
    >(
        request: HTTPRequest,
        pathParameters: [String: Substring],
        reader: consuming sending Reader,
        responseSender: consuming sending Sender
    ) async throws where Reader.ReadElement == UInt8, Reader.FinalElement == HTTPFields?, Sender.Writer: ~Copyable {
        guard let target = try target(pathParameters) else {
            try await responseSender.sendAndFinish(HTTPResponse(status: .notFound))
            return
        }
        let attribution: Attribution?
        do {
            attribution = try Self.attribution(of: target.kind, asked: request.path)
        } catch {
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
        guard let format = Artwork.Format(signatureOf: image) else {
            try await responseSender.sendAndFinish(HTTPResponse(status: .unsupportedMediaType))
            return
        }

        let written = try await store(image, as: format, attributedTo: attribution, at: target)
        guard written else {
            try await responseSender.sendAndFinish(HTTPResponse(status: .notFound))
            return
        }

        var body = UniqueArray<UInt8>(
            copying: Array(#"{"kind":"\#(target.kind)","format":"\#(format.rawValue)"}"#.utf8)
        )
        try await responseSender.sendAndFinish(
            HTTPResponse(
                status: .ok,
                headerFields: [.contentType: "application/json", .contentLength: String(body.count)]
            ),
            buffer: &body
        )
    }

    /// Writes the image as the kind's file and records or removes its attribution, under the library's
    /// lock: the sidecar first when it gains one, last when it loses one. False when the library no
    /// longer holds the container.
    private func store(
        _ image: Data,
        as format: Artwork.Format,
        attributedTo attribution: Attribution?,
        at target: Target
    ) async throws -> Bool {
        let kind = target.kind
        let index = index
        return try await libraries.exclusively(target.library) { () throws -> Bool in
            guard let row = try index.container(target.id, in: target.library.id) else { return false }
            let folder = target.library.root.appendingPathComponent(row.folder, isDirectory: true)
            if attribution != nil {
                try Self.attribute(kind, to: attribution, of: row, in: target.library, index: index)
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
            if attribution == nil {
                try Self.attribute(kind, to: nil, of: row, in: target.library, index: index)
            }
            return true
        }
    }

    @Delete("/libraries/{library}/containers/{id}/artwork/{kind}")
    @RawRoute
    @Middleware(RouteMiddleware.requireOperator)
    package func removeArtwork<Sender: HTTPResponseSender & ~Copyable & SendableMetatype>(
        pathParameters: [String: Substring],
        responseSender: consuming sending Sender
    ) async throws where Sender.Writer: ~Copyable {
        guard let target = try target(pathParameters) else {
            try await responseSender.sendAndFinish(HTTPResponse(status: .notFound))
            return
        }
        let index = index
        let removed = try await libraries.exclusively(target.library) { () throws -> Bool in
            guard let row = try index.container(target.id, in: target.library.id) else { return false }
            let folder = target.library.root.appendingPathComponent(row.folder, isDirectory: true)
            guard Artwork.file(of: target.kind, in: folder) != nil else { return false }
            for format in Artwork.Format.allCases {
                try? FileManager.default.removeItem(
                    at: folder.appendingPathComponent("\(target.kind).\(format.rawValue)")
                )
            }
            try Self.attribute(target.kind, to: nil, of: row, in: target.library, index: index)
            return true
        }
        try await responseSender.sendAndFinish(HTTPResponse(status: removed ? .noContent : .notFound))
    }

    /// A put's query is malformed: a provider without a value, or a value without a provider.
    private struct HalfAnAttribution: Error {}

    /// The attribution a put's `provider` and `value` ask for, both or neither: nil for neither, and
    /// refused for one alone.
    private static func attribution(of kind: String, asked path: String?) throws -> Attribution? {
        let query = URLComponents(string: path ?? "")?.queryItems ?? []
        let provider = query.first { $0.name == "provider" }?.value
        let value = query.first { $0.name == "value" }?.value
        switch (provider, value) {
        case (let provider?, let value?) where !provider.isEmpty && !value.isEmpty:
            return Attribution(subject: .artwork(kind), provider: Provider(rawValue: provider), value: value)
        case (nil, nil):
            return nil
        default:
            throw HalfAnAttribution()
        }
    }

    /// Sets, or with nil removes, the attribution of an artwork kind in the container's sidecar,
    /// writing it and reading it into the index only when that changes it.
    private static func attribute(
        _ kind: String,
        to attribution: Attribution?,
        of row: IndexedContainer,
        in library: LibraryConfig,
        index: Index
    ) throws {
        let url = library.root.appendingPathComponent("\(row.folder)/\(SidecarFile.fileName)")
        let held = try Data(contentsOf: url)
        let current = try SidecarFile.sidecar(from: held).attributions
        let subject = Attribution.Subject.artwork(kind)
        var next = current
        if let position = next.firstIndex(where: { $0.subject == subject }) {
            if let attribution { next[position] = attribution } else { next.remove(at: position) }
        } else if let attribution {
            next.append(attribution)
        }
        guard next != current else { return }
        try SidecarFile.data(settingAttributions: next, in: held).write(to: url, options: .atomic)
        _ = try Indexer.refresh(
            folder: row.folder,
            parent: row.parent.flatMap(ContainerID.init),
            in: library,
            index: index
        )
    }

    /// What the path names: the library, the container in it, the container's folder as the index has
    /// it now, and the artwork kind; nil for a library the silo does not serve, a container it does not
    /// hold, or a kind that is not one.
    private struct Target: Sendable {
        var library: LibraryConfig
        var id: ContainerID
        var folder: URL
        var kind: String
    }

    private func target(_ pathParameters: [String: Substring]) throws -> Target? {
        guard let library = pathParameters["library"].map(String.init).flatMap(libraries.library),
            let id = pathParameters["id"].flatMap({ ContainerID(String($0)) }),
            let kind = pathParameters["kind"].map(String.init), Artwork.kinds.contains(kind),
            let row = try index.container(id, in: library.id)
        else { return nil }
        return Target(
            library: library,
            id: id,
            folder: library.root.appendingPathComponent(row.folder, isDirectory: true),
            kind: kind
        )
    }
}
