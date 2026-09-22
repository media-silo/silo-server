// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import ArgumentParser
import Encoder
import FileServing
import Foundation
import Logging
import SiloClient
import SiloDiscovery
import SiloKit
import SiloWorker

/// A node on another machine. Finds the silo, registers, waits to be approved, then runs the
/// worker's loop and serves what it makes for the silo to fetch at placement.
@main
struct SiloNode: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "silo-node",
        abstract: "Encode for a silo on this network."
    )

    @Option(help: "The silo's URL. Found by Bonjour when not given; SILO_URL also works.")
    var silo: String?

    @Option(help: "This node's name, as the operator sees it. Defaults to the machine's.")
    var name: String?

    @Option(name: .customLong("state-dir"), help: "Where the node keeps its identity. Defaults to ~/.silo-node.")
    var stateDirectory: String?

    @Option(name: .customLong("serve-port"), help: "The port finished files are served on for the silo to fetch.")
    var servePort: Int = 18600

    @Option(name: .customLong("advertised-host"), help: "The name the silo reaches this machine by. Defaults to the machine's host name.")
    var advertisedHost: String?

    @Option(name: .customLong("poll"), help: "Seconds between asking for work.")
    var pollSeconds: Int = 5

    mutating func run() async throws {
        LoggingSystem.bootstrap { StreamLogHandler.standardOutput(label: $0) }
        let logger = Logger(label: "silo-node")
        let environment = ProcessInfo.processInfo.environment
        let hostName = ProcessInfo.processInfo.hostName
        let nodeName = name ?? hostName
        let state = URL(fileURLWithPath: stateDirectory ?? (NSHomeDirectory() + "/.silo-node"), isDirectory: true)
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)

        // The tools first: a node without them has nothing to offer.
        let ffmpeg = try FFmpeg()
        let ffprobe = try FFprobe()
        let capabilities = try await ffmpeg.encoders()
        let version = try await ffmpeg.version()

        // The silo: given, from the environment, or found.
        let baseURL: URL
        if let text = silo ?? environment["SILO_URL"], let url = URL(string: text) {
            baseURL = url
        } else {
            guard Discovery.isAvailable else { throw ValidationError("give --silo; \(Discovery.unavailable)") }
            logger.info("looking for a silo…")
            let found = try await Discovery.browse()
            guard let first = found.first else { throw ValidationError("no silo found on this network; give --silo") }
            if found.count > 1 { logger.info("\(found.count) silos found; using \(first.name)") }
            logger.info("found \(first.name) at \(first.url)")
            baseURL = first.url
        }

        // The identity: minted once and kept.
        let identityURL = state.appendingPathComponent("identity.json")
        var identity: NodeIdentity
        if let data = try? Data(contentsOf: identityURL), let saved = try? JSONDecoder().decode(NodeIdentity.self, from: data) {
            identity = saved
        } else {
            identity = NodeIdentity()
            try JSONEncoder().encode(identity).write(to: identityURL, options: .atomic)
        }

        let registering = SiloClient(baseURL: baseURL)
        let registration = NodeRegistration(
            id: identity.id, secret: identity.secret, name: nodeName,
            platform: Self.platform, capabilities: capabilities.sorted(),
            ffmpegVersion: version, cores: ProcessInfo.processInfo.activeProcessorCount
        )
        var node = try await registering.registerNode(registration)
        logger.info("registered as \(node.name) (\(node.id)): \(node.state.rawValue)")

        // Approval, and the token that comes with it.
        var announced = false
        while identity.token == nil {
            let status = try await registering.nodeStatus(id: identity.id, secret: identity.secret)
            node = status.node
            if let token = status.token {
                identity.token = token
                try JSONEncoder().encode(identity).write(to: identityURL, options: .atomic)
                logger.info("approved; token taken")
            } else if node.state == .revoked {
                throw ValidationError("this node has been revoked on the silo")
            } else {
                if !announced {
                    logger.info("waiting for approval: on the silo, run  silo-ctl nodes approve \(identity.id)")
                    announced = true
                }
                try await Task.sleep(for: .seconds(5))
            }
        }

        // Serving what it makes.
        let server = try FileServer(port: servePort, advertisedHost: advertisedHost ?? hostName)
        let serving = Task { try await server.run() }
        defer { serving.cancel() }
        let holder = identity.id

        let client = SiloClient(baseURL: baseURL, token: identity.token)
        let worker = Worker(
            api: client,
            configuration: Worker.Configuration(
                nodeID: identity.id,
                workFolder: state.appendingPathComponent("work", isDirectory: true),
                pollInterval: .seconds(pollSeconds)
            ) { job, file in
                var ref = server.publish(file, at: "\(job)/output")
                ref.holder = holder
                return ref
            },
            ffmpeg: ffmpeg, ffprobe: ffprobe, logger: logger
        )
        logger.info("ready: \(capabilities.count) encoders, serving outputs on port \(servePort)")
        await worker.run()
    }

    static var platform: String {
        #if os(macOS)
        "macOS"
        #elseif os(Linux)
        "Linux"
        #else
        "other"
        #endif
    }
}
