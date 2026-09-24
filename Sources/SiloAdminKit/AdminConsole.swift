// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloClient
import SiloDiscovery
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The console's engine: discovery merged into the registry, every silo it shows classified
/// exactly one way, and the two flows that change what this Mac holds — staging a bootstrap
/// silo's setup, and claiming a silo whose passkey the operator supplies. Access is asked,
/// never inferred: the probe against the silo is the verdict, and an unreachable silo renders
/// its last-known state rather than vanishing. An actor because every mutation of the rendered
/// list passes through it, and none of them may interleave.
public actor AdminConsole {
    /// The four classes, and every silo is exactly one. `lastKnown` is not a class: a silo that
    /// stops answering keeps whichever of the seen pair it last earned, with its last-seen time.
    public enum Classification: String, Hashable, Sendable, Codable {
        /// Waiting on its operator; gets the setup flow.
        case bootstrap
        /// Reachable, but this Mac has never met it; the offered act is to claim it.
        case unseen
        /// Met, and this Mac holds a passkey the probe passes.
        case seenWithAccess
        /// Met, but no passkey is stored, or the stored one is refused; the offered act is to enter one.
        case seenWithoutAccess
    }

    /// A silo as the app renders it.
    public struct Silo: Hashable, Sendable {
        public var id: String
        public var name: String
        public var url: URL
        public var lastSeen: Date
        public var classification: Classification
    }

    /// The two ways the server can say no to staging a setup. `stagedElsewhere` carries the
    /// standing stage's deadline, so the operator is told how long there is to wait out;
    /// `noLongerInBootstrap` means someone finished first — the silo is classified by what its
    /// probe says and the minted passkey is discarded.
    public enum SetupRefusal: Error, Hashable {
        case stagedElsewhere(until: Date)
        case noLongerInBootstrap
    }

    /// The passkey the operator supplied is not one the silo accepts. Nothing is stored.
    public struct ClaimRefused: Error, Hashable {}

    /// The sheet's payload for a bootstrap silo: a passkey the app will store only once the
    /// stage answers 202, and how much of it the operator may see. A minted passkey is rendered
    /// exactly once, here; the residue of an interrupted attempt already had its once.
    public struct PreparedSetup: Sendable {
        public enum Presentation: Sendable, Hashable {
            /// Shown once, with an offer to copy, and never in full again.
            case minted(String)
            /// Already in the Keychain from an attempt whose confirm never landed; not reshown.
            case reused
        }

        public var serverID: String
        public var url: URL
        public var presentation: Presentation
        let passkey: String
    }

    private let registry: SiloRegistry
    private let passkeys: any PasskeyStore
    private let session: URLSession
    private let now: @Sendable () -> Date
    private let browse: @Sendable () async throws -> [DiscoveredSilo]
    private var latest: [Silo] = []

    public init(
        registry: SiloRegistry = SiloRegistry(),
        passkeys: any PasskeyStore,
        session: URLSession = .shared,
        now: @escaping @Sendable () -> Date = { .now },
        browse: (@Sendable () async throws -> [DiscoveredSilo])? = nil
    ) {
        self.registry = registry
        self.passkeys = passkeys
        self.session = session
        self.now = now
        self.browse = browse ?? { try await Discovery.browse() }
    }

    /// The silos as the last refresh or flow left them.
    public var silos: [Silo] { latest }

    /// Browses Bonjour and resolves any typed-in addresses through `GET /v1/server`, merging
    /// each contact into the registry and reclassifying what it finds. A silo that neither
    /// registers nor answers does not appear at all; Bonjour being missing or broken never
    /// fails the refresh, since a URL is the mechanism and discovery only convenience.
    @discardableResult
    public func refresh(typedURLs: [URL] = []) async -> [Silo] {
        let known = Dictionary(registry.all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let discovered = (try? await browse()) ?? []
        var candidates: [URL] = []
        for url in discovered.map(\.url) + typedURLs where !candidates.contains(url) {
            candidates.append(url)
        }

        let session = session
        let contacts = await withTaskGroup(of: (URL, SiloClient.ServerInfo)?.self) { group in
            for url in candidates {
                group.addTask {
                    guard let info = try? await SiloClient(baseURL: url, session: session).server() else { return nil }
                    return (url, info)
                }
            }
            var reached: [(URL, SiloClient.ServerInfo)] = []
            for await contact in group.compactMap({ $0 }) { reached.append(contact) }
            return reached
        }

        var rows: [Silo] = []
        for (url, info) in contacts {
            let stored = passkeys.passkey(for: info.id)
            let classification = await classify(info: info, url: url, prior: known[info.id], stored: stored)
            let seenAt = now()
            try? registry.merge(RegisteredSilo(id: info.id, name: info.name, url: url, lastSeen: seenAt, hasStoredPasskey: stored != nil))
            rows.append(Silo(id: info.id, name: info.name, url: url, lastSeen: seenAt, classification: classification))
        }

        let contacted = Set(contacts.map { $0.1.id })
        for ghost in known.values where !contacted.contains(ghost.id) {
            rows.append(Silo(
                id: ghost.id,
                name: ghost.name,
                url: ghost.url,
                lastSeen: ghost.lastSeen,
                classification: ghost.hasStoredPasskey ? .seenWithAccess : .seenWithoutAccess
            ))
        }

        latest = rows.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return latest
    }

    /// The reachable-silo classification: bootstrap says so itself; the registry decides met
    /// or new; the passkey — probed, never assumed — decides access. A first contact is
    /// `unseen` this pass and `seen` from the next, because the merge follows the class.
    private func classify(info: SiloClient.ServerInfo, url: URL, prior: RegisteredSilo?, stored: String?) async -> Classification {
        if info.bootstrap { return .bootstrap }
        guard prior != nil else { return .unseen }
        guard let stored else { return .seenWithoutAccess }
        return await hasAccess(url: url, passkey: stored) ? .seenWithAccess : .seenWithoutAccess
    }

    /// The probe: `GET /v1/nodes` with the passkey as bearer. 200 is access and everything
    /// else is not — asking is the only honest test.
    private func hasAccess(url: URL, passkey: String) async -> Bool {
        (try? await SiloClient(baseURL: url, token: passkey, session: session).nodes()) != nil
    }

    // MARK: - Setup

    /// Prepares the setup sheet for a bootstrap silo: mints a passkey to show once, or reuses
    /// the one an earlier attempt left in the Keychain — which is shown no second time.
    public func prepareSetup(_ silo: Silo) throws -> PreparedSetup {
        if let existing = passkeys.passkey(for: silo.id) {
            return PreparedSetup(serverID: silo.id, url: silo.url, presentation: .reused, passkey: existing)
        }
        let minted = Passkey.mint()
        return PreparedSetup(serverID: silo.id, url: silo.url, presentation: .minted(minted), passkey: minted)
    }

    /// Plays the pair in order once the operator confirms the sheet: stage, then the passkey
    /// into the Keychain, then the confirm — so the silo cannot become configured while the
    /// console holds no copy. On 201 the silo is recorded and classifies seen, has access;
    /// a 410 ends the flow with the minted passkey discarded and the silence classified by
    /// probe, and a 409 tells the operator whose window to wait out, storing nothing.
    @discardableResult
    public func runSetup(_ prepared: PreparedSetup, name: String?) async throws -> Silo {
        let client = SiloClient(baseURL: prepared.url, session: session)
        do {
            _ = try await client.setup(name: name, passkey: prepared.passkey)
        } catch SiloClientError.conflict(let until) {
            throw SetupRefusal.stagedElsewhere(until: until)
        } catch SiloClientError.status(410, _) {
            await reclassify(prepared.serverID, at: prepared.url)
            throw SetupRefusal.noLongerInBootstrap
        }

        passkeys.store(prepared.passkey, for: prepared.serverID)
        let info = try await client.confirmSetup(bearer: prepared.passkey)

        let row = Silo(id: prepared.serverID, name: info.name, url: prepared.url, lastSeen: now(), classification: .seenWithAccess)
        try? registry.merge(RegisteredSilo(id: row.id, name: row.name, url: row.url, lastSeen: row.lastSeen, hasStoredPasskey: true))
        render(row)
        return row
    }

    /// What the silo is once someone else finished setup: classified by its probe, with the
    /// Keychain's holdings untouched and the registry told fresh contact happened.
    private func reclassify(_ serverID: String, at url: URL) async {
        let stored = passkeys.passkey(for: serverID)
        let access = if let stored { await hasAccess(url: url, passkey: stored) } else { false }
        let prior = registry.entry(for: serverID)
        let name = (try? await SiloClient(baseURL: url, session: session).server())?.name ?? prior?.name ?? serverID
        let row = Silo(id: serverID, name: name, url: url, lastSeen: now(), classification: access ? .seenWithAccess : .seenWithoutAccess)
        try? registry.merge(RegisteredSilo(id: serverID, name: name, url: url, lastSeen: row.lastSeen, hasStoredPasskey: stored != nil))
        render(row)
    }

    // MARK: - Claim

    /// Claims a silo the operator types a passkey for, in the only order that is safe: the
    /// probe first, and only a passing probe stores. A refused passkey keeps nothing and
    /// changes nothing.
    @discardableResult
    public func claim(_ silo: Silo, passkey: String) async throws -> Silo {
        do {
            _ = try await SiloClient(baseURL: silo.url, token: passkey, session: session).nodes()
        } catch SiloClientError.status(401, _) {
            throw ClaimRefused()
        }

        passkeys.store(passkey, for: silo.id)
        let row = Silo(id: silo.id, name: silo.name, url: silo.url, lastSeen: now(), classification: .seenWithAccess)
        try? registry.merge(RegisteredSilo(id: row.id, name: row.name, url: row.url, lastSeen: row.lastSeen, hasStoredPasskey: true))
        render(row)
        return row
    }

    private func render(_ row: Silo) {
        if let index = latest.firstIndex(where: { $0.id == row.id }) {
            latest[index] = row
        } else {
            latest.append(row)
        }
        latest.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
