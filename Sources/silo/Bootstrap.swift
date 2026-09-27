// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import BasicContainers
import Foundation
import HTTPAPIs
import HTTPTypes
import Logging
import NIOHTTPServer
import SiloApp
import SiloKit
import SiloStore
import Wire
import WireMVC
import WireMVCRouter

// The composition root, and the whole of this target's entry point: there is no main.swift. The
// route generator emits it from this type — runs `prepare()`, bootstraps the graph with what it
// returned, asks this binding for the server and the route builder, registers every collated route
// contributor, mounts introspection, registers the fallback, freezes the builder and serves.

/// The graph's inputs, read before any binding is constructed: `silo.json` and the startup settings
/// as `SiloConfig`, and the settings store over `settings.json`. They are the honest case for an
/// input — deployment facts, read from the state directory, that must exist before the first binding
/// reads them and must stop the boot when they cannot be read.
@GraphInputs
package struct AppInputs: Sendable {
    package let siloConfig: SiloConfig
    package let settings: SettingsStore
}

@Singleton
@WireMVCBootstrap
package struct AppBootstrap {
    @Inject let config: SiloConfig

    /// Pre-graph, so it can inject nothing; `LoggingSystem.bootstrap` is why it has to run first.
    /// The state directory is resolved and logged before anything reads it, so where the reset file
    /// goes is the first thing the log says; then the two files are opened, and a file the silo will
    /// not start over stops the boot here, named, before anything is served.
    package static func prepare() async throws -> AppInputs {
        LoggingSystem.bootstrap { StreamLogHandler.standardOutput(label: $0) }
        let logger = Logger(label: "silo")
        let state = StateDirectory.resolve(for: .silo)
        logger.info("state directory: \(state.url.path) (\(state.source))")
        do {
            try FileManager.default.createDirectory(at: state.url, withIntermediateDirectories: true)
            let heldState = stateDirectoryHoldsState(state.url)
            let (silo, siloReport) = try SiloFile.open(in: state.url)
            log(siloReport, for: SiloFile.fileName, to: logger)
            if siloReport.defaulted("serverID") && heldState {
                logger.warning("minted a new ServerID, \(silo.serverID), over a state directory that already holds a silo's state: this is a new server to every console that knew the old one")
            }
            let (settings, settingsReport) = try SettingsStore.open(in: state.url, defaultName: "Silo on \(ProcessInfo.processInfo.hostName)")
            log(settingsReport, for: SettingsStore.fileName, to: logger)
            return AppInputs(siloConfig: try SiloConfig(silo: silo, settings: settings.current, stateDirectory: state.url), settings: settings)
        } catch {
            // A clean failure rather than a trap: a service manager reads a trap as a crash, and
            // this is a configuration the owner has to correct.
            logger.critical("not starting: \(error)")
            exit(EXIT_FAILURE)
        }
    }

    private static func log(_ report: ConfigurationFileReport, for file: String, to logger: Logger) {
        if report.created {
            logger.info("\(file): written with its defaults")
        } else if !report.filled.isEmpty {
            logger.info("\(file): added \(report.filled.joined(separator: ", ")) at their defaults")
        }
        for key in report.unknown {
            logger.warning("\(file): \"\(key)\" is not a key the silo knows; kept as it is")
        }
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
