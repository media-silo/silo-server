// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

#if canImport(SwiftUI)
import AppKit
import Combine
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
            containerDrafts: ContainerDraftStore(file: folder.appending(path: "container-drafts.json", directoryHint: .notDirectory)),
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
    private let console: AdminConsole

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
    /// The trial jobs this console started for a silo, by its id, as the silo last had them.
    private(set) var trialJobs: [AdminConsole.Silo.ID: [AdminConsole.TrialJob]] = [:]
    /// What starting trials could not do, binding by binding, in the silo's words.
    private(set) var trialRefusals: [AdminConsole.Silo.ID: [String]] = [:]
    /// The tried trials of the open version's branch, each beside what its binding placed.
    private(set) var trials: [AdminConsole.Silo.ID: [AdminConsole.TrialComparison]] = [:]

    /// A branch's version to try, and the bindings to try it on: those its impact lists offered
    /// first, and any other the operator names.
    struct Trying: Identifiable {
        let id = UUID()
        var silo: AdminConsole.Silo
        var ruleset: String
        var branch: String
        var version: Int
        var candidates: [AdminConsole.TrialCandidate]
        var chosen: Set<String> = []
    }

    /// A draft's review: its difference and impact before anything is stored, and, when another
    /// version landed first, that version, for the draft to be re-based on it or discarded.
    struct Review: Identifiable {
        let id = UUID()
        var silo: AdminConsole.Silo
        var draft: Draft
        var impact: [SiloClient.OutOfDatePresentation]
        var branches: [SiloClient.Branch]
        var landed: SiloClient.RulesetDocument?
    }

    /// A container in one library of one silo: what the browser and its cache are keyed by.
    struct ContainerKey: Hashable {
        var silo: AdminConsole.Silo.ID
        var library: String
        var container: String
    }

    /// A library, or a container in one, as the Libraries section's browser chooses it.
    enum Browsed: Hashable {
        case library(String)
        case container(ContainerKey)
    }

    /// A container draft's review: its difference from its base and the silo's findings before
    /// anything is stored; when another edit landed first, that sidecar and how it differs from the
    /// base, for the draft to be re-based on it or discarded.
    struct ContainerReview: Identifiable {
        let id = UUID()
        var silo: AdminConsole.Silo
        var draft: ContainerDraft
        var check: AdminConsole.ContainerCheck?
        var landed: AdminConsole.OpenedContainer?
    }

    /// A branch's promotion: what it would put out of date, and, once refused, what it has not taken in.
    struct Promotion: Identifiable {
        let id = UUID()
        var silo: AdminConsole.Silo
        var ruleset: String
        var branch: String
        var impact: [SiloClient.OutOfDatePresentation]
        var refused: AdminConsole.PromotionRefused?
    }

    enum DraftView: String, CaseIterable, Identifiable {
        case form = "Form"
        case text = "Text"

        var id: String { rawValue }
    }

    enum DetailSection: String, CaseIterable, Identifiable {
        case settings = "Settings"
        case libraries = "Libraries"
        case rulesets = "Rulesets"
        case outOfDate = "Out of Date"

        var id: String { rawValue }
    }

    /// The endings an operator has to be told in words: someone else's stage runs out at a
    /// clock time, someone else finished, the silo could not be asked at all, or it refused a
    /// settings change or the passkey the change was asked with.
    enum Refusal {
        case stagedElsewhere(until: Date)
        case noLongerInBootstrap
        case unreachable
        case settingsRefused(String)
        case storeRefused(String)
        case noAccess

        var title: String {
            switch self {
            case .stagedElsewhere: "Setup Staged Elsewhere"
            case .noLongerInBootstrap: "Someone Finished First"
            case .unreachable: "The Silo Could Not Be Reached"
            case .settingsRefused: "The Silo Refused the Change"
            case .storeRefused: "The Silo Refused the Store"
            case .noAccess: "No Access"
            }
        }

        var message: String {
            switch self {
            case .stagedElsewhere(let until):
                "Another console has a setup staged on this silo. Its window runs out at \(until.formatted(date: .omitted, time: .shortened)) — try again after that."
            case .noLongerInBootstrap:
                "This silo's setup was already confirmed. It now shows as what its probe says."
            case .unreachable:
                "No reply; the row keeps its last-known state. Try again when the silo answers."
            case .settingsRefused(let reason):
                "Nothing was changed: \(reason)."
            case .storeRefused(let reason):
                "Nothing was stored, and the draft is kept: \(reason)."
            case .noAccess:
                "The silo no longer accepts the passkey this Mac holds for it, so its settings cannot be changed from here."
            }
        }
    }

    /// How a claim ended; only `refused` keeps the sheet up, so a mistyped group can be fixed.
    enum ClaimOutcome {
        case claimed
        case refused
        case failed
    }

    init(console: AdminConsole, checkDelay: Duration = .milliseconds(400)) {
        self.console = console
        self.checkDelay = checkDelay
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
        guard let target = selected.single, let silo = silos.first(where: { $0.id == target }), silo.classification == .withAccess else { return }
        switch section {
        case .settings: break
        // The walks move on by themselves, and a library added or removed elsewhere changes the
        // settings, so both are read again; and a container changed elsewhere, by an edit or a walk,
        // arrives with its new digest, which is what marks a draft behind.
        case .libraries:
            await loadSettings(for: silo)
            await loadLibraries(for: silo)
            await loadContainers(for: silo)
            for key in containers.keys where key.silo == silo.id { await open(key) }
        case .rulesets:
            await loadRulesets(for: silo)
            if let current = opened[silo.id] { await open(ruleset: current.summary.name, version: current.document.version, of: silo) }
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

    // MARK: Drafts

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
        if let id = editing[silo.id], drafts[silo.id]?.contains(where: { $0.id == id }) != true { editing[silo.id] = nil }
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
            guard !Task.isCancelled, let self, let draft = self.drafts[silo.id]?.first(where: { $0.id == id }) else { return }
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
            let branches = draft.base == nil ? [] : (try? await console.open(ruleset: draft.ruleset, of: silo).branches) ?? []
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
        else { refusal = .unreachable; return }
        rebase(on: landed.document, for: silo)
    }

    // MARK: Promotion

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
        else { refusal = .unreachable; return }
        self.promotion = nil
        var draft = Draft.change(branchHead.document)
        draft.upToDateWith = standardHead
        startDraft(draft, for: promotion.silo)
    }

    // MARK: Trials

    /// Starts choosing the bindings to try the version on screen on, its branch's impact offered first.
    func beginTrying(_ version: SiloClient.RulesetDocument, on silo: AdminConsole.Silo) async {
        guard let number = version.version, let branch = version.branch, branch != "standard" else { return }
        do {
            let candidates = try await console.trialCandidates(of: version.name, branch: branch, on: silo)
            trying = Trying(silo: silo, ruleset: version.name, branch: branch, version: number, candidates: candidates, chosen: Set(candidates.map(\.binding)))
        } catch {
            refusal = .unreachable
        }
    }

    /// Makes a trial job of every recipe the version makes for the chosen bindings. Places nothing.
    func startTrials(_ trying: Trying) async {
        self.trying = nil
        do {
            let started = try await console.startTrials(of: trying.ruleset, branch: trying.branch, version: trying.version, on: trying.chosen.sorted(), of: trying.silo)
            trialJobs[trying.silo.id, default: []].append(contentsOf: started.flatMap(\.jobs))
            trialRefusals[trying.silo.id] = started.compactMap { start in start.refusal.map { "\(start.binding): \($0)" } }
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

    // MARK: Libraries

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
    func addLibrary(id: String, folder: String, within root: String, create: Bool = false, on silo: AdminConsole.Silo) async -> String? {
        do {
            _ = try await console.addLibrary(id: id, path: AdminConsole.path(folder, within: root), create: create, on: silo)
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
    func checkLibrary(id: String, folder: String, within root: String, create: Bool, on silo: AdminConsole.Silo) async -> SiloClient.LibraryCheck? {
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

    // MARK: Containers

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
        }
    }

    /// Chooses a library or a container in the browser, and reads a container chosen.
    func browse(_ chosen: Browsed?, on silo: AdminConsole.Silo) async {
        browsed[silo.id] = chosen
        if case .container(let key)? = chosen { await open(key) }
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
        if let id = editingContainer[silo.id], containerDrafts[silo.id]?.contains(where: { $0.id == id }) != true { editingContainer[silo.id] = nil }
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
        guard let opened = containers[key], let draft = try? ContainerDraft.change(opened.container, sidecar: opened.sidecar) else { return }
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
        if let index = containerDrafts[silo.id]?.firstIndex(where: { $0.id == draft.id }) { containerDrafts[silo.id]?[index] = draft }
    }

    /// As for a ruleset's draft: each keystroke cancels the save and dry run it supersedes, and a reply
    /// for text that has since changed is dropped.
    private func scheduleContainerCheck(of id: ContainerDraft.ID, for silo: AdminConsole.Silo, after delay: Duration) {
        checkingContainer[id]?.cancel()
        checkingContainer[id] = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled, let self, let draft = self.containerDrafts[silo.id]?.first(where: { $0.id == id }) else { return }
            try? self.console.containerDrafts.save(draft, for: silo.id)
            guard let outcome = try? await self.console.check(draft, of: silo), !Task.isCancelled,
                  self.containerDrafts[silo.id]?.first(where: { $0.id == id })?.text == draft.text
            else { return }
            self.containerChecks[id] = outcome
        }
    }

    /// Opens the review of the open container draft: its difference from its base, and the silo's
    /// dry run as it stands. Nothing is stored.
    func beginContainerReview(for silo: AdminConsole.Silo) async {
        guard let draft = containerDraft(of: silo) else { return }
        let check = try? await console.check(draft, of: silo)
        if let check { containerChecks[draft.id] = check }
        containerReview = ContainerReview(silo: silo, draft: draft, check: check)
    }

    /// Stores the reviewed container draft. A written sidecar ends the draft and shows the container
    /// as the silo now reads it; findings that refuse it, or a sidecar that landed first, keep it.
    func storeContainer() async {
        guard let review = containerReview, let draft = containerDraft(of: review.silo) else { return }
        let key = ContainerKey(silo: review.silo.id, library: draft.library, container: draft.container)
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
        } catch let refused as AdminConsole.StoreRefused {
            refusal = .storeRefused(refused.reason)
        } catch is AdminConsole.NoAccess {
            refusal = .noAccess
        } catch {
            refusal = .unreachable
        }
    }

    /// Re-bases the open container draft on the sidecar that landed, its text as it was; the review
    /// closes, so that the next one is read against the new base.
    func rebaseContainerDraft(on landed: AdminConsole.OpenedContainer, for silo: AdminConsole.Silo) {
        guard let draft = containerDraft(of: silo), let rebased = try? draft.rebased(on: landed.container, sidecar: landed.sidecar) else { return }
        containerReview = nil
        keepContainerDraft(rebased, for: silo)
        containerChecks[rebased.id] = nil
        scheduleContainerCheck(of: rebased.id, for: silo, after: .zero)
    }

    /// Re-bases the open container draft on the library's sidecar as the silo has it now.
    func rebaseContainerDraftOnLatest(for silo: AdminConsole.Silo) async {
        guard let draft = containerDraft(of: silo),
              let landed = try? await console.open(container: draft.container, in: draft.library, of: silo)
        else { refusal = .unreachable; return }
        containers[ContainerKey(silo: silo.id, library: draft.library, container: draft.container)] = landed
        rebaseContainerDraft(on: landed, for: silo)
    }

    /// Puts an image as a kind of a container's artwork, and reads the container again.
    func putArtwork(_ image: Data, as kind: String, of key: ContainerKey) async {
        guard let silo = silos.first(where: { $0.id == key.silo }) else { return }
        await artwork(of: key) { try await self.console.putArtwork(image, as: kind, of: key.container, in: key.library, on: silo) }
    }

    /// Removes a kind of a container's artwork, and reads the container again.
    func removeArtwork(_ kind: String, of key: ContainerKey) async {
        guard let silo = silos.first(where: { $0.id == key.silo }) else { return }
        await artwork(of: key) { try await self.console.removeArtwork(kind, of: key.container, in: key.library, on: silo) }
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

struct ConsoleView: View {
    @Bindable var model: ConsoleModel

    @State private var addressDraft = ""

    private let refresher = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if model.silos.isEmpty {
                // Bonjour is browsing from launch, so an empty list is a search in progress, not
                // an absence — the address entry stays as a quiet link for when discovery can't
                // reach a silo. Hand-rolled so the link sizes to fit its text —
                // ContentUnavailableView caps its action width and truncates on macOS.
                VStack(spacing: 12) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                        .symbolEffect(.variableColor.iterative.reversing)
                    Text("Searching for Silos…")
                        .font(.title2.bold())
                    Text("Silos on your network appear here as they're found.")
                        .foregroundStyle(.secondary)
                    Button("Add a Silo by Address…") { model.addingByAddress = true }
                        .buttonStyle(.link)
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                NavigationSplitView {
                    List(model.silos, selection: $model.selected) { silo in
                        SiloRow(silo: silo) {
                            switch silo.classification {
                            case .bootstrap:
                                Button("Set Up…") { Task { await model.prepareSetup(for: silo) } }
                            case .withoutAccess:
                                Button("Claim…") { model.claimTarget = silo }
                            case .unreachable:
                                Button("Forget…", role: .destructive) { model.forgetTarget = silo }
                            case .withAccess:
                                EmptyView()
                            }
                        }
                        .tag(silo.id)
                    }
                    .navigationSplitViewColumnWidth(min: 220, ideal: 260)
                    .toolbar {
                        ToolbarItem {
                            Button("Add Silo by Address", systemImage: "plus") { model.addingByAddress = true }
                                .help("Add the silo at a typed address")
                        }
                    }
                } detail: {
                    DetailRoute(model: model)
                }
            }
        }
        // Freshness is the app's job, on all three of its cues: the window appearing, the
        // interval firing, and the app coming back to the fore. The engine's sweep coalescing
        // folds any overlap into one asking of the silos.
        .task { await model.refresh() }
        .onReceive(refresher) { _ in Task { await model.refresh() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.refresh() }
        }
        .sheet(item: $model.prepared) { prepared in
            SetupSheet(
                prepared: prepared,
                onConfirm: { name in Task { await model.runSetup(prepared, name: name) } },
                onCancel: { model.prepared = nil }
            )
        }
        .sheet(item: $model.review) { review in
            ReviewSheet(review: review, model: model)
        }
        .sheet(item: $model.promotion) { promotion in
            PromotionSheet(promotion: promotion, model: model)
        }
        .sheet(item: $model.trying) { trying in
            TrialSheet(trying: trying, model: model)
        }
        .sheet(item: $model.claimTarget) { silo in
            ClaimSheet(
                silo: silo,
                onClaim: { passkey in await model.claim(silo, passkey: passkey) },
                onCancel: { model.claimTarget = nil }
            )
        }
        .alert("Forget \(model.forgetTarget?.name ?? "this silo")?", isPresented: Binding(
            get: { model.forgetTarget != nil },
            set: { if !$0 { model.forgetTarget = nil } }
        )) {
            Button("Forget", role: .destructive) {
                if let silo = model.forgetTarget {
                    Task { await model.forget(silo) }
                }
            }
            Button("Cancel", role: .cancel) { model.forgetTarget = nil }
        } message: {
            Text("The passkey on this Mac is deleted and the registry lets it go. If it answers again, it arrives as never met.")
        }
        .alert(model.refusal?.title ?? "", isPresented: Binding(
            get: { model.refusal != nil },
            set: { if !$0 { model.refusal = nil } }
        )) {
            Button("OK") { model.refusal = nil }
        } message: {
            if let refusal = model.refusal {
                Text(refusal.message)
            }
        }
        .alert("Add Silo by Address", isPresented: $model.addingByAddress) {
            TextField("host or http://host:port", text: $addressDraft)
            Button("Add") {
                model.addAddress(addressDraft)
                addressDraft = ""
            }
            .keyboardShortcut(.defaultAction)
            .disabled(addressDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) { addressDraft = "" }
        } message: {
            Text("The address is kept and asked at every refresh from now on.")
        }
    }
}

/// The detail pane, picked by the sidebar selection: the silo read aloud — its class, its
/// host and when it was last seen. The act stays on the row, one click from where the silo
/// was picked. A silo the operator cannot use right now is announced under a banner: gone
/// quiet dims the whole read until it answers again, and a stored passkey the silo has
/// stopped accepting is named for what it is. Both are read off the row, so a return to
/// truth restores the pane without anything to unwind.
private struct DetailRoute: View {
    let model: ConsoleModel

    var body: some View {
        if let target = model.selected.single, let silo = model.silos.first(where: { $0.id == target }) {
            VStack(spacing: 12) {
                Image(systemName: silo.classification.symbol)
                    .font(.system(size: 44))
                    .foregroundStyle(silo.classification.colour)
                Text(silo.name)
                    .font(.title2)
                Text(silo.statusLabel)
                    .foregroundStyle(.secondary)
                SeenText(prefix: silo.url.host ?? silo.url.absoluteString, silo: silo)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if silo.classification == .unreachable, let lastKnown = silo.lastKnownAccess.lastKnownLabel {
                    Text(lastKnown)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if silo.classification == .withAccess {
                    WithAccessPane(silo: silo, model: model)
                }
            }
            .padding(silo.classification == .withAccess ? 20 : 40)
            .opacity(silo.classification == .unreachable ? 0.35 : 1)
            .saturation(silo.classification == .unreachable ? 0 : 1)
            .allowsHitTesting(silo.classification != .unreachable)
            .overlay(alignment: .top) {
                if silo.classification == .unreachable {
                    SiloBanner("Silo is currently unreachable")
                } else if silo.passkeyRefused {
                    SiloBanner("The stored passkey is no longer accepted")
                }
            }
        } else {
            ContentUnavailableView("Select a Silo", systemImage: "externaldrive")
        }
    }
}

/// What the operator can read of a silo this Mac has access to, a section at a time.
private struct WithAccessPane: View {
    let silo: AdminConsole.Silo
    @Bindable var model: ConsoleModel

    var body: some View {
        VStack(spacing: 12) {
            Picker("Section", selection: $model.section) {
                ForEach(ConsoleModel.DetailSection.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 360)
            switch model.section {
            case .settings: SettingsPane(silo: silo, model: model)
            case .libraries: LibrariesPane(silo: silo, model: model)
            case .rulesets: RulesetsPane(silo: silo, model: model)
            case .outOfDate: OutOfDatePane(silo: silo, model: model)
            }
        }
    }
}

/// The silo's rulesets: each one, and the one open — its branches and versions to choose between,
/// and the chosen version's document as stored beside the silo's reading of it.
private struct RulesetsPane: View {
    let silo: AdminConsole.Silo
    let model: ConsoleModel

    /// A row of the sidebar: a ruleset the silo holds, or a draft this Mac keeps.
    enum Item: Hashable {
        case ruleset(String)
        case draft(Draft.ID)
    }

    /// Every ruleset the silo holds or this Mac has a draft of, by name.
    private var names: [String] {
        let held = (model.rulesets[silo.id] ?? []).map(\.name)
        let drafted = (model.drafts[silo.id] ?? []).map(\.ruleset).filter { !held.contains($0) }
        return (held + Set(drafted)).sorted()
    }

    var body: some View {
        HSplitView {
            List(selection: Binding<Item?>(
                get: { model.editing[silo.id].map(Item.draft) ?? model.opened[silo.id].map { .ruleset($0.summary.name) } },
                set: { item in
                    switch item {
                    case .ruleset(let name)?:
                        model.closeDraft(for: silo)
                        Task { await model.open(ruleset: name, of: silo) }
                    case .draft(let id)?: model.openDraft(id, for: silo)
                    case nil: break
                    }
                }
            )) {
                ForEach(names, id: \.self) { name in
                    let summary = model.rulesets[silo.id]?.first { $0.name == name }
                    VStack(alignment: .leading) {
                        Text(name)
                        Text(summary.map { $0.standard.map { "standard at version \($0)" } ?? "no standard" } ?? "not on the silo yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(summary == nil ? nil : Item.ruleset(name))
                    ForEach((model.drafts[silo.id] ?? []).filter { $0.ruleset == name }) { draft in
                        DraftRow(draft: draft, behind: draft.isBehind(in: model.rulesets[silo.id] ?? []))
                            .tag(Item.draft(draft.id))
                    }
                }
            }
            .frame(minWidth: 160, idealWidth: 200, maxWidth: 260)
            .safeAreaInset(edge: .bottom) {
                Button("New Ruleset…", systemImage: "plus") { naming = .new }
                    .buttonStyle(.borderless)
                    .padding(8)
            }
            Group {
                if let draft = model.draft(of: silo) {
                    DraftEditor(silo: silo, draft: draft, model: model)
                } else if let opened = model.opened[silo.id] {
                    VStack(alignment: .leading, spacing: 8) {
                        RulesetActions(silo: silo, opened: opened, model: model, naming: $naming)
                        OpenedRulesetView(opened: opened) { version in
                            Task { await model.open(ruleset: opened.summary.name, version: version, of: silo) }
                        }
                        if !(model.trialJobs[silo.id] ?? []).isEmpty || !(model.trials[silo.id] ?? []).isEmpty || !(model.trialRefusals[silo.id] ?? []).isEmpty {
                            TrialsPanel(silo: silo, model: model)
                        }
                    }
                } else if model.rulesets[silo.id]?.isEmpty == true, (model.drafts[silo.id] ?? []).isEmpty {
                    ContentUnavailableView("No Rulesets", systemImage: "list.bullet.rectangle", description: Text("This silo holds no ruleset yet."))
                } else {
                    ContentUnavailableView("Select a Ruleset", systemImage: "list.bullet.rectangle")
                }
            }
            .padding(10)
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .sectionPanel()
        .task(id: silo.id) { await model.loadRulesets(for: silo) }
        .alert(naming?.title ?? "", isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("Name", text: $nameDraft)
            Button("Start Draft") {
                let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                switch naming {
                case .new: model.startDraft(.starter(named: name), for: silo)
                case .copy(let version): model.startDraft(.copy(of: version, as: name), for: silo)
                case nil: break
                }
                nameDraft = ""
            }
            .keyboardShortcut(.defaultAction)
            .disabled(nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) { nameDraft = "" }
        } message: {
            Text(naming?.message ?? "")
        }
    }

    @State private var naming: Naming?
    @State private var nameDraft = ""

    /// A draft that needs a name before it starts: a new ruleset from the starter, or a copy.
    enum Naming {
        case new
        case copy(SiloClient.RulesetDocument)

        var title: String {
            switch self {
            case .new: "New Ruleset"
            case .copy(let version): "Copy \(version.name) Version \(version.version ?? 0)"
            }
        }

        var message: String {
            switch self {
            case .new: "It starts from a rule copying every stream of each scope, and one output."
            case .copy: "The copy's name attribute is changed to the new name, as an edit you can see."
            }
        }
    }
}

/// A draft in the sidebar, under its ruleset: the branch it is listed under, its base, and whether
/// that base is no longer the branch's head.
private struct DraftRow: View {
    let draft: Draft
    let behind: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "pencil.line").foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                Text("Draft on \(draft.branch)")
                Text((draft.base.map { "from version \($0), " } ?? "") + "edited \(draft.edited.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if behind {
                Text("Behind")
                    .font(.caption2.bold())
                    .padding(.horizontal, 4)
                    .background(.orange.opacity(0.25), in: Capsule())
                    .help("The branch has moved since this draft's base; re-base it before storing")
            }
        }
        .padding(.leading, 12)
    }
}

/// What can be done from the version on screen: change it, copy it, go back to it when it is not
/// its branch's head, and promote its branch when that is not the standard.
private struct RulesetActions: View {
    let silo: AdminConsole.Silo
    let opened: AdminConsole.OpenedRuleset
    let model: ConsoleModel
    @Binding var naming: RulesetsPane.Naming?

    private var branch: SiloClient.Branch? {
        opened.branches.first { $0.name == (opened.document.branch ?? "standard") }
    }

    var body: some View {
        HStack {
            Button("Edit", systemImage: "pencil") { model.startDraft(.change(opened.document), for: silo) }
            Button("Copy As…", systemImage: "doc.on.doc") { naming = .copy(opened.document) }
            if let branch, let head = branch.head, head != opened.document.version, !branch.closed {
                Button("Go Back to This Version", systemImage: "arrow.uturn.backward") {
                    Task {
                        await model.open(ruleset: opened.summary.name, version: head, of: silo)
                        if let current = model.opened[silo.id]?.document {
                            model.startDraft(.goingBack(to: opened.document, head: current), for: silo)
                        }
                    }
                }
                .help("A draft of this version's document, based on version \(head), the branch's head")
            }
            Spacer()
            if let branch, branch.base != nil, !branch.closed {
                Button("Try…", systemImage: "testtube.2") {
                    Task { await model.beginTrying(opened.document, on: silo) }
                }
                .help("Encode this version for chosen bindings, to compare with what is placed; nothing is placed")
                Button("Promote \(branch.name)…", systemImage: "arrow.up.circle") {
                    Task { await model.beginPromotion(of: branch.name, of: opened.summary.name, on: silo) }
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

/// A draft, in a form built from the rule language or as its text: read by this console with the
/// reader the silo runs, every change in the form a splice of the text, the text saved and checked by
/// the silo a moment after each pause, with the silo's reading of it — or its refusal, in its words —
/// where the base's reading stood.
private struct DraftEditor: View {
    let silo: AdminConsole.Silo
    let draft: Draft
    let model: ConsoleModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Draft of \(draft.ruleset)").font(.title3.bold())
                    Text(origin).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("View", selection: Binding(get: { model.draftView }, set: { model.draftView = $0 })) {
                    ForEach(ConsoleModel.DraftView.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                if behind {
                    Button("Re-base on the Head") { Task { await model.rebaseOnHead(for: silo) } }
                }
                Button("Discard", role: .destructive) { model.discardDraft(for: silo) }
                Button("Review and Store…") { Task { await model.beginReview(for: silo) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!storable)
            }
            switch model.draftView {
            case .text:
                HSplitView {
                    TextEditor(text: Binding(get: { model.draft(of: silo)?.text ?? draft.text }, set: { model.editDraft($0, for: silo) }))
                        .font(.system(.callout, design: .monospaced))
                        .autocorrectionDisabled()
                        .frame(minWidth: 260)
                    Group {
                        switch model.draftCheck(of: silo) {
                        case .reading(let reading)?: ReadingView(reading: reading)
                        case .refused(let reason)?: RefusalView(reason: reason)
                        case nil: ProgressView("Checking with the silo…")
                        }
                    }
                    .frame(minWidth: 220, maxHeight: .infinity)
                }
            case .form:
                // The form is this console's reading, so the silo's is only its verdict: whether it
                // reads the draft too, or what only the silo can refuse.
                SiloVerdict(check: model.draftCheck(of: silo))
                DraftForm(draft: draft) { model.editDraft($0, for: silo) }
            }
        }
    }

    private var origin: String {
        var line = draft.base.map { "From version \($0)" + (draft.baseBranch.map { " on \($0)" } ?? "") } ?? "A new ruleset"
        if let upToDateWith = draft.upToDateWith { line += ", taking in standard version \(upToDateWith)" }
        return line
    }

    /// A draft is stored once it says something its base does not, and the silo reads it.
    private var storable: Bool {
        guard case .reading? = model.draftCheck(of: silo) else { return false }
        return draft.isChanged || draft.base == nil
    }

    private var behind: Bool { draft.isBehind(in: model.rulesets[silo.id] ?? []) }
}

/// What the silo made of the draft as last saved, in a line.
private struct SiloVerdict: View {
    let check: AdminConsole.DraftCheck?

    var body: some View {
        switch check {
        case .reading?: Label("Silo validated", systemImage: "checkmark.circle").foregroundStyle(.green).font(.caption)
        case .refused(let reason)?: Label("The silo refuses it: \(reason)", systemImage: "exclamationmark.octagon").foregroundStyle(.red).font(.caption).textSelection(.enabled)
        case nil: Label("Checking with the silo…", systemImage: "clock").foregroundStyle(.secondary).font(.caption)
        }
    }
}

/// Choosing the bindings to try a branch's version on: those its impact lists, chosen at first, and
/// any other by its id.
private struct TrialSheet: View {
    let trying: ConsoleModel.Trying
    let model: ConsoleModel
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Set<String> = []
    @State private var other = ""
    @State private var others: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Try \(trying.ruleset) Version \(trying.version) on \(trying.branch)").font(.headline)
            Text("Each binding chosen is resolved through this version and encoded as a trial, kept apart from the library to compare with what is placed. Nothing is placed.")
                .font(.callout)
                .foregroundStyle(.secondary)
            List {
                Section(trying.candidates.isEmpty ? "The branch changes nothing placed" : "What the branch would change") {
                    ForEach(trying.candidates) { candidate in
                        Toggle(isOn: Binding(get: { chosen.contains(candidate.binding) }, set: { if $0 { chosen.insert(candidate.binding) } else { chosen.remove(candidate.binding) } })) {
                            VStack(alignment: .leading) {
                                Text([candidate.container, candidate.item].compactMap { $0 }.joined(separator: " › "))
                                Text(candidate.profile ?? "unqualified").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Other bindings") {
                    ForEach(others, id: \.self) { Text($0).font(.body.monospaced()) }
                    HStack {
                        TextField("Binding id", text: $other)
                        Button("Add") {
                            let id = other.trimmingCharacters(in: .whitespaces)
                            if !id.isEmpty, !others.contains(id) { others.append(id); chosen.insert(id) }
                            other = ""
                        }
                    }
                }
            }
            .frame(minHeight: 220)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Make Trials") {
                    var started = trying
                    started.chosen = chosen
                    Task { await model.startTrials(started) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(chosen.isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 480)
        .onAppear { chosen = trying.chosen }
    }
}

/// The trials of the version's branch: the jobs still encoding, and each tried trial beside what its
/// binding placed, stream by stream, with both files to play.
private struct TrialsPanel: View {
    let silo: AdminConsole.Silo
    let model: ConsoleModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Trials").font(.headline)
            ForEach(model.trialRefusals[silo.id] ?? [], id: \.self) { refusal in
                Label(refusal, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.caption)
            }
            ForEach((model.trialJobs[silo.id] ?? []).filter { $0.state.rawValue != "tried" }, id: \.id) { job in
                HStack {
                    Text(job.id.prefix(8)).font(.caption.monospaced())
                    Text(job.state.rawValue)
                    if let fraction = job.progress?.fraction, job.state.rawValue == "encoding" {
                        ProgressView(value: fraction).frame(width: 120)
                    }
                    if let failure = job.failure { Text(failure).foregroundStyle(.red).font(.caption) }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.trials[silo.id] ?? [], id: \.trial.job) { compared in
                        TrialRow(compared: compared) { Task { await model.deleteTrial(compared.trial.job, on: silo) } }
                    }
                }
            }
            .frame(maxHeight: 260)
        }
        .padding(8)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct TrialRow: View {
    let compared: AdminConsole.TrialComparison
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(compared.trial.binding.prefix(8)) · \(compared.trial.profile ?? "unqualified") · \(compared.trial.ruleset)@\(compared.trial.version ?? 0)")
                    .font(.callout.monospaced())
                Spacer()
                Button("Play Trial") { NSWorkspace.shared.open(compared.trialFile) }
                Button("Play Placed") { if let url = compared.placedFile { NSWorkspace.shared.open(url) } }
                    .disabled(compared.placedFile == nil)
                Button("Delete", role: .destructive, action: delete)
            }
            .controlSize(.small)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
                GridRow {
                    Text("Stream").bold()
                    Text("Placed").bold()
                    Text("Trial").bold()
                }
                ForEach(compared.streams, id: \.stream) { stream in
                    GridRow {
                        Text(stream.stream)
                        Text(stream.placed?.summary ?? "—")
                        Text(stream.tried?.summary ?? "—")
                            .foregroundStyle(stream.placed == stream.tried ? Color.primary : Color.orange)
                    }
                }
            }
            .font(.caption)
            if compared.placedFile == nil {
                Text("No placed presentation of this binding is one the branch would change, so there is none to compare with.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A reader's refusal, in its words.
struct RefusalView: View {
    let reason: String

    var body: some View {
        ScrollView {
            Label(reason, systemImage: "exclamationmark.octagon")
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(8)
        }
    }
}

/// Lines of two texts' difference: removed in red, added in green, the rest as they were.
struct DifferenceView: View {
    let lines: [LineDifference.Line]

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(prefix(line.kind) + line.text)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(line.kind == .same ? Color.secondary : Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(background(line.kind))
                }
            }
            .padding(6)
        }
        .frame(minHeight: 80)
        .background(.background.secondary, in: .rect(cornerRadius: 6))
    }

    private func prefix(_ kind: LineDifference.Line.Kind) -> String {
        switch kind {
        case .same: "  "
        case .removed: "- "
        case .added: "+ "
        }
    }

    private func background(_ kind: LineDifference.Line.Kind) -> Color {
        switch kind {
        case .same: .clear
        case .removed: .red.opacity(0.15)
        case .added: .green.opacity(0.15)
        }
    }
}

/// Before a store: the draft's difference from its base and what it would put out of date, then where
/// it goes. When another version landed first, that version and how it differs from the base, with
/// the draft kept to be re-based or discarded; the console never merges.
private struct ReviewSheet: View {
    let review: ConsoleModel.Review
    let model: ConsoleModel

    @State private var target = Target.baseBranch
    @State private var newBranch = ""
    @Environment(\.dismiss) private var dismiss

    enum Target: Hashable {
        case baseBranch, branch(String), newBranch
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let landed = review.landed {
                Text("Version \(landed.version ?? 0) Landed First").font(.headline)
                Text("Nothing was stored. Version \(landed.version ?? 0) was stored on \(landed.branch ?? "the standard") after this draft's base, version \(review.draft.base ?? 0). How it differs from that base:")
                    .foregroundStyle(.secondary)
                DifferenceView(lines: LineDifference.lines(from: review.draft.baseText, to: landed.document))
                HStack {
                    Button("Cancel", role: .cancel) { model.review = nil }
                    Spacer()
                    Button("Discard Draft", role: .destructive) { model.discardDraft(for: review.silo) }
                    Button("Re-base on Version \(landed.version ?? 0)") { model.rebase(on: landed, for: review.silo) }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                Text("Store \(review.draft.ruleset)").font(.headline)
                Text(review.draft.base.map { "Its difference from version \($0):" } ?? "A new ruleset:")
                    .foregroundStyle(.secondary)
                DifferenceView(lines: review.draft.difference)
                Text(impactLine).foregroundStyle(.secondary)
                if !review.impact.isEmpty {
                    List(review.impact, id: \.recipe) { OutOfDateRow(presentation: $0) }
                        .frame(minHeight: 120)
                }
                if review.draft.base != nil {
                    Picker("Store on", selection: $target) {
                        Text(review.draft.baseBranch.map { "its base's branch, \($0)" } ?? "the standard").tag(Target.baseBranch)
                        ForEach(review.branches.filter { $0.name != (review.draft.baseBranch ?? "standard") && !$0.closed }, id: \.name) { branch in
                            Text("the branch \(branch.name)").tag(Target.branch(branch.name))
                        }
                        if (review.draft.baseBranch ?? "standard") == "standard" {
                            Text("a new branch from version \(review.draft.base ?? 0)").tag(Target.newBranch)
                        }
                    }
                    if target == .newBranch {
                        TextField("New branch's name", text: $newBranch).textFieldStyle(.roundedBorder)
                    }
                }
                HStack {
                    Button("Cancel", role: .cancel) { model.review = nil }
                    Spacer()
                    Button("Store") { Task { await model.store(to: storeTarget) } }
                        .buttonStyle(.borderedProminent)
                        .disabled(target == .newBranch && newBranch.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(20)
        .frame(width: 620, height: 560)
    }

    private var impactLine: String {
        switch review.impact.count {
        case 0: "No placed presentation would be made differently."
        case 1: "One placed presentation would be made differently. Nothing is made again."
        default: "\(review.impact.count) placed presentations would be made differently. Nothing is made again."
        }
    }

    private var storeTarget: AdminConsole.StoreTarget {
        switch target {
        case .baseBranch: .baseBranch
        case .branch(let name): .branch(name)
        case .newBranch: .newBranch(newBranch.trimmingCharacters(in: .whitespaces))
        }
    }
}

/// A branch's promotion: what it would put out of date beside it, and, when the silo refuses, each
/// standard version the branch has not taken in and how it differs from the branch's base.
private struct PromotionSheet: View {
    let promotion: ConsoleModel.Promotion
    let model: ConsoleModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Promote \(promotion.branch)").font(.headline)
            if let refused = promotion.refused {
                Label(refused.reason, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(refused.notTakenIn, id: \.version) { version in
                            Text("Standard version \(version.version ?? 0), against the branch's base\(refused.base?.version.map { ", version \($0)" } ?? ""):")
                                .font(.callout.bold())
                            DifferenceView(lines: LineDifference.lines(from: refused.base?.document ?? "", to: version.document))
                        }
                    }
                }
                HStack {
                    Button("Cancel", role: .cancel) { model.promotion = nil }
                    Spacer()
                    if let head = refused.notTakenIn.last?.version {
                        Button("Take In Version \(head)…") { Task { await model.takeIn(head, on: promotion) } }
                            .buttonStyle(.borderedProminent)
                            .help("A draft on \(promotion.branch) from its head, declaring it takes in standard version \(head)")
                    }
                }
            } else {
                Text(promotion.impact.isEmpty
                    ? "Promoting would put no placed presentation out of date."
                    : "Promoting would put \(promotion.impact.count) placed presentation\(promotion.impact.count == 1 ? "" : "s") out of date. Nothing is made again.")
                    .foregroundStyle(.secondary)
                List(promotion.impact, id: \.recipe) { OutOfDateRow(presentation: $0) }
                    .frame(minHeight: 160)
                HStack {
                    Button("Cancel", role: .cancel) { model.promotion = nil }
                    Spacer()
                    Button("Promote") { Task { await model.promote() } }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(20)
        .frame(width: 620, height: 520)
    }
}

/// One ruleset opened: its branches, each with its base, its head, the standard version it takes in
/// and whether it has been promoted; the versions on the chosen branch with what each made; and the
/// chosen version's document beside the silo's reading.
private struct OpenedRulesetView: View {
    let opened: AdminConsole.OpenedRuleset
    let choose: (Int) -> Void

    private var version: Int? { opened.document.version }
    private var branch: String { opened.document.branch ?? "standard" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(opened.summary.name).font(.title3.bold())
                Spacer()
                Picker("Branch", selection: Binding(
                    get: { branch },
                    set: { chosen in
                        if let head = opened.branches.first(where: { $0.name == chosen })?.head { choose(head) }
                    }
                )) {
                    ForEach(opened.branches, id: \.name) { branch in
                        Text(branch.label).tag(branch.name)
                    }
                }
                .frame(maxWidth: 260)
                Picker("Version", selection: Binding(get: { version ?? 0 }, set: { choose($0) })) {
                    ForEach(versions, id: \.version) { version in
                        Text("\(version.version) · made \(version.presentations)").tag(version.version)
                    }
                }
                .frame(maxWidth: 180)
            }
            if let current = opened.branches.first(where: { $0.name == branch }) {
                Text(current.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HSplitView {
                ScrollView([.vertical, .horizontal]) {
                    Text(opened.document.document)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(8)
                }
                .frame(minWidth: 220)
                if let reading = opened.document.reading {
                    ReadingView(reading: reading)
                        .frame(minWidth: 220)
                } else {
                    ContentUnavailableView("No Reading", systemImage: "questionmark.text.page", description: Text("The silo sent no reading of this version."))
                }
            }
        }
    }

    /// The versions on the chosen branch, newest first.
    private var versions: [SiloClient.RulesetVersion] {
        (opened.summary.versions ?? []).filter { $0.branch == branch }.reversed()
    }
}

/// The silo's reading of a version: the rules grouped by scope in the order that decides between
/// them, a scope that can leave a stream undecided marked so, then the outputs.
private struct ReadingView: View {
    let reading: SiloClient.RulesetReading

    var body: some View {
        List {
            ForEach(reading.byScope, id: \.scope) { group in
                Section {
                    ForEach(group.rules, id: \.name) { rule in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(rule.name).font(.body.monospaced())
                                Spacer()
                                Text(rule.action.summary).foregroundStyle(.secondary)
                            }
                            Text(rule.conditions.isEmpty ? "always" : rule.conditions.map(\.text).joined(separator: " and "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    HStack {
                        Text(group.scope.rawValue.capitalized)
                        if reading.scopesWithoutCatchAll.contains(group.scope) {
                            Label("No catch-all", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                                .help("Every \(group.scope.rawValue) rule has conditions: a stream that meets none of them stops an application.")
                        }
                    }
                }
            }
            Section("Outputs") {
                ForEach(reading.outputs, id: \.self) { output in
                    LabeledContent(output.profile ?? "unqualified", value: output.container)
                }
            }
        }
    }
}

/// Each library's out-of-date presentations as the background check has found them so far, with
/// how many it has still to check. Nothing here makes anything again.
private struct OutOfDatePane: View {
    let silo: AdminConsole.Silo
    let model: ConsoleModel

    var body: some View {
        List {
            ForEach(model.outOfDate[silo.id] ?? [], id: \.library) { library in
                Section {
                    if library.report.presentations.isEmpty {
                        Text("Nothing out of date").foregroundStyle(.secondary)
                    }
                    ForEach(library.report.presentations, id: \.recipe) { presentation in
                        OutOfDateRow(presentation: presentation)
                    }
                } header: {
                    HStack {
                        Text(library.library)
                        Spacer()
                        if library.report.pending > 0 {
                            Text("\(library.report.pending) still to be checked")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .sectionPanel()
        .task(id: silo.id) { await model.loadOutOfDate(for: silo) }
    }
}

private struct OutOfDateRow: View {
    let presentation: SiloClient.OutOfDatePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text([presentation.container, presentation.item].compactMap { $0 }.joined(separator: " · "))
                if let profile = presentation.profile { Text(profile).foregroundStyle(.secondary) }
                Spacer()
                if !presentation.everySourceHasACopy {
                    Label("A source has no copy", systemImage: "externaldrive.badge.exclamationmark")
                        .foregroundStyle(.orange)
                }
            }
            if let file = presentation.file {
                Text(file).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Text("Made by \(presentation.madeBy.summary); checked against \(presentation.checkedAgainst.summary)")
                .font(.caption)
            ForEach(presentation.changes, id: \.self) { change in
                Text("\(change.kind.rawValue) \(change.index): \(change.was.summary) → \(change.now.summary)")
                    .font(.caption.monospaced())
            }
            if presentation.outcome == .unresolvable {
                Text(presentation.reason.map { "No longer resolves: \($0)" } ?? "No longer resolves")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if let reason = presentation.reason {
                Text(reason).font(.caption)
            }
        }
    }
}

extension SiloClient.Branch {
    /// The picker's line: the branch, marked when it has been promoted.
    fileprivate var label: String {
        closed ? "\(name) (promoted)" : name
    }

    /// Where the branch stands: its base, its head, and the standard version it takes in.
    fileprivate var detail: String {
        guard let base else { return head.map { "The standard, at version \($0)" } ?? "The standard" }
        return "From standard version \(base), at version \(head ?? base), up to date with standard version \(upToDateWith ?? base)" + (closed ? "; promoted, and closed" : "")
    }
}

/// A with-access silo's settings, as the silo reports them: what a route changes, editable, and
/// the facts of its machine — where it listens, its id, where its state lives — read-only, since no
/// route changes them. Each change goes to the silo as it is made, and what the silo answers is what
/// the pane then shows. The libraries have a section of their own.
private struct SettingsPane: View {
    let silo: AdminConsole.Silo
    let model: ConsoleModel
    @State private var nameDraft = ""

    var body: some View {
        Group {
            if let report = model.settings[silo.id] {
                Form {
                    Section("Settings") {
                        TextField("Name", text: $nameDraft)
                            .onSubmit { save(SiloClient.SettingsPatch(name: nameDraft)) }
                        Toggle("Encode on this silo", isOn: Binding(
                            get: { report.editable.embeddedNode },
                            set: { save(SiloClient.SettingsPatch(embeddedNode: $0)) }
                        ))
                        Toggle("Advertise on the network", isOn: Binding(
                            get: { report.editable.advertise },
                            set: { save(SiloClient.SettingsPatch(advertise: $0)) }
                        ))
                    }
                    Section {
                        LabeledContent("Listens on", value: "\(report.readOnly.host):\(report.readOnly.port)")
                        LabeledContent("Server ID", value: report.readOnly.serverID)
                        LabeledContent("State directory", value: report.readOnly.stateDirectory)
                            .textSelection(.enabled)
                        LabeledContent("Library roots", value: report.readOnly.libraryRoots.isEmpty ? "None" : report.readOnly.libraryRoots.joined(separator: "\n"))
                            .textSelection(.enabled)
                    } header: {
                        Text("This Silo's Machine")
                    } footer: {
                        Text("Set in silo.json on the silo's machine. The state directory is where operator-credential.reset goes; a library added from the console must lie within one of the library roots.")
                    }
                }
                .formStyle(.grouped)
                .sectionPanel()
                .onAppear { nameDraft = report.editable.name }
                .onChange(of: report.editable.name) { _, name in nameDraft = name }
            } else {
                ProgressView()
            }
        }
        .task(id: silo.id) { await model.loadSettings(for: silo) }
    }

    private func save(_ patch: SiloClient.SettingsPatch) {
        Task { await model.updateSettings(for: silo, patch) }
    }
}

/// A with-access silo's libraries, and what each holds: a browser of every library with its tree of
/// containers beneath it, and the library or container chosen. A library shows its path, its
/// standard, whether it is available and what its last walk found, and is removed from here; libraries
/// are added within the roots the silo's owner named. A container shows what its library's sidecar
/// says, or the draft of an edit to it. There is no rescan: the silo walks its libraries itself, and
/// the section reads the walks and the containers again at the console's cadence while it is open.
private struct LibrariesPane: View {
    let silo: AdminConsole.Silo
    @Bindable var model: ConsoleModel
    @State private var addingLibrary = false
    @State private var removingLibrary: String?

    var body: some View {
        Group {
            if let report = model.settings[silo.id] {
                HSplitView {
                    VStack(alignment: .leading, spacing: 8) {
                        LibraryBrowser(silo: silo, libraries: report.editable.libraries, model: model)
                        Button("Add Library…", systemImage: "plus") { addingLibrary = true }
                            .buttonStyle(.borderless)
                            .padding(.horizontal, 8)
                    }
                    .padding(.vertical, 8)
                    .frame(minWidth: 220, idealWidth: 260, maxWidth: 360)

                    Group {
                        if let draft = model.containerDraft(of: silo) {
                            ContainerEditor(silo: silo, draft: draft, model: model)
                        } else {
                            switch model.browsed[silo.id] {
                            case .library(let id)?:
                                if let library = report.editable.libraries.first(where: { $0.id == id }) {
                                    LibraryDetail(silo: silo, library: library, model: model) { removingLibrary = id }
                                }
                            case .container(let key)?:
                                if let opened = model.containers[key] {
                                    ContainerDetail(key: key, opened: opened, model: model)
                                } else {
                                    ProgressView()
                                }
                            case nil:
                                ContentUnavailableView(
                                    report.editable.libraries.isEmpty ? "No Libraries" : "Nothing Chosen",
                                    systemImage: "externaldrive",
                                    description: Text(report.editable.libraries.isEmpty
                                        ? "Add a library within the roots the silo's owner named."
                                        : "Choose a library to see its path and last walk, or a container in it to see what its sidecar says.")
                                )
                            }
                        }
                    }
                    .padding(8)
                    .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
                }
                .sectionPanel()
            } else {
                ProgressView()
            }
        }
        .task(id: silo.id) {
            await model.loadSettings(for: silo)
            await model.loadLibraries(for: silo)
            await model.loadContainers(for: silo)
        }
        .sheet(isPresented: $addingLibrary) {
            AddLibrarySheet(
                roots: model.libraryRoots(of: silo) ?? [],
                onCheck: { id, folder, root, create in await model.checkLibrary(id: id, folder: folder, within: root, create: create, on: silo) },
                onAdd: { id, folder, root, create in await model.addLibrary(id: id, folder: folder, within: root, create: create, on: silo) }
            )
        }
        .sheet(item: $model.containerReview) { review in
            ContainerReviewSheet(review: review, model: model)
        }
        .alert("Remove \(removingLibrary ?? "the library")?", isPresented: Binding(
            get: { removingLibrary != nil },
            set: { if !$0 { removingLibrary = nil } }
        )) {
            Button("Remove", role: .destructive) {
                if let library = removingLibrary {
                    Task { await model.removeLibrary(library, on: silo) }
                }
            }
            Button("Cancel", role: .cancel) { removingLibrary = nil }
        } message: {
            Text("The silo forgets the library and its index. Nothing on the silo's disk is touched: every sidecar and media file stays where it is.")
        }
    }
}

/// A library chosen in the browser, which names it: where it is on the silo's machine, whether it is
/// there, what the silo's last walk of it found, and its standard; and its removal, set apart at the
/// top. Nothing here asks for a walk.
private struct LibraryDetail: View {
    let silo: AdminConsole.Silo
    let library: SiloClient.SettingsReport.Library
    let model: ConsoleModel
    let onRemove: () -> Void

    private var listed: SiloClient.Library? { model.libraries[silo.id]?.first { $0.id == library.id } }
    private var walk: SiloClient.LastWalk? { model.lastWalks[silo.id]?[library.id] }

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Button("Remove Library…", systemImage: "trash", role: .destructive, action: onRemove)
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .padding([.top, .horizontal], 12)
            Form {
                Section {
                    LabeledContent("Location") {
                        Text(library.path).textSelection(.enabled)
                    }
                    if listed?.available == false || walk?.available == false {
                        Label("Unavailable: its folder is missing, or holds nothing where the silo's index holds something. Its containers are kept, and it is walked again when the folder returns.", systemImage: "externaldrive.badge.exclamationmark")
                            .foregroundStyle(.orange)
                    }
                    LabeledContent("Last walk") {
                        if let walk {
                            Text(walk.walkedAt.formatted(.relative(presentation: .named)) + (walk.available ? ": \(walk.report.read) read, \(walk.report.unchanged) unchanged, \(walk.report.removed) removed" : ""))
                        } else {
                            Text("Not yet walked")
                        }
                    }
                    ForEach(walk?.report.findings ?? [], id: \.self) { finding in
                        Label(finding.path.map { "\($0): \(finding.text)" } ?? finding.text, systemImage: finding.severity == .error ? "exclamationmark.octagon" : "exclamationmark.triangle")
                            .foregroundStyle(finding.severity == .error ? .red : .orange)
                            .textSelection(.enabled)
                    }
                    Picker("Standard", selection: Binding(
                        get: { listed?.ruleset ?? "" },
                        set: { chosen in Task { await model.setStandard(chosen.isEmpty ? nil : chosen, of: library.id, on: silo) } }
                    )) {
                        Text("None").tag("")
                        ForEach(model.rulesets[silo.id] ?? [], id: \.name) { Text($0.name).tag($0.name) }
                    }
                } footer: {
                    Text("A library's standard is the ruleset an application takes when it names none. The silo walks each library itself — at startup, when a missing folder returns, and every five minutes — so there is nothing to rescan.")
                }
            }
            .formStyle(.grouped)
        }
    }
}

/// Adding a library: a folder chosen within one of the roots the silo's owner named in its
/// `silo.json`, since the console cannot browse the silo's disk. As the folder is typed the silo is
/// asked what the addition would find, and the sheet shows each folder along the path and whether it
/// is there; folders that are missing can be made, within a root that exists, by asking for them.
/// With the roots emptied, it says so rather than offer a path the silo will refuse. A refusal is
/// shown here, in the silo's words.
private struct AddLibrarySheet: View {
    let roots: [String]
    let onCheck: (_ id: String, _ folder: String, _ root: String, _ create: Bool) async -> SiloClient.LibraryCheck?
    let onAdd: (_ id: String, _ folder: String, _ root: String, _ create: Bool) async -> String?

    @State private var id = ""
    @State private var root = ""
    @State private var folder = ""
    @State private var create = false
    @State private var check: SiloClient.LibraryCheck?
    @State private var refused: String?
    @State private var adding = false
    @Environment(\.dismiss) private var dismiss

    private struct Asked: Equatable {
        var id: String, folder: String, root: String, create: Bool
    }

    private var name: String { id.trimmingCharacters(in: .whitespaces) }

    private var typedPath: String { AdminConsole.path(folder, within: root) }

    /// The silo's answer, while it is about the path as typed and not one typed before it.
    private var current: SiloClient.LibraryCheck? {
        guard let check, check.path == URL(fileURLWithPath: typedPath).standardizedFileURL.path else { return nil }
        return check
    }

    /// Orange for folders that will be made, red for anything else that is not there.
    private func absentColor(_ check: SiloClient.LibraryCheck) -> Color {
        create && !check.creates.isEmpty && !check.refusesPath(create: create) ? .orange : .red
    }

    /// The sentence the coloured path sits in: what comes before it and what after. A refusal over the
    /// name leaves the path good, and is said below the form.
    private func saying(_ check: SiloClient.LibraryCheck) -> (before: String, after: String) {
        let count = check.creates.count
        let folders = count == 1 ? "folder" : "\(count) folders"
        if let refusal = check.refusal, check.refusesPath(create: create) {
            // A place no folder may be made in is said over the folders being missing: making them is
            // no answer there.
            guard refusal.status == 403 || create || count == 0 else {
                return ("A library cannot be created at ", ". The \(folders) in red \(count == 1 ? "does" : "do") not exist.")
            }
            return ("A library cannot be created at ", ": \(refusal.detail).")
        }
        guard count == 0 else {
            return ("A library will be created at ", ". The \(folders) in orange will be created.")
        }
        return ("A library will be created at ", ". This path already exists on the silo.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add a Library")
                .font(.headline)
            if roots.isEmpty {
                Text("This silo has no library roots. Its owner names the folders a library may be added within in silo.json, on the silo's machine; until then nothing can be added from here.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Form {
                    TextField("Name", text: $id, prompt: Text("films"))
                    Picker("Within", selection: $root) {
                        ForEach(roots, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Folder", text: $folder, prompt: Text("Media/Films"))
                }
                .formStyle(.grouped)
                .scrollDisabled(true)
                .fixedSize(horizontal: false, vertical: true)

                Form {
                    if let check = current {
                        let saying = saying(check)
                        Text("\(saying.before)\(Text(check.present).foregroundStyle(.green))\(Text(check.absent).foregroundStyle(absentColor(check)))\(saying.after)")
                            .font(.callout)
                            .textSelection(.enabled)
                        if !check.creates.isEmpty, check.refusal?.status != 403 {
                            Toggle(check.creates.count == 1 ? "Create the missing folder" : "Create the \(check.creates.count) missing folders", isOn: $create)
                        }
                    } else {
                        // Until the silo answers for the path as typed, nothing is said of what is there.
                        Text("A library will be created at \(typedPath).")
                            .font(.callout)
                            .textSelection(.enabled)
                    }
                }
                .formStyle(.grouped)
                .scrollDisabled(true)
                .fixedSize(horizontal: false, vertical: true)
            }
            if let refused {
                Text("The silo refused it: \(refused)")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .textSelection(.enabled)
            } else if let check = current, let refusal = check.refusal, !name.isEmpty, !check.refusesPath(create: create) {
                Text("The silo would refuse it: \(refusal.detail)")
                    .foregroundStyle(.orange)
                    .font(.callout)
                    .textSelection(.enabled)
            }
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Add") {
                    adding = true
                    Task {
                        refused = await onAdd(name, folder, root, create)
                        adding = false
                        if refused == nil { dismiss() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(roots.isEmpty || name.isEmpty || adding || check?.refusal != nil)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear { root = roots.first ?? "" }
        // Asked again a moment after the typing stops, and not at every keystroke.
        .task(id: Asked(id: name, folder: folder, root: root, create: create)) {
            guard !roots.isEmpty, !root.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let answer = await onCheck(name, folder, root, create)
            guard !Task.isCancelled else { return }
            check = answer
            refused = nil
        }
    }
}

/// The word the console puts on what a silo cannot be used for: above a detail it cannot let
/// the operator act inside. A slab against the dimmed pane, gone the moment the row says
/// otherwise — there is nothing to reset, only a sweep's verdict to obey.
private struct SiloBanner: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.callout.bold())
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
            .padding(.top, 20)
    }
}

/// The "seen … ago" line, kept on its own clock. A silo that has gone quiet holds its
/// last-seen time still, so its row never changes between sweeps and SwiftUI has no reason to
/// redraw it — the phrase would freeze at whatever it read when the silo last answered. The
/// timeline re-reads it against the wall clock, so the age keeps growing while the time holds.
/// Only an unreachable silo says when it was seen: one that answers was seen at the last sweep,
/// and the phrase only flickered between "now" and "15 seconds ago" with the sweep's rhythm.
private struct SeenText: View {
    let prefix: String
    let silo: AdminConsole.Silo

    var body: some View {
        if silo.classification == .unreachable {
            TimelineView(.periodic(from: .now, by: 15)) { _ in
                Text("\(prefix) · seen \(silo.lastSeen.formatted(.relative(presentation: .named)))")
            }
        } else {
            Text(prefix)
        }
    }
}

extension View {
    /// A section of a silo's detail set apart from the silo's read above it: the window's own
    /// background is the section's too, so without a tone and an edge of its own nothing says where
    /// the section, and its scroll, begins.
    func sectionPanel() -> some View {
        scrollContentBackground(.hidden)
            .background(Color(nsColor: .underPageBackgroundColor))
            .clipShape(.rect(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.separator) }
    }
}

extension Set {
    /// The selection the detail reads: exactly one, or nothing to say.
    var single: Element? { count == 1 ? first : nil }
}

struct SiloRow<Actions: View>: View {
    let silo: AdminConsole.Silo
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack {
            Image(systemName: silo.classification.symbol)
                .foregroundStyle(silo.classification.colour)
                .frame(width: 24)
            VStack(alignment: .leading) {
                Text(silo.name)
                SeenText(prefix: "\(silo.url.host ?? silo.url.absoluteString) · \(silo.statusLabel)", silo: silo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if silo.classification == .unreachable, let lastKnown = silo.lastKnownAccess.lastKnownLabel {
                    Text(lastKnown)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            actions()
        }
        .opacity(silo.classification == .unreachable ? 0.6 : 1)
    }
}

extension AdminConsole.Silo {
    /// Held-then-refused: the silo answers, but the passkey this Mac holds for it no longer
    /// does — told apart from a silo never entered, wherever the console speaks of it.
    var passkeyRefused: Bool {
        classification == .withoutAccess && lastKnownAccess == false
    }

    /// The label the row and the detail read: the class, with a refusal named instead of
    /// plain no-access.
    var statusLabel: String {
        passkeyRefused ? "passkey no longer accepted" : classification.label
    }
}

extension AdminConsole.Classification {
    /// The one-word truth of how this Mac stands with the silo.
    var label: String {
        switch self {
        case .bootstrap: "waiting for setup"
        case .withAccess: "has access"
        case .withoutAccess: "no access"
        case .unreachable: "gone quiet"
        }
    }

    var symbol: String {
        switch self {
        case .bootstrap: "wand.and.sparkles"
        case .withAccess: "checkmark.shield"
        case .withoutAccess: "lock.trianglebadge.exclamationmark"
        case .unreachable: "antenna.radiowaves.left.and.right.slash"
        }
    }

    var colour: AnyShapeStyle {
        switch self {
        case .bootstrap: AnyShapeStyle(.tint)
        case .withAccess: AnyShapeStyle(.green)
        case .withoutAccess: AnyShapeStyle(.orange)
        case .unreachable: AnyShapeStyle(.secondary)
        }
    }
}

extension Optional where Wrapped == Bool {
    /// What an unreachable silo last owned up to — row data, since the silo itself cannot be
    /// asked. Nil means no passkey was ever held, so nothing was ever asked and there is
    /// nothing to say — a line reading "Never asked" left the operator wondering what was.
    fileprivate var lastKnownLabel: String? {
        switch self {
        case .some(true): "Had access when last seen"
        case .some(false): "Had no access when last seen"
        case .none: nil
        }
    }
}

/// The one place a minted passkey is ever rendered in full. Confirming dismisses it for good;
/// the engine has already promised the Keychain write lands before the confirm does. When the
/// engine probed the Keychain's residue as a stage that still stands, the sheet instead offers
/// that stage to be finished — deadline shown, the residue never re-rendered, the name the
/// stage already holds not up for typing anew.
struct SetupSheet: View {
    let prepared: AdminConsole.PreparedSetup
    let onConfirm: (String?) -> Void
    let onCancel: () -> Void

    @State private var name = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(prepared.resumingUntil == nil ? "Set Up This Silo" : "Finish Setting Up This Silo")
                .font(.headline)

            switch prepared.presentation {
            case .minted(let passkey):
                Text("This passkey is shown once. File it in your password manager before confirming.")
                    .foregroundStyle(.secondary)
                Text(passkey)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .background(.quaternary, in: .rect(cornerRadius: 6))
                Button("Copy Passkey", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(passkey, forType: .string)
                }
            case .reused:
                if let until = prepared.resumingUntil {
                    Text("An earlier attempt left a setup staged on this silo; its window shuts at \(until.formatted(date: .omitted, time: .shortened)).")
                        .foregroundStyle(.secondary)
                    Text("Confirming finalises the passkey shown at that attempt; it will not be shown again. The staged setup keeps the name it was made with.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("The passkey from the earlier, unfinished attempt is already filed away.")
                        .foregroundStyle(.secondary)
                }
            }

            if prepared.resumingUntil == nil {
                TextField("Name for the silo (optional)", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel", role: .cancel) { dismiss(); onCancel() }
                Spacer()
                Button(prepared.resumingUntil == nil ? "Confirm Setup" : "Finish Setup") { dismiss(); onConfirm(name) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

/// The claim: type the passkey the password manager holds, and the silo's probe decides. A
/// refusal is said inline and nothing of what was typed is kept by anyone.
struct ClaimSheet: View {
    let silo: AdminConsole.Silo
    let onClaim: (String) async -> ConsoleModel.ClaimOutcome
    let onCancel: () -> Void

    @State private var passkey = ""
    @State private var refused = false
    @State private var claiming = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Claim \(silo.name)")
                .font(.headline)
            SecureField("Passkey", text: $passkey)
                .textFieldStyle(.roundedBorder)
            if refused {
                Text("The silo refused that passkey. Nothing was stored.")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
            HStack {
                Button("Cancel", role: .cancel) { dismiss(); onCancel() }
                Spacer()
                Button("Claim") {
                    claiming = true
                    Task {
                        switch await onClaim(passkey) {
                        case .claimed, .failed:
                            dismiss()
                        case .refused:
                            refused = true
                        }
                        claiming = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(passkey.isEmpty || claiming)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
#endif
