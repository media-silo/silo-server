// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloStore
import Synchronization
import Wire

/// The setup window is shut: the server is not in bootstrap, so staging is gone for good.
package struct SetupGone: Error {}

/// The passkey a setup would stage is empty.
package struct EmptyPasskey: Error {}

/// A setup is staged already; its window is still open — the standing stage's deadline is what
/// a refused stager is told, so another console knows how long to wait out.
package struct StagePending: Error {
    package var confirmBy: Date
}

/// Nothing is staged to confirm: the stage expired, was never made, or a restart forgot it.
package struct NothingStaged: Error {}

/// The confirm's bearer is not the staged passkey.
package struct ConfirmRefused: Error {}

/// What the verify route's middleware is told when a live staged passkey asks after itself:
/// the request is pending, and until when — carried as an error because the middleware that
/// answers it speaks raw bytes, not the document's types.
package struct PendingStage: Error {
    package var confirmBy: Date
}

/// The server's identity as the rest of the silo reads it: what it minted, and whether it is in
/// bootstrap — the absence of any operator credential, which is to say no stored credential and
/// no token in the environment. It also holds the one staged setup: in memory only, ten minutes
/// from staging, void the moment its deadline or its confirm passes — nothing of it may outlive
/// a restart, since a staged passkey is not yet a credential.
@Singleton
package final class ServerService: Sendable {
    package let identity: ServerIdentity
    private let config: SiloConfig
    private let credential: OperatorCredential
    private let stageWindow: TimeInterval
    private let now: @Sendable () -> Date
    private let staged: Mutex<PendingSetup?>
    private let confirmedName: Mutex<String?>

    /// The graph's init: production timing — the ten-minute window and the wall clock. The
    /// seams live on the test-facing init below, since the graph can bind neither a closure nor
    /// a bare number.
    @Inject
    package convenience init(identity: ServerIdentity, config: SiloConfig, credential: OperatorCredential) {
        self.init(identity: identity, config: config, credential: credential, stageWindow: 600, now: { .now })
    }

    /// The timing seams, for tests: how long a stage stands, and what "now" is.
    package init(
        identity: ServerIdentity,
        config: SiloConfig,
        credential: OperatorCredential,
        stageWindow: TimeInterval,
        now: @escaping @Sendable () -> Date
    ) {
        self.identity = identity
        self.config = config
        self.credential = credential
        self.stageWindow = stageWindow
        self.now = now
        staged = Mutex(nil)
        confirmedName = Mutex(nil)
    }

    /// Bootstrap: no operator credential from anywhere. A confirmed setup lands the stored one,
    /// which ends it without a restart.
    package var isInBootstrap: Bool {
        config.operatorToken == nil && credential.current == nil
    }

    /// What the server goes by on the network right now. The identity's name until a setup
    /// renames it — the file next, the advertisement at once, and no restart.
    package var name: String {
        confirmedName.withLock { $0 } ?? identity.name
    }

    private struct PendingSetup: Sendable {
        var passkey: String
        var name: String
        var confirmBy: Date
    }

    /// What a staged setup tells its stager: the name it would take and its deadline.
    package struct StagedSetup: Sendable {
        package var name: String
        package var confirmBy: Date
    }

    /// Stages a passkey and name in memory with a deadline ten minutes hence, writing nothing.
    /// The passkey lives only here and only until its confirm or its deadline; a second stage
    /// while the window is open is refused, and an expired stage is void — overwritten, not
    /// extended.
    package func stageSetup(passkey: String, name: String?) throws -> StagedSetup {
        guard isInBootstrap else { throw SetupGone() }
        guard !passkey.isEmpty else { throw EmptyPasskey() }
        return try staged.withLock { current in
            let now = self.now()
            if let pending = current, pending.confirmBy > now { throw StagePending(confirmBy: pending.confirmBy) }
            let pending = PendingSetup(passkey: passkey, name: name ?? self.name, confirmBy: now.addingTimeInterval(stageWindow))
            current = pending
            return StagedSetup(name: pending.name, confirmBy: pending.confirmBy)
        }
    }

    /// Throws `PendingStage` with the stage's deadline when a bearer is the live staged
    /// passkey: the one staged secret is not yet a credential, and the verify route alone
    /// answers it — everywhere else keeps the operator gate.
    package func pendingConfirmBy(bearer: String?) throws {
        let confirmBy = staged.withLock { current -> Date? in
            guard let pending = current, pending.confirmBy > now(), let bearer, !bearer.isEmpty, bearer == pending.passkey else { return nil }
            return pending.confirmBy
        }
        if let confirmBy { throw PendingStage(confirmBy: confirmBy) }
    }

    /// Confirms the staged setup: the bearer's hash and the staged name land in the state
    /// directory, ending bootstrap. The stage is void before anything is written, so a landing
    /// that fails leaves the silo in bootstrap and free to stage anew; a wrong bearer does no
    /// damage — the stage stands. The name is written first: what ends bootstrap is the
    /// credential, so it lands last.
    package func confirmSetup(bearer: String?) throws {
        let pending = try staged.withLock { current -> PendingSetup in
            guard let pending = current, pending.confirmBy > now() else {
                current = nil
                throw NothingStaged()
            }
            guard let bearer, !bearer.isEmpty, bearer == pending.passkey else { throw ConfirmRefused() }
            current = nil
            return pending
        }
        try storeServerIdentity(ServerIdentity(id: identity.id, name: pending.name), in: config.stateDirectory)
        try land(StoredOperatorCredential(passkeyHash: NodeStore.hash(pending.passkey)))
        confirmedName.withLock { $0 = pending.name }
    }

    /// The credential a confirmed setup lands, ending bootstrap. The gate already reads it.
    package func land(_ stored: StoredOperatorCredential) throws {
        try credential.install(stored)
    }
}
