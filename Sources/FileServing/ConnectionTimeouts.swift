// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import NIOHTTPServer

extension NIOHTTPServerConfiguration.ConnectionTimeouts {
    /// The timeouts every server of the silo's runs with: the silo's API and a participant's file
    /// server.
    ///
    /// swift-http-server arms its header timer again as soon as a request's `.end` has arrived, so it
    /// runs while the handler works and while the answer is sent, and closes the connection under
    /// either when it fires. With the library's 30 seconds, a placement that fetches a large output,
    /// a walk that moves folders, or a file served for longer than that is cut off part way. An hour
    /// is well beyond the slowest of them, and still drops a client that opens a connection and never
    /// sends anything. The idle and body timeouts keep the library's defaults. (#197)
    public static let silo = Self(readHeader: .seconds(3600))
}

extension NIOHTTPServerConfiguration {
    /// What every server of the silo's runs with: plaintext HTTP/1.1 bound to `host` and `port`, under
    /// the silo's timeouts. The silo's API and a participant's file server are both made from it, so
    /// neither can be given the library's timeouts by being built some other way.
    public static func silo(host: String, port: Int) throws -> Self {
        var configuration = try Self(
            bindTarget: .hostAndPort(host: host, port: port),
            supportedHTTPVersions: [.http1_1],
            transportSecurity: .plaintext
        )
        configuration.connectionTimeouts = .silo
        return configuration
    }
}
