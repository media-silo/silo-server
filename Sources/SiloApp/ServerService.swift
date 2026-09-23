// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloStore
import Wire

/// The server's identity as the rest of the silo reads it: what it minted, and whether it is in
/// bootstrap — the absence of any operator credential, which is to say no stored credential and
/// no token in the environment.
@Singleton
package final class ServerService: Sendable {
    package let identity: ServerIdentity
    private let config: SiloConfig
    private let credential: OperatorCredential

    @Inject
    package init(identity: ServerIdentity, config: SiloConfig, credential: OperatorCredential) {
        self.identity = identity
        self.config = config
        self.credential = credential
    }

    /// Bootstrap: no operator credential from anywhere. A confirmed setup lands the stored one,
    /// which ends it without a restart.
    package var isInBootstrap: Bool {
        config.operatorToken == nil && credential.current == nil
    }

    /// What the server goes by on the network right now. The identity's name until a setup
    /// renames it — the file next, the advertisement at once, and no restart.
    package var name: String {
        identity.name
    }

    /// The credential a confirmed setup lands, ending bootstrap. The gate already reads it.
    package func land(_ stored: StoredOperatorCredential) throws {
        try credential.install(stored)
    }
}
