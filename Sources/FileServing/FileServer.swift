// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import HTTPAPIs
import HTTPTypes
import Logging
import NIOHTTPServer
import SiloKit
import Synchronization

/// Serves the files a node holds, by range, to the node that needs them. `Silo.md`, principle 6:
/// files stay where they are until they are placed, and every participant serves its own.
///
/// A file is published under a path of the node's choosing with a secret the silo hands only to
/// the node that claimed the job; a request without it is 404, not 401, so that the set of
/// paths is not enumerable. Serving is `NIOHTTPServer` with one handler, no framework.
public final class FileServer: Sendable {
    public struct Published: Hashable, Sendable {
        public var url: URL
        public var secret: String
    }

    /// The header a fetching node sends the secret in.
    public static let secretHeader = HTTPField.Name("x-silo-secret")!

    private let files = Mutex<[String: Published]>([:])
    private let server: NIOHTTPServer
    private let host: String
    private let port: Int
    private let logger: Logger

    /// `advertisedHost` is what other machines reach this one as; the bind host may be `0.0.0.0`.
    public init(host: String = "0.0.0.0", port: Int, advertisedHost: String, logger: Logger = Logger(label: "silo.files")) throws {
        self.host = advertisedHost
        self.port = port
        self.logger = logger
        server = NIOHTTPServer(
            logger: logger,
            configuration: try .init(
                bindTarget: .hostAndPort(host: host, port: port),
                supportedHTTPVersions: [.http1_1],
                transportSecurity: .plaintext
            )
        )
    }

    /// Publishes a file under a path and returns where it is and the secret to fetch it with.
    public func publish(_ url: URL, at path: String, secret: String = FileRef.mintSecret()) -> FileRef {
        files.withLock { $0[path] = Published(url: url, secret: secret) }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
        return FileRef(holder: "", url: URL(string: "http://\(host):\(port)/files/\(path)")!, path: url.path, sizeBytes: size, secret: secret)
    }

    public func unpublish(_ path: String) {
        files.withLock { $0[path] = nil }
    }

    public var published: [String] {
        files.withLock { Array($0.keys) }.sorted()
    }

    /// Serves until cancelled.
    public func run() async throws {
        try await server.serve(handler: Handler(files: self))
    }

    func lookup(_ path: String) -> Published? {
        files.withLock { $0[path] }
    }

    /// The one handler: a published path with its secret is the file, by range; anything else is
    /// 404, so that the set of paths cannot be told from the set of secrets.
    struct Handler: HTTPServerRequestHandler {
        let files: FileServer

        func handle(
            request: HTTPRequest,
            requestContext: consuming NIOHTTPServer.RequestContext,
            reader: consuming sending NIOHTTPServer.Reader,
            responseSender: consuming sending NIOHTTPServer.ResponseSender
        ) async throws {
            guard request.method == .get || request.method == .head,
                  let path = request.path, path.hasPrefix("/files/"),
                  let published = files.lookup(String(path.dropFirst("/files/".count))),
                  request.headerFields[FileServer.secretHeader] == published.secret
            else {
                try await responseSender.sendAndFinish(HTTPResponse(status: .notFound))
                return
            }
            try await FileResponse.send(
                file: published.url,
                method: request.method,
                rangeHeader: request.headerFields[.range],
                contentType: FileResponse.contentType(for: published.url),
                to: responseSender
            )
        }
    }

    /// The port actually bound, once serving: what to advertise when the configured port was 0.
    public var boundPort: Int {
        get async throws {
            try await server.listeningAddresses.first?.port ?? port
        }
    }
}
