// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloClient
import SiloDiscovery
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The console's engine: discovery merged into the registry, every silo it shows classified
/// exactly one way, and the three flows that change what this Mac holds — staging a bootstrap
/// silo's setup, claiming a reachable silo whose passkey the operator supplies, and forgetting
/// one that has gone quiet. Access is asked, never inferred: the probe against the silo is the
/// verdict, and an unreachable silo renders what was last known of it rather than vanishing —
/// last-known-ness is row data, not another class. An actor because every mutation of the
/// rendered list passes through it, and none of them may interleave.
public actor AdminConsole {
    /// The four classes, and every silo is exactly one. Reachability sets the act vocabulary: a
    /// reachable silo this Mac cannot prove access to gets Claim — never met and refused alike —
    /// and a silo that has gone quiet gets Forget, its last-seen time and last-known access
    /// carried on the row rather than named as states.
    public enum Classification: String, Hashable, Sendable, Codable {
        /// Waiting on its operator; the offered act is to set it up.
        case bootstrap
        /// Reachable, and this Mac's passkey passed the probe; no act offered.
        case withAccess
        /// Reachable, but no passkey this Mac holds passes the probe — first contact, none
        /// stored, or refused is the same situation, so the offered act is to claim it.
        case withoutAccess
        /// Was reachable, now is not; the row carries what was last known, and the offered act
        /// is to forget it.
        case unreachable
    }

    /// A silo as the app renders it.
    public struct Silo: Hashable, Sendable {
        public var id: String
        public var name: String
        public var url: URL
        public var lastSeen: Date
        public var classification: Classification
        /// The last verdict the probe gave while this Mac held a passkey — nil until there was
        /// one. Meaningful on an `unreachable` row, where it is the honest remainder of access.
        public var lastKnownAccess: Bool?
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

    /// This Mac holds no passkey the silo accepts, so its settings cannot be asked or changed; the
    /// next sweep classifies the silo by its probe.
    public struct NoAccess: Error, Hashable {}

    /// The silo refused a settings change, in its own words. Nothing was changed.
    public struct SettingsRefused: Error, Hashable {
        public var reason: String

        public init(reason: String) {
            self.reason = reason
        }
    }

    /// The sheet's payload for a bootstrap silo: a passkey the app will store only once the
    /// stage answers 202, and how much of it the operator may see. A minted passkey is rendered
    /// exactly once, here. `resumingUntil` is set when the Keychain's residue probed as the
    /// live stage's own passkey: the sheet is offered the stage to finish before its deadline,
    /// and the residue — already shown once, at the earlier attempt — is shown never again.
    public struct PreparedSetup: Sendable {
        public enum Presentation: Sendable, Hashable {
            /// Shown once, with an offer to copy, and never in full again.
            case minted(String)
            /// In the Keychain from an attempt whose stage still stands; not reshown.
            case reused
        }

        public var serverID: String
        public var url: URL
        public var presentation: Presentation
        /// Non-nil when the sheet resumes a stage that still stands: when its window shuts.
        public var resumingUntil: Date?
        let passkey: String
    }

    private let registry: SiloRegistry
    private let passkeys: any PasskeyStore
    private let session: URLSession
    private let now: @Sendable () -> Date
    private let browse: @Sendable () async throws -> [DiscoveredSilo]
    private var latest: [Silo] = []

    /// The session's liveness memory per silo: how many sweeps in a row found no contact, and
    /// the class the silo keeps through its first miss. Deliberately not persisted — hysteresis
    /// is a property of this console's vantage, and the registry already holds everything
    /// durable; a fresh session seeds it from the registry's recorded verdicts.
    private struct Liveness {
        var misses: Int
        var held: Classification?
    }

    private var liveness: [String: Liveness] = [:]

    /// The sweep in flight, when one is: refreshes asked for mid-sweep join it rather than
    /// stacking a second pass onto the actor.
    private var sweep: Task<[Silo], Never>?

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
    /// fails the refresh, since a URL is the mechanism and discovery only convenience. One
    /// sweep never overlaps another — a refresh asked for in flight joins the one under way —
    /// and a silo is called unreachable only after two consecutive sweeps find no contact:
    /// hysteresis damps the fall, but contact heals at once.
    @discardableResult
    public func refresh(typedURLs: [URL] = []) async -> [Silo] {
        if let sweep { return await sweep.value }
        let next = Task { await self.performRefresh(typedURLs: typedURLs) }
        sweep = next
        let rows = await next.value
        sweep = nil
        return rows
    }

    /// The body of a sweep, run by `refresh` alone so joining callers share its rows.
    private func performRefresh(typedURLs: [URL]) async -> [Silo] {
        let known = Dictionary(registry.all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // Launch seeding: a silo this session has never reached keeps, through its first miss,
        // the class the registry's recorded verdicts imply — where there is no verdict, there
        // is nothing to hold, and the first miss reads unreachable at once.
        for entry in known.values where liveness[entry.id] == nil {
            let held: Classification? = switch entry.lastKnownAccess {
            case .some(true): .withAccess
            case .some(false): .withoutAccess
            case .none: nil
            }
            liveness[entry.id] = Liveness(misses: 0, held: held)
        }

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
            let (classification, lastKnownAccess) = await classify(info: info, url: url, stored: stored)
            let seenAt = now()
            try? registry.merge(RegisteredSilo(id: info.id, name: info.name, url: url, lastSeen: seenAt, hasStoredPasskey: stored != nil, lastKnownAccess: lastKnownAccess))
            rows.append(Silo(id: info.id, name: info.name, url: url, lastSeen: seenAt, classification: classification, lastKnownAccess: lastKnownAccess))
            liveness[info.id] = Liveness(misses: 0, held: classification)
        }

        let contacted = Set(contacts.map { $0.1.id })
        for ghost in known.values where !contacted.contains(ghost.id) {
            var stance = liveness[ghost.id] ?? Liveness(misses: 0, held: nil)
            stance.misses += 1
            liveness[ghost.id] = stance
            // The first miss holds the class the console last verified — only last-seen stops
            // advancing. The second consecutive miss is the one allowed to call it quiet.
            let classification: Classification = stance.misses == 1 ? stance.held ?? .unreachable : .unreachable
            rows.append(Silo(
                id: ghost.id,
                name: ghost.name,
                url: ghost.url,
                lastSeen: ghost.lastSeen,
                classification: classification,
                lastKnownAccess: ghost.lastKnownAccess
            ))
        }

        latest = rows.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return latest
    }

    /// The reachable-silo classification: bootstrap says so itself, and for the rest the passkey
    /// — probed, never assumed — decides access. Never-yet-met, nothing-stored and
    /// stored-but-refused are all `withoutAccess`, since the console can offer one act for all
    /// of them; the pair returned is the class and the verdict the passkey earned, for the
    /// registry to keep as the row's last-known access.
    private func classify(info: SiloClient.ServerInfo, url: URL, stored: String?) async -> (Classification, lastKnownAccess: Bool?) {
        if info.bootstrap { return (.bootstrap, nil) }
        guard let stored else { return (.withoutAccess, nil) }
        return await hasAccess(url: url, passkey: stored) ? (.withAccess, true) : (.withoutAccess, false)
    }

    /// The probe: `GET /v1/operator` with the passkey as bearer, the verify-access route whose
    /// only job is this question — `active` is access and everything else is not: a `pending`
    /// answer names a staged passkey, and a stage is not yet a credential — without the node
    /// subsystem's health saying anything a refused credential didn't.
    private func hasAccess(url: URL, passkey: String) async -> Bool {
        (try? await SiloClient(baseURL: url, token: passkey, session: session).verifyAccess()) == .active
    }

    // MARK: - Setup

    /// Prepares the setup sheet for a bootstrap silo. A Keychain residue is probed first: the
    /// live stage's own passkey — answered `pending`, with its deadline — prepares a resume
    /// the sheet offers, the confirm sent only on the operator's word and never the engine's
    /// own; a refused residue is dead weight, dropped for a fresh mint whose write-ahead
    /// overwrites it. No residue mints straight away.
    public func prepareSetup(_ silo: Silo) async throws -> PreparedSetup {
        if let existing = passkeys.passkey(for: silo.id),
           case .pending(let confirmBy)? = try await probeResidue(existing, at: silo.url) {
            return PreparedSetup(serverID: silo.id, url: silo.url, presentation: .reused, resumingUntil: confirmBy, passkey: existing)
        }
        let minted = Passkey.mint()
        return PreparedSetup(serverID: silo.id, url: silo.url, presentation: .minted(minted), resumingUntil: nil, passkey: minted)
    }

    /// The residue's probe, a refusal read as a dead passkey — its stage ran out, was
    /// confirmed, or was never this silo's. Any other failure of the wire surfaces.
    private func probeResidue(_ passkey: String, at url: URL) async throws -> SiloClient.OperatorStatus? {
        do {
            return try await SiloClient(baseURL: url, token: passkey, session: session).verifyAccess()
        } catch SiloClientError.status(401, _) {
            return nil
        }
    }

    /// Plays the pair once the operator confirms the sheet — unless the sheet resumed a stage
    /// that still stands: then the stage was the earlier attempt's play and only the confirm
    /// remains, the standing stage keeping the name it was staged with. Otherwise stage, then
    /// the passkey into the Keychain, then the confirm — so the silo cannot become configured
    /// while the console holds no copy. On 201 the silo is recorded and classifies with
    /// access; a 410 ends the flow with the minted passkey discarded and the silence
    /// classified by probe, and a 409 tells the operator whose window to wait out, storing
    /// nothing.
    @discardableResult
    public func runSetup(_ prepared: PreparedSetup, name: String?) async throws -> Silo {
        let client = SiloClient(baseURL: prepared.url, session: session)
        if prepared.resumingUntil == nil {
            do {
                _ = try await client.setup(name: name, passkey: prepared.passkey)
            } catch SiloClientError.conflict(let until) {
                throw SetupRefusal.stagedElsewhere(until: until)
            } catch SiloClientError.status(410, _) {
                await reclassify(prepared.serverID, at: prepared.url)
                throw SetupRefusal.noLongerInBootstrap
            }
        }

        passkeys.store(prepared.passkey, for: prepared.serverID)
        let info = try await client.confirmSetup(bearer: prepared.passkey)

        let row = Silo(id: prepared.serverID, name: info.name, url: prepared.url, lastSeen: now(), classification: .withAccess, lastKnownAccess: true)
        try? registry.merge(RegisteredSilo(id: row.id, name: row.name, url: row.url, lastSeen: row.lastSeen, hasStoredPasskey: true, lastKnownAccess: true))
        render(row)
        return row
    }

    /// What the silo is once someone else finished setup: classified by its probe, with the
    /// Keychain's holdings untouched and the registry told fresh contact happened.
    private func reclassify(_ serverID: String, at url: URL) async {
        let stored = passkeys.passkey(for: serverID)
        let lastKnownAccess: Bool? = if let stored { await hasAccess(url: url, passkey: stored) } else { nil }
        let prior = registry.entry(for: serverID)
        let name = (try? await SiloClient(baseURL: url, session: session).server())?.name ?? prior?.name ?? serverID
        let row = Silo(id: serverID, name: name, url: url, lastSeen: now(), classification: lastKnownAccess == true ? .withAccess : .withoutAccess, lastKnownAccess: lastKnownAccess)
        try? registry.merge(RegisteredSilo(id: serverID, name: name, url: url, lastSeen: row.lastSeen, hasStoredPasskey: stored != nil, lastKnownAccess: lastKnownAccess))
        render(row)
    }

    // MARK: - Claim

    /// Claims a silo the operator types a passkey for, in the only order that is safe: the
    /// probe first, and only a passing probe stores. A refused passkey keeps nothing and
    /// changes nothing — `pending` is a refusal here too, a staged passkey not yet being a
    /// credential.
    @discardableResult
    public func claim(_ silo: Silo, passkey: String) async throws -> Silo {
        let status: SiloClient.OperatorStatus
        do {
            status = try await SiloClient(baseURL: silo.url, token: passkey, session: session).verifyAccess()
        } catch SiloClientError.status(401, _) {
            throw ClaimRefused()
        }
        guard status == .active else { throw ClaimRefused() }

        passkeys.store(passkey, for: silo.id)
        let row = Silo(id: silo.id, name: silo.name, url: silo.url, lastSeen: now(), classification: .withAccess, lastKnownAccess: true)
        try? registry.merge(RegisteredSilo(id: row.id, name: row.name, url: row.url, lastSeen: row.lastSeen, hasStoredPasskey: true, lastKnownAccess: true))
        render(row)
        return row
    }

    // MARK: - Settings

    /// A with-access silo's settings, asked with the passkey this Mac holds for it.
    public func settings(of silo: Silo) async throws -> SiloClient.SettingsReport {
        try await withOperator(silo) { try await $0.settings() }
    }

    /// Changes a with-access silo's editable settings, all of the patch or none of it. A refusal
    /// comes back as `SettingsRefused` in the silo's own words; a rename is rendered on the row and
    /// kept in the registry, so the console calls the silo by its new name before the next sweep.
    @discardableResult
    public func updateSettings(of silo: Silo, _ patch: SiloClient.SettingsPatch) async throws -> SiloClient.SettingsReport {
        let report: SiloClient.SettingsReport
        do {
            report = try await withOperator(silo) { try await $0.updateSettings(patch) }
        } catch SiloClientError.status(400, let body) {
            struct Problem: Decodable { var detail: String }
            throw SettingsRefused(reason: (try? SiloClient.decoder.decode(Problem.self, from: Data(body.utf8)))?.detail ?? body)
        }
        if report.editable.name != silo.name, let current = latest.first(where: { $0.id == silo.id }) {
            var renamed = current
            renamed.name = report.editable.name
            if let entry = registry.entry(for: silo.id) {
                try? registry.merge(RegisteredSilo(id: entry.id, name: renamed.name, url: entry.url, lastSeen: entry.lastSeen, hasStoredPasskey: entry.hasStoredPasskey, lastKnownAccess: entry.lastKnownAccess))
            }
            render(renamed)
        }
        return report
    }

    /// Runs `call` with the passkey this Mac holds for `silo` as its bearer; no passkey, or one the
    /// silo refuses, is `NoAccess`.
    private func withOperator<T: Sendable>(_ silo: Silo, _ call: @Sendable (SiloClient) async throws -> T) async throws -> T {
        guard let passkey = passkeys.passkey(for: silo.id) else { throw NoAccess() }
        do {
            return try await call(SiloClient(baseURL: silo.url, token: passkey, session: session))
        } catch SiloClientError.status(401, _) {
            throw NoAccess()
        }
    }

    // MARK: - Rulesets

    /// A ruleset opened: its summary and branches, and one version's document as the silo stored it,
    /// with the silo's reading of it.
    public struct OpenedRuleset: Hashable, Sendable {
        public var summary: SiloClient.RulesetSummary
        public var branches: [SiloClient.Branch]
        public var document: SiloClient.RulesetDocument
    }

    /// One library's out-of-date presentations, as the background check has found them so far.
    public struct LibraryOutOfDate: Hashable, Sendable {
        public var library: String
        public var report: SiloClient.OutOfDateReport
    }

    /// The rulesets a with-access silo holds, each with every version.
    public func rulesets(of silo: Silo) async throws -> [SiloClient.RulesetSummary] {
        try await withOperator(silo) { try await $0.rulesets() }
    }

    /// Opens a ruleset at a version, or at its standard's head when none is named: the version the
    /// library's applications take unless they name a branch.
    public func open(ruleset name: String, version: Int? = nil, of silo: Silo) async throws -> OpenedRuleset {
        try await withOperator(silo) { client in
            guard let summary = try await client.rulesets().first(where: { $0.name == name }) else {
                throw SiloClientError.status(404, "no ruleset \(name)")
            }
            let branches = try await client.branches(of: name)
            let document = try await client.ruleset(named: name, version: version ?? summary.standard ?? summary.version)
            return OpenedRuleset(summary: summary, branches: branches, document: document)
        }
    }

    /// Each library's out-of-date presentations, in the order the silo lists its libraries.
    public func outOfDate(of silo: Silo) async throws -> [LibraryOutOfDate] {
        try await withOperator(silo) { client in
            var reports: [LibraryOutOfDate] = []
            for library in try await client.settings().readOnly.libraries {
                reports.append(LibraryOutOfDate(library: library.id, report: try await client.outOfDate(in: library.id)))
            }
            return reports
        }
    }

    // MARK: - Changing rulesets

    /// What the silo made of a draft's text: its reading, or its refusal in its own words.
    public enum DraftCheck: Hashable, Sendable {
        case reading(SiloClient.RulesetReading)
        case refused(String)
    }

    /// Checks a draft with the silo as a store would, storing nothing.
    public func check(_ draft: Draft, of silo: Silo) async throws -> DraftCheck {
        do {
            return .reading(try await withOperator(silo) { try await $0.check(ruleset: draft.text, as: draft.ruleset) })
        } catch SiloClientError.status(400, let body) {
            return .refused(Self.detail(body))
        }
    }

    /// What a draft would put out of date were it stored on its base's branch. A new ruleset made
    /// nothing, so it puts nothing out of date.
    public func impact(of draft: Draft, of silo: Silo) async throws -> [SiloClient.OutOfDatePresentation] {
        guard let base = draft.base else { return [] }
        return try await withOperator(silo) { try await $0.impact(ofDraft: draft.text, basedOn: base, of: draft.ruleset) }
    }

    /// Where a draft is stored.
    public enum StoreTarget: Hashable, Sendable {
        /// Its base's branch, or the standard for a new ruleset.
        case baseBranch
        /// Another branch of the ruleset, at that branch's head.
        case branch(String)
        /// A branch started from the base, which must be on the standard.
        case newBranch(String)
    }

    /// How a store ended: the version the silo gave the draft, which ends it; or another version
    /// that landed on the branch first, which keeps it, for the operator to re-base or discard.
    public enum StoreOutcome: Hashable, Sendable {
        case stored(SiloClient.RulesetDocument)
        case landedFirst(SiloClient.RulesetDocument)
    }

    /// The silo refused the store for something other than a version landing first, in its words.
    public struct StoreRefused: Error, Hashable {
        public var reason: String
    }

    /// Stores a draft, naming as `basedOn` the head of the branch it goes to as the draft knows it:
    /// its base, on its base's branch; another branch's head as the silo lists it; or the base, for a
    /// branch started from it. The console never merges: a version that landed first is fetched and
    /// handed back with the draft kept.
    public func store(_ draft: Draft, to target: StoreTarget, of silo: Silo) async throws -> StoreOutcome {
        try await withOperator(silo) { client in
            var branch: String?
            var basedOn: Int
            switch target {
            case .baseBranch:
                branch = draft.baseBranch
                basedOn = draft.base ?? 0
            case .branch(let name):
                guard let head = try await client.branches(of: draft.ruleset).first(where: { $0.name == name })?.head else {
                    throw StoreRefused(reason: "\(draft.ruleset) has no branch \(name)")
                }
                branch = name
                basedOn = head
            case .newBranch(let name):
                guard let base = draft.base, draft.baseBranch == nil || draft.baseBranch == "standard" else {
                    throw StoreRefused(reason: "a branch is started from a version of the standard")
                }
                do {
                    _ = try await client.startBranch(name, of: draft.ruleset, from: base)
                } catch SiloClientError.status(let status, let body) where status == 400 || status == 409 {
                    throw StoreRefused(reason: Self.detail(body))
                }
                branch = name
                basedOn = base
            }
            do {
                return .stored(try await client.store(ruleset: draft.text, as: draft.ruleset, branch: branch, upToDateWith: draft.upToDateWith, basedOn: basedOn))
            } catch SiloClientError.status(409, let body) {
                let line = branch ?? "standard"
                guard let head = try await client.branches(of: draft.ruleset).first(where: { $0.name == line })?.head, head != basedOn else {
                    throw StoreRefused(reason: Self.detail(body))
                }
                return .landedFirst(try await client.ruleset(named: draft.ruleset, version: head))
            } catch SiloClientError.status(400, let body) {
                throw StoreRefused(reason: Self.detail(body))
            }
        }
    }

    /// What promoting a branch would put out of date, as the silo resolves it on request.
    public func impact(ofBranch branch: String, of ruleset: String, on silo: Silo) async throws -> [SiloClient.OutOfDatePresentation] {
        try await withOperator(silo) { try await $0.impact(ofBranch: branch, of: ruleset) }
    }

    /// A promotion the silo refused: the standard versions the branch has not taken in, and the
    /// branch's base they are read against.
    public struct PromotionRefused: Error, Hashable {
        public var reason: String
        public var notTakenIn: [SiloClient.RulesetDocument]
        public var base: SiloClient.RulesetDocument?
    }

    /// Promotes a branch, answering the standard's new version. A refusal names the standard versions
    /// the branch has not taken in, with their documents and its base's, so that each can be read for
    /// how it differs before a draft taking them in is stored on the branch.
    public func promote(_ branch: String, of ruleset: String, on silo: Silo) async throws -> SiloClient.RulesetDocument {
        try await withOperator(silo) { client in
            do {
                let promoted = try await client.promote(branch, of: ruleset)
                return try await client.ruleset(named: ruleset, version: promoted.version)
            } catch SiloClientError.status(409, let body) {
                let branches = try await client.branches(of: ruleset)
                let line = branches.first { $0.name == branch }
                let summary = try await client.rulesets().first { $0.name == ruleset }
                let since = line?.upToDateWith ?? line?.base ?? 0
                let missed = (summary?.versions ?? []).filter { $0.branch == "standard" && $0.version > since }.map(\.version)
                var documents: [SiloClient.RulesetDocument] = []
                for version in missed { documents.append(try await client.ruleset(named: ruleset, version: version)) }
                let base = try await line?.base.asyncMap { try await client.ruleset(named: ruleset, version: $0) }
                throw PromotionRefused(reason: Self.detail(body), notTakenIn: documents, base: base)
            }
        }
    }

    /// The libraries a with-access silo lists, each with its standard.
    public func libraries(of silo: Silo) async throws -> [SiloClient.Library] {
        try await withOperator(silo) { try await $0.libraries() }
    }

    /// Names a library's standard, or clears it with nil; the library as the silo answers.
    public func setStandard(_ ruleset: String?, of library: String, on silo: Silo) async throws -> SiloClient.Library {
        do {
            return try await withOperator(silo) { try await $0.setStandard(ruleset, of: library) }
        } catch SiloClientError.status(let status, let body) where status == 400 || status == 404 {
            throw SettingsRefused(reason: Self.detail(body).isEmpty ? "no ruleset \(ruleset ?? "")" : Self.detail(body))
        }
    }

    /// A problem's detail, or the body as it came.
    private static func detail(_ body: String) -> String {
        struct Problem: Decodable { var detail: String }
        return (try? SiloClient.decoder.decode(Problem.self, from: Data(body.utf8)))?.detail ?? body
    }

    // MARK: - Forget

    /// Forgets a silo outright: its passkey out of this Mac's stores, its entry out of the
    /// registry, its row out of the console. The act for a silo that has gone quiet — should
    /// it answer again, it arrives as never met.
    public func forget(_ silo: Silo) {
        passkeys.remove(for: silo.id)
        try? registry.remove(silo.id)
        liveness.removeValue(forKey: silo.id)
        latest.removeAll { $0.id == silo.id }
    }

    /// Replaces the silo's row after a flow verified fresh contact — the ledger resets with
    /// it, the class rendered here being the new verdict the next miss would hold.
    private func render(_ row: Silo) {
        liveness[row.id] = Liveness(misses: 0, held: row.classification)
        if let index = latest.firstIndex(where: { $0.id == row.id }) {
            latest[index] = row
        } else {
            latest.append(row)
        }
        latest.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

extension Optional {
    /// `map`, for a transform that suspends.
    fileprivate func asyncMap<T>(_ transform: (Wrapped) async throws -> T) async rethrows -> T? {
        guard let self else { return nil }
        return try await transform(self)
    }
}
