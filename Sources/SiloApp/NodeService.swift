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
package struct NodeService: Sendable {
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
        let node = Node(
            id: registration.id,
            name: registration.name,
            platform: registration.platform,
            capabilities: registration.capabilities,
            ffmpegVersion: registration.ffmpegVersion,
            cores: registration.cores,
            lastSeenAt: .now
        )
        try nodes.insert(NodeStore.Stored(node: node, secretHash: secretHash, tokenHash: nil, tokenDelivered: false))
        logger.info("node \(node.name) (\(node.id)) registered, pending approval")
        return node
    }

    /// The node's poll. Once approved, every poll carries a token until the node first uses one,
    /// each a new token whose hash replaces the last, so a poll whose answer is lost costs nothing:
    /// the next poll's token is the one that works. Once the node has used its token, polls carry
    /// none, since the node keeps it.
    package func status(_ id: String, secret: String) throws -> NodeStatus {
        guard let stored = nodes.stored(id) else { throw NoSuchNode() }
        guard stored.secretHash == NodeStore.hash(secret) else { throw WrongSecret() }
        var token: String?
        let updated = try nodes.update(id) { stored in
            stored.node.lastSeenAt = .now
            guard stored.node.state == .approved, !stored.tokenDelivered else { return }
            let minted = FileRef.mintSecret()
            stored.tokenHash = NodeStore.hash(minted)
            token = minted
        }!
        if token != nil { logger.info("node \(updated.node.name) was given a token") }
        return NodeStatus(node: updated.node, token: token)
    }

    /// Approval clears any token, so the node's next poll is given one. Approving again, after a
    /// revoke, gives a new one; the old was invalidated by the revoke.
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

    /// The approved node a bearer token belongs to, or nil. Seeing it is the node's heartbeat, and
    /// the first sight of it says the node received it, so its polls stop carrying one.
    package func authenticate(bearer token: String) -> Node? {
        let hash = NodeStore.hash(token)
        guard let stored = nodes.first(where: { $0.node.state == .approved && $0.tokenHash == hash }) else {
            return nil
        }
        _ = try? nodes.update(stored.node.id) { stored in
            stored.node.lastSeenAt = .now
            if !stored.tokenDelivered {
                stored.tokenDelivered = true
                logger.info("node \(stored.node.name) used its token")
            }
        }
        return stored.node
    }
}

package struct NoSuchNode: Error {}
package struct WrongSecret: Error {}
