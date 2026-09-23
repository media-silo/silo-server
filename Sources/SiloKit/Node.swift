// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation

/// A machine that encodes, as the silo records it. `Silo.md`, *Nodes, discovery and approval*: a
/// node registers itself and is given nothing; a person approves it; its next poll returns its
/// token; revoking it is one state change.
public struct Node: Identifiable, Hashable, Sendable, Codable {
    public var id: String
    public var name: String
    public var platform: String
    public var state: NodeState
    /// The encoders its `ffmpeg` has, by name.
    public var capabilities: [String]
    public var ffmpegVersion: String?
    public var cores: Int?
    public var registeredAt: Date
    public var approvedAt: Date?
    public var lastSeenAt: Date?

    public init(id: String, name: String, platform: String, state: NodeState = .pending, capabilities: [String] = [], ffmpegVersion: String? = nil, cores: Int? = nil, registeredAt: Date = .now, approvedAt: Date? = nil, lastSeenAt: Date? = nil) {
        self.id = id
        self.name = name
        self.platform = platform
        self.state = state
        self.capabilities = capabilities
        self.ffmpegVersion = ffmpegVersion
        self.cores = cores
        self.registeredAt = registeredAt
        self.approvedAt = approvedAt
        self.lastSeenAt = lastSeenAt
    }
}

public enum NodeState: String, Hashable, Sendable, Codable, CaseIterable {
    case pending, approved, revoked
}

/// What a node sends when it registers. The secret is minted by the node on its first run and
/// kept; it is what a later registration of the same id has to know.
public struct NodeRegistration: Hashable, Sendable, Codable {
    public var id: String
    public var secret: String
    public var name: String
    public var platform: String
    public var capabilities: [String]
    public var ffmpegVersion: String?
    public var cores: Int?

    public init(id: String, secret: String, name: String, platform: String, capabilities: [String], ffmpegVersion: String? = nil, cores: Int? = nil) {
        self.id = id
        self.secret = secret
        self.name = name
        self.platform = platform
        self.capabilities = capabilities
        self.ffmpegVersion = ffmpegVersion
        self.cores = cores
    }
}

/// What a node's poll answers: its record, and, once, its token.
public struct NodeStatus: Hashable, Sendable, Codable {
    public var node: Node
    public var token: String?

    public init(node: Node, token: String? = nil) {
        self.node = node
        self.token = token
    }
}

/// The identity a node keeps in its own state directory.
public struct NodeIdentity: Hashable, Sendable, Codable {
    public var id: String
    public var secret: String
    public var token: String?

    public init(id: String = UUID().uuidString.lowercased(), secret: String = FileRef.mintSecret(), token: String? = nil) {
        self.id = id
        self.secret = secret
        self.token = token
    }
}
