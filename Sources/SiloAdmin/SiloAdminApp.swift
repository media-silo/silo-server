// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

#if canImport(SwiftUI)
import AppKit
import Combine
import SwiftUI
import SiloAdminKit

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

    /// The endings an operator has to be told in words: someone else's stage runs out at a
    /// clock time, someone else finished, or the silo could not be asked at all.
    enum Refusal {
        case stagedElsewhere(until: Date)
        case noLongerInBootstrap
        case unreachable

        var title: String {
            switch self {
            case .stagedElsewhere: "Setup Staged Elsewhere"
            case .noLongerInBootstrap: "Someone Finished First"
            case .unreachable: "The Silo Could Not Be Reached"
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
    /// rendering of a minted passkey, is already gone.
    func runSetup(name: String?) async {
        guard let prepared else { return }
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
                onConfirm: { name in Task { await model.runSetup(name: name) } },
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
                Text("\(silo.url.host ?? silo.url.absoluteString) · seen \(silo.lastSeen.formatted(.relative(presentation: .named)))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if silo.classification == .unreachable {
                    Text(silo.lastKnownAccess.lastKnownLabel)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(40)
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

extension Set {
    /// The selection the detail reads: exactly one, or nothing to say.
    fileprivate var single: Element? { count == 1 ? first : nil }
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
                Text("\(silo.url.host ?? silo.url.absoluteString) · \(silo.statusLabel) · seen \(silo.lastSeen.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if silo.classification == .unreachable {
                    Text(silo.lastKnownAccess.lastKnownLabel)
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
    /// asked; nil means nothing was ever held, so nothing was ever asked.
    fileprivate var lastKnownLabel: String {
        switch self {
        case .some(true): "Had access when last seen"
        case .some(false): "Had no access when last seen"
        case .none: "Never asked"
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
