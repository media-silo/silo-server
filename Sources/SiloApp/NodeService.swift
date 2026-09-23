// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import Logging
import SiloKit
import SiloStore
import Wire

/// Nodes: registered by themselves, approved by a person, authenticated by the token the approval
/// minted. The silo stores hashes of the secret and the token and never either itself.
@Singleton
package final class NodeService: Sendable {
    private let nodes: NodeStore
    private let logger = Logger(label: "silo.nodes")

    @Inject
    package init(nodes: NodeStore) {
        self.nodes = nodes
    }

    package func all() -> [Node] {
        nodes.all().map(\.node)
    }

    package func node(_ id: String) throws -> Node {
        guard let stored = nodes.stored(id) else { throw NoSuchNode() }
        return stored.node
    }

    /// A first registration is recorded pending. A later one of the same id has to know the
    /// secret, and then brings the node's name and capabilities up to date.
    package func register(_ registration: NodeRegistration) throws -> Node {
        let secretHash = NodeStore.hash(registration.secret)
        if let existing = nodes.stored(registration.id) {
            guard existing.secretHash == secretHash else { throw WrongSecret() }
            return try nodes.update(registration.id) { stored in
                stored.node.name = registration.name
                stored.node.platform = registration.platform
                stored.node.capabilities = registration.capabilities
                stored.node.ffmpegVersion = registration.ffmpegVersion
                stored.node.cores = registration.cores
                stored.node.lastSeenAt = .now
            }!.node
        }
        let node = Node(id: registration.id, name: registration.name, platform: registration.platform, capabilities: registration.capabilities, ffmpegVersion: registration.ffmpegVersion, cores: registration.cores, lastSeenAt: .now)
        try nodes.insert(NodeStore.Stored(node: node, secretHash: secretHash, tokenHash: nil, tokenDelivered: false))
        logger.info("node \(node.name) (\(node.id)) registered, pending approval")
        return node
    }

    /// The node's poll. Once approved, the first poll after it carries the token; later ones do
    /// not, since the node keeps it.
    package func status(_ id: String, secret: String) throws -> NodeStatus {
        guard let stored = nodes.stored(id) else { throw NoSuchNode() }
        guard stored.secretHash == NodeStore.hash(secret) else { throw WrongSecret() }
        guard stored.node.state == .approved, !stored.tokenDelivered else {
            _ = try nodes.update(id) { $0.node.lastSeenAt = .now }
            return NodeStatus(node: stored.node)
        }
        let token = FileRef.mintSecret()
        let updated = try nodes.update(id) { stored in
            stored.tokenHash = NodeStore.hash(token)
            stored.tokenDelivered = true
            stored.node.lastSeenAt = .now
        }!
        logger.info("node \(updated.node.name) took its token")
        return NodeStatus(node: updated.node, token: token)
    }

    /// Approval mints a token the node's next poll takes. Approving again, after a revoke, mints
    /// a new one; the old was invalidated by the revoke.
    package func approve(_ id: String) throws -> Node {
        guard nodes.stored(id) != nil else { throw NoSuchNode() }
        let updated = try nodes.update(id) { stored in
            stored.node.state = .approved
            stored.node.approvedAt = .now
            stored.tokenHash = nil
            stored.tokenDelivered = false
        }!
        logger.info("node \(updated.node.name) approved")
        return updated.node
    }

    package func revoke(_ id: String) throws -> Node {
        guard nodes.stored(id) != nil else { throw NoSuchNode() }
        let updated = try nodes.update(id) { stored in
            stored.node.state = .revoked
            stored.tokenHash = nil
            stored.tokenDelivered = false
        }!
        logger.info("node \(updated.node.name) revoked")
        return updated.node
    }

    /// The approved node a bearer token belongs to, or nil. Seeing it is the node's heartbeat.
    package func authenticate(bearer token: String) -> Node? {
        let hash = NodeStore.hash(token)
        guard let stored = nodes.first(where: { $0.node.state == .approved && $0.tokenHash == hash }) else { return nil }
        _ = try? nodes.update(stored.node.id) { $0.node.lastSeenAt = .now }
        return stored.node
    }
}

package struct NoSuchNode: Error {}
package struct WrongSecret: Error {}
