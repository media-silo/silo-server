// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import BasicContainers
import Configuration
import HTTPAPIs
import HTTPTypes
import Logging
import NIOHTTPServer
import SiloApp
import Wire
import WireMVC
import WireMVCRouter

// The composition root, and the whole of this target's entry point: there is no main.swift. The
// route generator emits it from this type — runs `prepare()`, bootstraps the graph with what it
// returned, asks this binding for the server and the route builder, registers every collated route
// contributor, mounts introspection, registers the fallback, freezes the builder and serves.

/// The graph's inputs, read before any binding is constructed. The configuration is the honest
/// case for an input: it reads the environment, which is a deployment fact, and it has to exist
/// before the first binding that reads a key.
@GraphInputs
package struct AppInputs: Sendable {
    package let config: ConfigReader
    package let siloConfig: SiloConfig
}

@Singleton
@WireMVCBootstrap
package struct AppBootstrap {
    @Inject let config: SiloConfig

    /// Pre-graph, so it can inject nothing; `LoggingSystem.bootstrap` is why it has to run first.
    package static func prepare() async throws -> AppInputs {
        LoggingSystem.bootstrap { StreamLogHandler.standardOutput(label: $0) }
        let config = ConfigReader(provider: EnvironmentVariablesProvider())
        return AppInputs(config: config, siloConfig: try SiloConfig(reading: config))
    }

    /// The concrete server rather than `some HTTPServer`: the proposal's reader and sender are
    /// `~Copyable`, which a bare opaque return cannot express.
    package func createServer() throws -> NIOHTTPServer {
        NIOHTTPServer(
            logger: Logger(label: "silo"),
            configuration: try .init(
                bindTarget: .hostAndPort(host: config.host, port: config.port),
                supportedHTTPVersions: [.http1_1],
                transportSecurity: .plaintext
            )
        )
    }

    package func createRouteBuilder<Server: HTTPServer>(
        for server: borrowing Server
    ) -> some FinalizableHTTPServerRouteBuilder<Server.RequestContext, Server.Reader, Server.ResponseSender>
    where
        Server.RequestContext: ~Copyable,
        Server.Reader: ~Copyable,
        Server.ResponseSender: ~Copyable,
        Server.ResponseSender.Writer: ~Copyable
    {
        TrieRouteBuilder(for: server)
    }

    package func mountIntrospectionAt() -> String? { "/wiring" }

    @NotFound
    @RawRoute
    package func notFound<Sender: HTTPResponseSender & ~Copyable & SendableMetatype>(
        responseSender: consuming sending Sender
    ) async throws where Sender.Writer: ~Copyable {
        var body = UniqueArray<UInt8>(copying: Array(#"{"detail":"not found"}"#.utf8))
        try await responseSender.sendAndFinish(
            HTTPResponse(status: .notFound, headerFields: [.contentType: "application/json"]),
            buffer: &body
        )
    }
}
