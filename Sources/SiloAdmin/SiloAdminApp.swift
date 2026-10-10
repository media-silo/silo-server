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
        let registryFile = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "media-silo/SiloAdmin/registry.json", directoryHint: .notDirectory)
        let console = AdminConsole(
            registry: SiloRegistry(file: registryFile),
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

    enum DetailSection: String, CaseIterable, Identifiable {
        case settings = "Settings"
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
        case noAccess

        var title: String {
            switch self {
            case .stagedElsewhere: "Setup Staged Elsewhere"
            case .noLongerInBootstrap: "Someone Finished First"
            case .unreachable: "The Silo Could Not Be Reached"
            case .settingsRefused: "The Silo Refused the Change"
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

    init(console: AdminConsole) {
        self.console = console
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
        case .rulesets:
            await loadRulesets(for: silo)
            if let current = opened[silo.id] { await open(ruleset: current.summary.name, version: current.document.version, of: silo) }
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
    }

    /// Opens a ruleset at a version, or at its standard's head.
    func open(ruleset name: String, version: Int? = nil, of silo: AdminConsole.Silo) async {
        if let read = try? await console.open(ruleset: name, version: version, of: silo) {
            opened[silo.id] = read
        }
    }

    /// Reads each library's out-of-date presentations.
    func loadOutOfDate(for silo: AdminConsole.Silo) async {
        if let read = try? await console.outOfDate(of: silo) {
            outOfDate[silo.id] = read
        }
    }

    /// Forgetting is the engine's purge — passkey off this Mac, registry entry gone — so the
    /// row simply leaves on the next publish. Non-recoverable by design; the sheet said so.
    func forget(_ silo: AdminConsole.Silo) async {
        forgetTarget = nil
        await console.forget(silo)
        silos = await console.silos
    }
}

struct ConsoleView: View {
    @Bindable var model: ConsoleModel

    @State private var addressDraft = ""

    private let refresher = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if model.silos.isEmpty {
                // Hand-rolled so the buttons size to fit their text —
                // ContentUnavailableView caps its action width and truncates on macOS.
                VStack(spacing: 12) {
                    Image(systemName: "externaldrive")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No Silos")
                        .font(.title2.bold())
                    Button("Add Manually") { model.addingByAddress = true }
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

    var body: some View {
        HSplitView {
            List(model.rulesets[silo.id] ?? [], id: \.name, selection: Binding(
                get: { model.opened[silo.id]?.summary.name },
                set: { name in if let name { Task { await model.open(ruleset: name, of: silo) } } }
            )) { ruleset in
                VStack(alignment: .leading) {
                    Text(ruleset.name)
                    Text(ruleset.standard.map { "standard at version \($0)" } ?? "no standard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(ruleset.name)
            }
            .frame(minWidth: 160, idealWidth: 180, maxWidth: 240)
            Group {
                if let opened = model.opened[silo.id] {
                    OpenedRulesetView(opened: opened) { version in
                        Task { await model.open(ruleset: opened.summary.name, version: version, of: silo) }
                    }
                } else if model.rulesets[silo.id]?.isEmpty == true {
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
/// them, a scope that can leave a stream undecided marked so, then the outputs and the extraction
/// policy.
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
            Section("Extraction") {
                LabeledContent("Embedded audio tracks", value: reading.extraction.includeEmbeddedAudioTracks ? "kept" : "left out")
                LabeledContent("Subtitles", value: reading.extraction.includeSubtitles ? "kept" : "left out")
                LabeledContent("Embedded subtitle tracks", value: reading.extraction.includeEmbeddedSubtitleTracks ? "kept" : "left out")
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
/// the pane then shows. The libraries are listed, read-only, until they grow routes of their own.
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
                    } header: {
                        Text("This Silo's Machine")
                    } footer: {
                        Text("Set in silo.json on the silo's machine. The state directory is where operator-credential.reset goes.")
                    }
                    Section("Libraries") {
                        if report.readOnly.libraries.isEmpty {
                            Text("None").foregroundStyle(.secondary)
                        }
                        ForEach(report.readOnly.libraries, id: \.id) { library in
                            LabeledContent(library.id, value: library.path)
                        }
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
    fileprivate func sectionPanel() -> some View {
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
