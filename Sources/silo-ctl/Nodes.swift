// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import ArgumentParser
import Foundation
import SiloClient
import SiloDiscovery
import SiloKit

/// The nodes from the operator's side: who has asked to join, and the two decisions.
struct Nodes: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "The nodes: list them, approve one, revoke one, or find silos on the network.",
        subcommands: [List.self, Approve.self, Revoke.self, Discover.self]
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Every node the silo knows, pending ones included.")

        @OptionGroup var connection: Jobs.Connection

        mutating func run() async throws {
            let nodes = try await connection.client().nodes()
            if nodes.isEmpty { print("no nodes"); return }
            for node in nodes { print(Nodes.line(node)) }
        }
    }

    struct Approve: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Let a node take work. Its next poll gives it its token.")

        @OptionGroup var connection: Jobs.Connection
        @Argument var id: String

        mutating func run() async throws {
            print(Nodes.line(try await connection.client().approveNode(id)))
        }
    }

    struct Revoke: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Stop a node taking work; its token stops working at once.")

        @OptionGroup var connection: Jobs.Connection
        @Argument var id: String

        mutating func run() async throws {
            print(Nodes.line(try await connection.client().revokeNode(id)))
        }
    }

    struct Discover: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "The silos Bonjour can see on this network.")

        @Option(help: "Seconds to listen for.")
        var seconds: Int = 3

        mutating func run() async throws {
            guard Discovery.isAvailable else { throw ValidationError(Discovery.unavailable) }
            let found = try await Discovery.browse(timeout: .seconds(seconds))
            if found.isEmpty { print("no silos found"); return }
            for silo in found {
                print("\(silo.name)  \(silo.url)\(silo.txt.isEmpty ? "" : "  " + silo.txt.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }.joined(separator: " "))")
            }
        }
    }

    static func line(_ node: Node) -> String {
        var parts = [node.id, node.state.rawValue.padding(toLength: 9, withPad: " ", startingAt: 0), node.name, node.platform]
        if let cores = node.cores { parts.append("\(cores) cores") }
        parts.append("\(node.capabilities.count) encoders")
        if let seen = node.lastSeenAt { parts.append("seen \(seen.formatted(date: .abbreviated, time: .shortened))") }
        return parts.joined(separator: "  ")
    }
}
