// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

#if canImport(SwiftUI)
import AppKit
import SwiftUI
import SiloAdminKit
import SiloClient

/// The operator's console: a window over `AdminConsole`, and thin on purpose — the kit owns the
/// registry, the passkeys and the flows; the shell renders what the engine handed back and asks
/// it for the next thing. The passkey passes through exactly one view, the setup sheet, and
/// only when it was minted this attempt.
@main
struct SiloAdminApp: App {
    @State private var model: ConsoleModel

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "media-silo/SiloAdmin", directoryHint: .isDirectory)
        let console = AdminConsole(
            registry: SiloRegistry(file: folder.appending(path: "registry.json", directoryHint: .notDirectory)),
            drafts: DraftStore(file: folder.appending(path: "drafts.json", directoryHint: .notDirectory)),
            containerDrafts: ContainerDraftStore(
                file: folder.appending(path: "container-drafts.json", directoryHint: .notDirectory)
            ),
            passkeys: KeychainPasskeyStore()
        )
        _model = State(initialValue: ConsoleModel(console: console))

        // A bare executable earns no menu bar of its own: menus, the app name and Quit all
        // belong to the regular activation policy, which an unpacked binary never takes.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
    }

    var body: some Scene {
        Window("SiloAdmin", id: "console") {
            ConsoleView(model: model)
                .frame(minWidth: 640, minHeight: 380)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Silo by Address…") { model.addingByAddress = true }
                    .keyboardShortcut("A", modifiers: [.command, .shift])
            }
        }
    }
}

extension AdminConsole.Silo: Identifiable {}

extension AdminConsole.PreparedSetup: Identifiable {
    public var id: String { serverID }
}

/// The engine at the window's cadence: the rendered rows, the address being typed, and the
/// transient state of the sheets and alerts. Main-actor because the views are; every hand-off to the
/// console suspends into the actor and comes back with rows to publish.
@MainActor @Observable
final class ConsoleModel {
    let console: AdminConsole

    private(set) var silos: [AdminConsole.Silo] = []
    var addedAddresses: [String] = []
    var selected: Set<AdminConsole.Silo.ID> = []
    var addingByAddress = false
    var prepared: AdminConsole.PreparedSetup?
    var claimTarget: AdminConsole.Silo?
    var forgetTarget: AdminConsole.Silo?
    var refusal: Refusal?
    /// The settings last read or written for a silo, by its id: what the detail pane shows.
    private(set) var settings: [AdminConsole.Silo.ID: SiloClient.SettingsReport] = [:]
    /// Which part of a with-access silo the detail shows.
    var section: DetailSection = .settings
    /// The rulesets last read for a silo, by its id.
    private(set) var rulesets: [AdminConsole.Silo.ID: [SiloClient.RulesetSummary]] = [:]
    /// The ruleset open for a silo, by its id, at the version chosen.
    private(set) var opened: [AdminConsole.Silo.ID: AdminConsole.OpenedRuleset] = [:]
    /// Each library's out-of-date presentations as last read for a silo, by its id.
    private(set) var outOfDate: [AdminConsole.Silo.ID: [AdminConsole.LibraryOutOfDate]] = [:]
    /// The drafts this Mac keeps for a silo, by its id: the draft store's, as it last gave them, with
    /// the open draft's latest keystrokes, which reach the store a moment after the operator stops.
    private(set) var drafts: [AdminConsole.Silo.ID: [Draft]] = [:]
    /// The draft open in the editor for a silo, by its id.
    private(set) var editing: [AdminConsole.Silo.ID: Draft.ID] = [:]
    /// What the silo last made of each draft's text.
    private(set) var draftChecks: [Draft.ID: AdminConsole.DraftCheck] = [:]
    private var checking: [Draft.ID: Task<Void, Never>] = [:]
    /// How long after the last keystroke a draft is saved and checked.
    let checkDelay: Duration
    /// Whether the editor shows a draft in the form or as its text.
    var draftView: DraftView = .form
    /// The review before a store, when one is open.
    var review: Review?
    /// A promotion being considered, when one is.
    var promotion: Promotion?
    /// The libraries last read for a silo, each with its standard.
    private(set) var libraries: [AdminConsole.Silo.ID: [SiloClient.Library]] = [:]
    /// Each library's last walk as last read for a silo, by the library's id.
    private(set) var lastWalks: [AdminConsole.Silo.ID: [String: SiloClient.LastWalk]] = [:]
    /// A branch's version being tried, while its bindings are chosen.
    var trying: Trying?
    /// The containers at the top of each library as last read for a silo, by its id, then the library.
    private(set) var containerRoots: [AdminConsole.Silo.ID: [String: [SiloClient.ContainerSummary]]] = [:]
    /// Each container as last read, by the silo, the library and its id: the browser's tree reads its
    /// children from here, and the detail the container itself.
    private(set) var containers: [ContainerKey: AdminConsole.OpenedContainer] = [:]
    /// What the Libraries section shows for a silo, by its id: a library, or a container in one.
    var browsed: [AdminConsole.Silo.ID: Browsed] = [:]
    /// The container drafts this Mac keeps for a silo, with the open one's latest keystrokes.
    private(set) var containerDrafts: [AdminConsole.Silo.ID: [ContainerDraft]] = [:]
    /// The container draft open in the editor for a silo, by its id.
    private(set) var editingContainer: [AdminConsole.Silo.ID: ContainerDraft.ID] = [:]
    /// What the silo's dry run last made of each container draft.
    private(set) var containerChecks: [ContainerDraft.ID: AdminConsole.ContainerCheck] = [:]
    private var checkingContainer: [ContainerDraft.ID: Task<Void, Never>] = [:]
    /// The review before a container draft is stored, when one is open.
    var containerReview: ContainerReview?
    /// The folder on this Mac named as the clone of smddb's data repository, kept between launches.
    var smddbFolder: URL?
    /// Why the clone cannot be read, in words, when it cannot; nil when it can.
    var smddbProblem: String?
    /// How each container opened stands against smddb's record, as last compared.
    var standings: [ContainerKey: AdminConsole.Standing] = [:]
    /// An import from smddb being chosen, when one is.
    var importing: Importing?
    /// A new container being named, when one is.
    var newContainer: NewContainer?
    /// A container being proposed to smddb, when one is.
    var proposing: Proposing?
    /// The trial jobs this console started for a silo, by its id, as the silo last had them.
    private(set) var trialJobs: [AdminConsole.Silo.ID: [AdminConsole.TrialJob]] = [:]
    /// What starting trials could not do, binding by binding, in the silo's words.
    private(set) var trialRefusals: [AdminConsole.Silo.ID: [String]] = [:]
    /// The tried trials of the open version's branch, each beside what its binding placed.
    private(set) var trials: [AdminConsole.Silo.ID: [AdminConsole.TrialComparison]] = [:]

    /// A branch's version to try, and the bindings to try it on: those its impact lists offered
    /// first, and any other the operator names.
    init(console: AdminConsole, checkDelay: Duration = .milliseconds(400)) {
        self.console = console
        self.checkDelay = checkDelay
        smddbFolder = UserDefaults.standard.url(forKey: Self.smddbFolderKey)
    }

    /// Browses, resolves every added address, and republishes the rows. An added address that
    /// does not parse is skipped, not an error to report.
    func refresh() async {
        var urls: [URL] = []
        for entered in addedAddresses {
            let trimmed = entered.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let candidate = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
            if let url = URL(string: candidate), url.host != nil { urls.append(url) }
        }
        silos = await console.refresh(typedURLs: urls)
        await refreshSection()
    }

    /// What the selected silo's detail shows, read again at the console's cadence, so that a version
    /// stored or a check that moved on elsewhere arrives without the operator asking.
    private func refreshSection() async {
        guard let target = selected.single, let silo = silos.first(where: { $0.id == target }),
            silo.classification == .withAccess
        else { return }
        switch section {
        case .settings: break
        // The walks move on by themselves, and a library added or removed elsewhere changes the
        // settings, so both are read again; and a container changed elsewhere, by an edit or a walk,
        // arrives with its new digest, which is what marks a draft behind.
        case .libraries:
            await readClone()
            await loadSettings(for: silo)
            await loadLibraries(for: silo)
            await loadContainers(for: silo)
            for key in containers.keys where key.silo == silo.id { await open(key) }
        case .rulesets:
            await loadRulesets(for: silo)
            if let current = opened[silo.id] {
                await open(ruleset: current.summary.name, version: current.document.version, of: silo)
            }
            await loadTrials(for: silo)
        case .outOfDate: await loadOutOfDate(for: silo)
        }
    }

    /// The dialog's confirm: the address joins the kept list, so it answers every refresh from
    /// now on, and the refresh happens on the spot.
    func addAddress(_ entered: String) {
        let trimmed = entered.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !addedAddresses.contains(trimmed) else { return }
        addedAddresses.append(trimmed)
        refreshTask()
    }

    private func refreshTask() {
        Task { await refresh() }
    }

    func prepareSetup(for silo: AdminConsole.Silo) async {
        do {
            prepared = try await console.prepareSetup(silo)
        } catch {
            refusal = .unreachable
        }
    }

    /// Confirms the sheet: plays the pair through the engine; the sheet, and with it the one
    /// rendering of a minted passkey, is already gone. The setup arrives as an argument because
    /// the sheet's own dismissal has cleared `prepared` by the time this runs.
    func runSetup(_ prepared: AdminConsole.PreparedSetup, name: String?) async {
        self.prepared = nil
        do {
            _ = try await console.runSetup(prepared, name: name?.isEmpty == true ? nil : name)
            silos = await console.silos
        } catch AdminConsole.SetupRefusal.stagedElsewhere(let until) {
            refusal = .stagedElsewhere(until: until)
        } catch AdminConsole.SetupRefusal.noLongerInBootstrap {
            silos = await console.silos
            refusal = .noLongerInBootstrap
        } catch {
            silos = await console.silos
            refusal = .unreachable
        }
    }

    /// Hands the operator's passkey to the engine; the engine's probe is the verdict, and a
    /// refusal keeps the sheet open so a mistyped group can be fixed.
    func claim(_ silo: AdminConsole.Silo, passkey: String) async -> ClaimOutcome {
        do {
            _ = try await console.claim(silo, passkey: passkey)
            silos = await console.silos
            claimTarget = nil
            return .claimed
        } catch is AdminConsole.ClaimRefused {
            return .refused
        } catch {
            silos = await console.silos
            claimTarget = nil
            refusal = .unreachable
            return .failed
        }
    }

    /// Reads a with-access silo's settings for the detail pane. A failure leaves the last reading
    /// in place; the next sweep says how the Mac stands with the silo.
    func loadSettings(for silo: AdminConsole.Silo) async {
        if let report = try? await console.settings(of: silo) {
            settings[silo.id] = report
        }
    }

    /// Sends one change to the silo. What the silo answered is what the pane shows, and a refusal
    /// is told in the silo's own words.
    func updateSettings(for silo: AdminConsole.Silo, _ patch: SiloClient.SettingsPatch) async {
        do {
            settings[silo.id] = try await console.updateSettings(of: silo, patch)
            silos = await console.silos
        } catch let refused as AdminConsole.SettingsRefused {
            refusal = .settingsRefused(refused.reason)
        } catch is AdminConsole.NoAccess {
            refusal = .noAccess
        } catch {
            refusal = .unreachable
        }
    }

    /// Reads a with-access silo's rulesets. A failure leaves the last reading in place, as the
    /// settings do.
    func loadRulesets(for silo: AdminConsole.Silo) async {
        if let read = try? await console.rulesets(of: silo) {
            rulesets[silo.id] = read
        }
        loadDrafts(for: silo)
    }

    /// Opens a ruleset at a version, or at its standard's head, with its branch's trials.
    func open(ruleset name: String, version: Int? = nil, of silo: AdminConsole.Silo) async {
        let before = opened[silo.id].map { ($0.summary.name, $0.document.branch) }
        if let read = try? await console.open(ruleset: name, version: version, of: silo) {
            opened[silo.id] = read
        }
        if before.map({ $0 != (name, opened[silo.id]?.document.branch) }) ?? true { await loadTrials(for: silo) }
    }

    /// Reads each library's out-of-date presentations.
    func loadOutOfDate(for silo: AdminConsole.Silo) async {
        if let read = try? await console.outOfDate(of: silo) {
            outOfDate[silo.id] = read
        }
    }

}

// MARK: - Drafts

extension ConsoleModel {
    /// The draft open in the editor for a silo.
    func draft(of silo: AdminConsole.Silo) -> Draft? {
        editing[silo.id].flatMap { id in drafts[silo.id]?.first { $0.id == id } }
    }

    /// What the silo last made of the open draft.
    func draftCheck(of silo: AdminConsole.Silo) -> AdminConsole.DraftCheck? {
        editing[silo.id].flatMap { draftChecks[$0] }
    }

    /// The silo's drafts as this Mac keeps them, the open draft's unsaved keystrokes kept over them.
    func loadDrafts(for silo: AdminConsole.Silo) {
        let open = draft(of: silo)
        drafts[silo.id] = console.drafts.drafts(of: silo.id).map { $0.id == open?.id ? open! : $0 }
        if let id = editing[silo.id], drafts[silo.id]?.contains(where: { $0.id == id }) != true {
            editing[silo.id] = nil
        }
    }

    /// Keeps a new draft on this Mac, opens it, and has the silo check it at once.
    func startDraft(_ draft: Draft, for silo: AdminConsole.Silo) {
        keep(draft, for: silo)
        editing[silo.id] = draft.id
        draftChecks[draft.id] = nil
        scheduleCheck(of: draft.id, for: silo, after: .zero)
    }

    /// Opens a kept draft in the editor.
    func openDraft(_ id: Draft.ID, for silo: AdminConsole.Silo) {
        guard drafts[silo.id]?.contains(where: { $0.id == id }) == true else { return }
        editing[silo.id] = id
        if draftChecks[id] == nil { scheduleCheck(of: id, for: silo, after: .zero) }
    }

    /// Closes the editor, keeping the draft.
    func closeDraft(for silo: AdminConsole.Silo) {
        guard let id = editing[silo.id] else { return }
        if let draft = draft(of: silo) { keep(draft, for: silo) }
        editing[silo.id] = nil
        checking[id]?.cancel()
    }

    /// The operator's edit: the text kept, then saved to this Mac and checked by the silo a moment
    /// after they stop typing.
    func editDraft(_ text: String, for silo: AdminConsole.Silo) {
        guard var draft = draft(of: silo), draft.text != text,
            let index = drafts[silo.id]?.firstIndex(where: { $0.id == draft.id })
        else { return }
        draft.text = text
        draft.edited = .now
        drafts[silo.id]?[index] = draft
        scheduleCheck(of: draft.id, for: silo, after: checkDelay)
    }

    /// Discards the open draft: off this Mac, and out of the editor.
    func discardDraft(for silo: AdminConsole.Silo) {
        guard let id = editing[silo.id] else { return }
        checking[id]?.cancel()
        try? console.drafts.remove(id, of: silo.id)
        editing[silo.id] = nil
        draftChecks[id] = nil
        loadDrafts(for: silo)
        if review?.silo.id == silo.id { review = nil }
    }

    /// Waits for the save and check in flight, if any: what a test needs to read the outcome.
    func settleCheck(for silo: AdminConsole.Silo) async {
        guard let id = editing[silo.id] else { return }
        await checking[id]?.value
    }

    private func keep(_ draft: Draft, for silo: AdminConsole.Silo) {
        try? console.drafts.save(draft, for: silo.id)
        loadDrafts(for: silo)
        if let index = drafts[silo.id]?.firstIndex(where: { $0.id == draft.id }) { drafts[silo.id]?[index] = draft }
    }

    /// Each keystroke cancels the save and check it supersedes, so only the text the operator stopped
    /// on is saved and sent; a reply for text that has since changed is dropped.
    private func scheduleCheck(of id: Draft.ID, for silo: AdminConsole.Silo, after delay: Duration) {
        checking[id]?.cancel()
        checking[id] = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled, let self, let draft = self.drafts[silo.id]?.first(where: { $0.id == id }) else {
                return
            }
            try? self.console.drafts.save(draft, for: silo.id)
            guard let outcome = try? await self.console.check(draft, of: silo), !Task.isCancelled,
                self.drafts[silo.id]?.first(where: { $0.id == id })?.text == draft.text
            else { return }
            self.draftChecks[id] = outcome
        }
    }

    /// Opens the review: the draft's difference from its base, which needs nothing from the silo, and
    /// its impact, which the silo resolves. Nothing is stored.
    func beginReview(for silo: AdminConsole.Silo) async {
        guard let draft = draft(of: silo) else { return }
        do {
            let impact = try await console.impact(of: draft, of: silo)
            let branches =
                draft.base == nil ? [] : (try? await console.open(ruleset: draft.ruleset, of: silo).branches) ?? []
            review = Review(silo: silo, draft: draft, impact: impact, branches: branches)
        } catch {
            refusal = .unreachable
        }
    }

    /// Stores the reviewed draft. A new version ends the draft and opens what was stored; a version
    /// that landed first keeps the draft and shows that version in the review.
    func store(to target: AdminConsole.StoreTarget) async {
        guard let review, let draft = draft(of: review.silo) else { return }
        do {
            switch try await console.store(draft, to: target, of: review.silo) {
            case .stored(let version):
                self.review = nil
                discardDraft(for: review.silo)
                await loadRulesets(for: review.silo)
                await open(ruleset: version.name, version: version.version, of: review.silo)
            case .landedFirst(let landed):
                self.review?.landed = landed
            }
        } catch let refused as AdminConsole.StoreRefused {
            refusal = .storeRefused(refused.reason)
        } catch is AdminConsole.NoAccess {
            refusal = .noAccess
        } catch {
            refusal = .unreachable
        }
    }

    /// Re-bases the open draft on the version that landed first, its text as it was; the review
    /// closes, so that the next one is read against the new base.
    func rebase(on landed: SiloClient.RulesetDocument, for silo: AdminConsole.Silo) {
        guard let draft = draft(of: silo) else { return }
        review = nil
        startDraft(draft.rebased(on: landed), for: silo)
    }

    /// Re-bases the open draft on its branch's head as the silo has it now: for a draft listed as behind.
    func rebaseOnHead(for silo: AdminConsole.Silo) async {
        guard let draft = draft(of: silo), draft.base != nil,
            let opened = try? await console.open(ruleset: draft.ruleset, of: silo),
            let head = opened.branches.first(where: { $0.name == draft.branch })?.head,
            let landed = try? await console.open(ruleset: draft.ruleset, version: head, of: silo)
        else {
            refusal = .unreachable
            return
        }
        rebase(on: landed.document, for: silo)
    }

}

// MARK: - Promotion

extension ConsoleModel {
    func beginPromotion(of branch: String, of ruleset: String, on silo: AdminConsole.Silo) async {
        do {
            let impact = try await console.impact(ofBranch: branch, of: ruleset, on: silo)
            promotion = Promotion(silo: silo, ruleset: ruleset, branch: branch, impact: impact)
        } catch {
            refusal = .unreachable
        }
    }

    /// Promotes the branch being considered. A refusal stays in the sheet, with what the branch has
    /// not taken in.
    func promote() async {
        guard let promotion else { return }
        do {
            let version = try await console.promote(promotion.branch, of: promotion.ruleset, on: promotion.silo)
            self.promotion = nil
            await loadRulesets(for: promotion.silo)
            await open(ruleset: version.name, version: version.version, of: promotion.silo)
        } catch let refused as AdminConsole.PromotionRefused {
            self.promotion?.refused = refused
        } catch {
            refusal = .unreachable
        }
    }

    /// A draft on the branch from its head, taking in the standard's head, for the operator to make
    /// the branch's document say what it should of the standard's work before the promotion is
    /// offered again.
    func takeIn(_ standardHead: Int, on promotion: Promotion) async {
        guard let opened = try? await console.open(ruleset: promotion.ruleset, of: promotion.silo),
            let head = opened.branches.first(where: { $0.name == promotion.branch })?.head,
            let branchHead = try? await console.open(ruleset: promotion.ruleset, version: head, of: promotion.silo)
        else {
            refusal = .unreachable
            return
        }
        self.promotion = nil
        var draft = Draft.change(branchHead.document)
        draft.upToDateWith = standardHead
        startDraft(draft, for: promotion.silo)
    }

}

// MARK: - Trials

extension ConsoleModel {
    /// Starts choosing the bindings to try the version on screen on, its branch's impact offered first.
    func beginTrying(_ version: SiloClient.RulesetDocument, on silo: AdminConsole.Silo) async {
        guard let number = version.version, let branch = version.branch, branch != "standard" else { return }
        do {
            let candidates = try await console.trialCandidates(of: version.name, branch: branch, on: silo)
            trying = Trying(
                silo: silo,
                ruleset: version.name,
                branch: branch,
                version: number,
                candidates: candidates,
                chosen: Set(candidates.map(\.binding))
            )
        } catch {
            refusal = .unreachable
        }
    }

    /// Makes a trial job of every recipe the version makes for the chosen bindings. Places nothing.
    func startTrials(_ trying: Trying) async {
        self.trying = nil
        do {
            let started = try await console.startTrials(
                of: trying.ruleset,
                branch: trying.branch,
                version: trying.version,
                on: trying.chosen.sorted(),
                of: trying.silo
            )
            trialJobs[trying.silo.id, default: []].append(contentsOf: started.flatMap(\.jobs))
            trialRefusals[trying.silo.id] = started.compactMap { start in
                start.refusal.map { "\(start.binding): \($0)" }
            }
            await loadTrials(for: trying.silo)
        } catch is AdminConsole.NoAccess {
            refusal = .noAccess
        } catch {
            refusal = .unreachable
        }
    }

    /// The trial jobs this console started, as far as each has got, and the tried trials of the open
    /// version's branch beside what was placed.
    func loadTrials(for silo: AdminConsole.Silo) async {
        let started = trialJobs[silo.id] ?? []
        if !started.isEmpty, let now = try? await console.trialJobs(started.map(\.id), on: silo) {
            trialJobs[silo.id] = now
        }
        guard let version = opened[silo.id]?.document, let branch = version.branch, branch != "standard" else {
            trials[silo.id] = nil
            return
        }
        if let read = try? await console.trials(of: version.name, branch: branch, on: silo) {
            trials[silo.id] = read
        }
    }

    func deleteTrial(_ job: String, on silo: AdminConsole.Silo) async {
        do {
            try await console.deleteTrial(job, on: silo)
            trialJobs[silo.id]?.removeAll { $0.id == job }
            await loadTrials(for: silo)
        } catch {
            refusal = .unreachable
        }
    }

}

// MARK: - Libraries

extension ConsoleModel {
    /// Reads a with-access silo's libraries and each one's last walk. A failure leaves the last
    /// reading in place, as the settings do. There is no rescan: the silo walks its libraries itself.
    func loadLibraries(for silo: AdminConsole.Silo) async {
        if let read = try? await console.libraries(of: silo) {
            libraries[silo.id] = read
        }
        if let walks = try? await console.lastWalks(of: silo) {
            lastWalks[silo.id] = walks
        }
        if rulesets[silo.id] == nil { await loadRulesets(for: silo) }
    }

    /// Where the network may add a library to a silo, as its settings last said: nil until they are
    /// read, and empty when its owner named none.
    func libraryRoots(of silo: AdminConsole.Silo) -> [String]? {
        settings[silo.id]?.readOnly.libraryRoots
    }

    /// Adds a library at `folder` within `root`. Nil when it was added, and the settings and
    /// libraries read again, so the pane shows the library as the silo walked it; otherwise why not,
    /// in the silo's own words, for the sheet that asked to say.
    func addLibrary(
        id: String,
        folder: String,
        within root: String,
        create: Bool = false,
        on silo: AdminConsole.Silo
    ) async -> String? {
        do {
            _ = try await console.addLibrary(
                id: id,
                path: AdminConsole.path(folder, within: root),
                create: create,
                on: silo
            )
        } catch let refused as AdminConsole.SettingsRefused {
            return refused.reason
        } catch is AdminConsole.NoAccess {
            return Refusal.noAccess.message
        } catch {
            return Refusal.unreachable.message
        }
        await loadSettings(for: silo)
        await loadLibraries(for: silo)
        return nil
    }

    /// What adding a library at `folder` within `root` would find, for the sheet to say as the operator
    /// types; nil when the silo could not be asked, and the sheet then says nothing of the path.
    func checkLibrary(
        id: String,
        folder: String,
        within root: String,
        create: Bool,
        on silo: AdminConsole.Silo
    ) async -> SiloClient.LibraryCheck? {
        try? await console.checkLibrary(id: id, path: AdminConsole.path(folder, within: root), create: create, on: silo)
    }

    /// Removes a library; a refusal names the job that holds it.
    func removeLibrary(_ library: String, on silo: AdminConsole.Silo) async {
        do {
            try await console.removeLibrary(library, on: silo)
        } catch let refused as AdminConsole.SettingsRefused {
            refusal = .settingsRefused(refused.reason)
            return
        } catch is AdminConsole.NoAccess {
            refusal = .noAccess
            return
        } catch {
            refusal = .unreachable
            return
        }
        // Its containers go with it, and so does the browser's choice of it or of one of them.
        containerRoots[silo.id]?[library] = nil
        containers = containers.filter { $0.key.silo != silo.id || $0.key.library != library }
        switch browsed[silo.id] {
        case .library(library)?: browsed[silo.id] = nil
        case .container(let key)? where key.library == library: browsed[silo.id] = nil
        default: break
        }
        await loadSettings(for: silo)
        await loadLibraries(for: silo)
    }

    /// Lays a library out again, or with `dryRun` asks what that would move; nil when it was refused,
    /// the refusal said. After moves, the library's walk and containers are read again.
    func layOut(_ library: String, on silo: AdminConsole.Silo, dryRun: Bool) async -> SiloClient.LayoutResult? {
        do {
            let result = try await console.layOut(library, on: silo, dryRun: dryRun)
            if !dryRun, !result.moves.isEmpty {
                await loadLibraries(for: silo)
                await loadContainers(for: silo)
            }
            return result
        } catch let refused as AdminConsole.SettingsRefused {
            refusal = .settingsRefused(refused.reason)
        } catch is AdminConsole.NoAccess {
            refusal = .noAccess
        } catch {
            refusal = .unreachable
        }
        return nil
    }

    /// Names a library's standard, or clears it; the library shows what the silo answered with.
    func setStandard(_ ruleset: String?, of library: String, on silo: AdminConsole.Silo) async {
        do {
            let answered = try await console.setStandard(ruleset, of: library, on: silo)
            if let index = libraries[silo.id]?.firstIndex(where: { $0.id == library }) {
                libraries[silo.id]?[index] = answered
            }
        } catch let refused as AdminConsole.SettingsRefused {
            refusal = .settingsRefused(refused.reason)
        } catch is AdminConsole.NoAccess {
            refusal = .noAccess
        } catch {
            refusal = .unreachable
        }
    }

}

// MARK: - Containers

extension ConsoleModel {
    /// Reads the containers at the top of each library the silo lists, listed or not, and the drafts
    /// kept for the silo. A library that fails to answer keeps its last reading.
    func loadContainers(for silo: AdminConsole.Silo) async {
        loadContainerDrafts(for: silo)
        for library in libraries[silo.id] ?? [] {
            if let roots = try? await console.containers(in: library.id, of: silo) {
                containerRoots[silo.id, default: [:]][library.id] = roots
            }
        }
    }

    /// Reads one container as its library's sidecar says it, with the last walk's findings on it.
    func open(_ key: ContainerKey) async {
        guard let silo = silos.first(where: { $0.id == key.silo }) else { return }
        if let opened = try? await console.open(container: key.container, in: key.library, of: silo) {
            containers[key] = opened
            await compareWithSmddb(key)
        }
    }

    /// Chooses a library or a container in the browser, and reads a container chosen.
    func browse(_ chosen: Browsed?, on silo: AdminConsole.Silo) async {
        browsed[silo.id] = chosen
        guard case .container(let key)? = chosen else { return }
        // A new container's draft has nothing in the library to read yet: it opens in the editor.
        if containerDraft(for: key)?.isNew == true {
            editContainer(key)
        } else {
            await open(key)
        }
    }

    /// Chooses a container in the browser and reads it.
    func select(_ key: ContainerKey) async {
        browsed[key.silo] = .container(key)
        await open(key)
    }

    /// The silo's container drafts as this Mac keeps them, the open one's unsaved keystrokes kept.
    func loadContainerDrafts(for silo: AdminConsole.Silo) {
        let open = containerDraft(of: silo)
        containerDrafts[silo.id] = console.containerDrafts.drafts(of: silo.id).map { $0.id == open?.id ? open! : $0 }
        if let id = editingContainer[silo.id], containerDrafts[silo.id]?.contains(where: { $0.id == id }) != true {
            editingContainer[silo.id] = nil
        }
    }

    /// The container draft open in the editor for a silo.
    func containerDraft(of silo: AdminConsole.Silo) -> ContainerDraft? {
        editingContainer[silo.id].flatMap { id in containerDrafts[silo.id]?.first { $0.id == id } }
    }

    /// The draft kept for a container, open or not.
    func containerDraft(for key: ContainerKey) -> ContainerDraft? {
        containerDrafts[key.silo]?.first { $0.library == key.library && $0.container == key.container }
    }

    /// What the silo's dry run last made of the open container draft.
    func containerCheck(of silo: AdminConsole.Silo) -> AdminConsole.ContainerCheck? {
        editingContainer[silo.id].flatMap { containerChecks[$0] }
    }

    /// Edits a container: its kept draft, or a new one based on the sidecar as last read, opened and
    /// checked by the silo at once.
    func editContainer(_ key: ContainerKey) {
        guard let silo = silos.first(where: { $0.id == key.silo }) else { return }
        if let kept = containerDraft(for: key) {
            editingContainer[silo.id] = kept.id
            if containerChecks[kept.id] == nil { scheduleContainerCheck(of: kept.id, for: silo, after: .zero) }
            return
        }
        guard let opened = containers[key],
            let draft = try? ContainerDraft.change(opened.container, sidecar: opened.sidecar)
        else { return }
        keepContainerDraft(draft, for: silo)
        editingContainer[silo.id] = draft.id
        scheduleContainerCheck(of: draft.id, for: silo, after: .zero)
    }

    /// Closes the container editor, keeping the draft.
    func closeContainerDraft(for silo: AdminConsole.Silo) {
        guard let id = editingContainer[silo.id] else { return }
        if let draft = containerDraft(of: silo) { keepContainerDraft(draft, for: silo) }
        editingContainer[silo.id] = nil
        checkingContainer[id]?.cancel()
    }

    /// The operator's edit, from the form or the text: kept, then saved to this Mac and dry-run by the
    /// silo a moment after they stop.
    func editContainerDraft(_ text: String, for silo: AdminConsole.Silo) {
        guard var draft = containerDraft(of: silo), draft.text != text,
            let index = containerDrafts[silo.id]?.firstIndex(where: { $0.id == draft.id })
        else { return }
        draft.text = text
        draft.edited = .now
        containerDrafts[silo.id]?[index] = draft
        scheduleContainerCheck(of: draft.id, for: silo, after: checkDelay)
    }

    /// Discards the open container draft: off this Mac, and out of the editor.
    func discardContainerDraft(for silo: AdminConsole.Silo) {
        guard let id = editingContainer[silo.id] else { return }
        checkingContainer[id]?.cancel()
        try? console.containerDrafts.remove(id, of: silo.id)
        editingContainer[silo.id] = nil
        containerChecks[id] = nil
        loadContainerDrafts(for: silo)
        if containerReview?.silo.id == silo.id { containerReview = nil }
    }

    /// Waits for the container draft's save and dry run in flight, if any.
    func settleContainerCheck(for silo: AdminConsole.Silo) async {
        guard let id = editingContainer[silo.id] else { return }
        await checkingContainer[id]?.value
    }

    /// Whether the open container draft's library sidecar has moved on since its base, as last read.
    func isBehind(_ draft: ContainerDraft, on silo: AdminConsole.Silo) -> Bool {
        let key = ContainerKey(silo: silo.id, library: draft.library, container: draft.container)
        if let digest = containers[key]?.container.digest, draft.isBehind(digest) { return true }
        if case .behind? = containerChecks[draft.id] { return true }
        return false
    }

    private func keepContainerDraft(_ draft: ContainerDraft, for silo: AdminConsole.Silo) {
        try? console.containerDrafts.save(draft, for: silo.id)
        loadContainerDrafts(for: silo)
        if let index = containerDrafts[silo.id]?.firstIndex(where: { $0.id == draft.id }) {
            containerDrafts[silo.id]?[index] = draft
        }
    }

    /// As for a ruleset's draft: each keystroke cancels the save and dry run it supersedes, and a reply
    /// for text that has since changed is dropped.
    private func scheduleContainerCheck(of id: ContainerDraft.ID, for silo: AdminConsole.Silo, after delay: Duration) {
        checkingContainer[id]?.cancel()
        checkingContainer[id] = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled, let self, let draft = self.containerDrafts[silo.id]?.first(where: { $0.id == id })
            else { return }
            try? self.console.containerDrafts.save(draft, for: silo.id)
            guard let outcome = try? await self.check(draft, of: silo), !Task.isCancelled,
                self.containerDrafts[silo.id]?.first(where: { $0.id == id })?.text == draft.text
            else { return }
            self.containerChecks[id] = outcome
        }
    }

    /// Opens the review of the open container draft: its difference from its base, and the silo's
    /// dry run as it stands. Nothing is stored.
    func beginContainerReview(for silo: AdminConsole.Silo) async {
        guard let draft = containerDraft(of: silo) else { return }
        let check = try? await self.check(draft, of: silo)
        if let check { containerChecks[draft.id] = check }
        containerReview = ContainerReview(silo: silo, draft: draft, check: check)
    }

    /// Stores the reviewed container draft. A written sidecar ends the draft and shows the container
    /// as the silo now reads it; findings that refuse it, or a sidecar that landed first, keep it.
    func storeContainer() async {
        guard let review = containerReview, let draft = containerDraft(of: review.silo) else { return }
        let key = ContainerKey(silo: review.silo.id, library: draft.library, container: draft.container)
        containerReview?.failure = nil
        if draft.isNew {
            await make(draft, on: review.silo)
            return
        }
        do {
            switch try await console.store(draft, of: review.silo) {
            case .stored:
                containerReview = nil
                discardContainerDraft(for: review.silo)
                await open(key)
            case .refused(let result):
                containerChecks[draft.id] = .refused(result)
                containerReview?.check = .refused(result)
            case .landedFirst(let landed):
                containers[key] = landed
                containerReview?.landed = landed
            }
        } catch {
            containerReview?.failure = describe(error)
        }
    }

    /// Re-bases the open container draft on the sidecar that landed, its text as it was; the review
    /// closes, so that the next one is read against the new base.
    func rebaseContainerDraft(on landed: AdminConsole.OpenedContainer, for silo: AdminConsole.Silo) {
        guard let draft = containerDraft(of: silo),
            let rebased = try? draft.rebased(on: landed.container, sidecar: landed.sidecar)
        else { return }
        containerReview = nil
        keepContainerDraft(rebased, for: silo)
        containerChecks[rebased.id] = nil
        scheduleContainerCheck(of: rebased.id, for: silo, after: .zero)
    }

    /// Re-bases the open container draft on the library's sidecar as the silo has it now.
    func rebaseContainerDraftOnLatest(for silo: AdminConsole.Silo) async {
        guard let draft = containerDraft(of: silo),
            let landed = try? await console.open(container: draft.container, in: draft.library, of: silo)
        else {
            refusal = .unreachable
            return
        }
        containers[ContainerKey(silo: silo.id, library: draft.library, container: draft.container)] = landed
        rebaseContainerDraft(on: landed, for: silo)
    }

    /// Puts an image as a kind of a container's artwork, and reads the container again.
    func putArtwork(_ image: Data, as kind: String, of key: ContainerKey) async {
        guard let silo = silos.first(where: { $0.id == key.silo }) else { return }
        await artwork(of: key) {
            try await self.console.putArtwork(image, as: kind, of: key.container, in: key.library, on: silo)
        }
    }

    /// Removes a kind of a container's artwork, and reads the container again.
    func removeArtwork(_ kind: String, of key: ContainerKey) async {
        guard let silo = silos.first(where: { $0.id == key.silo }) else { return }
        await artwork(of: key) {
            try await self.console.removeArtwork(kind, of: key.container, in: key.library, on: silo)
        }
    }

    private func artwork(of key: ContainerKey, _ change: () async throws -> Void) async {
        do {
            try await change()
        } catch let refused as AdminConsole.SettingsRefused {
            refusal = .settingsRefused(refused.reason)
        } catch is AdminConsole.NoAccess {
            refusal = .noAccess
        } catch {
            refusal = .unreachable
        }
        await open(key)
    }

    /// Where a kind of a container's artwork is served.
    func artworkURL(_ kind: String, of key: ContainerKey) -> URL? {
        silos.first { $0.id == key.silo }.map { console.artworkURL(kind, of: key.container, in: key.library, of: $0) }
    }

    /// Forgetting is the engine's purge — passkey off this Mac, registry entry gone — so the
    /// row simply leaves on the next publish. Non-recoverable by design; the sheet said so.
    func forget(_ silo: AdminConsole.Silo) async {
        forgetTarget = nil
        await console.forget(silo)
        silos = await console.silos
        drafts[silo.id] = nil
        editing[silo.id] = nil
        containerDrafts[silo.id] = nil
        editingContainer[silo.id] = nil
    }
}

// MARK: - Drafts from elsewhere

extension ConsoleModel {
    /// Opens a container draft made outside the editor — from smddb, or new — in the editor, kept on
    /// this Mac, and checked by the silo at once.
    func open(_ draft: ContainerDraft, for silo: AdminConsole.Silo) {
        keepContainerDraft(draft, for: silo)
        editingContainer[silo.id] = draft.id
        browsed[silo.id] = .container(ContainerKey(silo: silo.id, library: draft.library, container: draft.container))
        scheduleContainerCheck(of: draft.id, for: silo, after: .zero)
    }

    /// Records what the silo made of a draft, in the editor and in its review if one is open.
    func settle(_ check: AdminConsole.ContainerCheck, of draft: ContainerDraft.ID) {
        containerChecks[draft] = check
        if containerReview?.draft.id == draft { containerReview?.check = check }
    }

    /// A draft's check: the dry run of making it, for a new container, or of the edit, for a held one.
    func check(_ draft: ContainerDraft, of silo: AdminConsole.Silo) async throws -> AdminConsole.ContainerCheck {
        draft.isNew ? try await console.check(new: draft, of: silo) : try await console.check(draft, of: silo)
    }
}
#endif
