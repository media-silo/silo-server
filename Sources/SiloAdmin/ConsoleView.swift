// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

#if canImport(SwiftUI)
import AppKit
import Combine
import SwiftUI
import SiloAdminKit

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
        .alert(
            "Forget \(model.forgetTarget?.name ?? "this silo")?",
            isPresented: Binding(
                get: { model.forgetTarget != nil },
                set: { if !$0 { model.forgetTarget = nil } }
            )
        ) {
            Button("Forget", role: .destructive) {
                if let silo = model.forgetTarget {
                    Task { await model.forget(silo) }
                }
            }
            Button("Cancel", role: .cancel) { model.forgetTarget = nil }
        } message: {
            Text(
                "The passkey on this Mac is deleted and the registry lets it go. If it answers again, it arrives as never met."
            )
        }
        .alert(
            model.refusal?.title ?? "",
            isPresented: Binding(
                get: { model.refusal != nil },
                set: { if !$0 { model.refusal = nil } }
            )
        ) {
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
                    Text(
                        "An earlier attempt left a setup staged on this silo; its window shuts at \(until.formatted(date: .omitted, time: .shortened))."
                    )
                    .foregroundStyle(.secondary)
                    Text(
                        "Confirming finalises the passkey shown at that attempt; it will not be shown again. The staged setup keeps the name it was made with."
                    )
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
                Button("Cancel", role: .cancel) {
                    dismiss()
                    onCancel()
                }
                Spacer()
                Button(prepared.resumingUntil == nil ? "Confirm Setup" : "Finish Setup") {
                    dismiss()
                    onConfirm(name)
                }
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
                Button("Cancel", role: .cancel) {
                    dismiss()
                    onCancel()
                }
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
