// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

#if canImport(SwiftUI)
import SwiftUI
import SiloAdminKit
import SiloClient

/// The silo's rulesets: each one, and the one open — its branches and versions to choose between,
/// and the chosen version's document as stored beside the silo's reading of it.
struct RulesetsPane: View {
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
            List(
                selection: Binding<Item?>(
                    get: {
                        model.editing[silo.id].map(Item.draft)
                            ?? model.opened[silo.id].map { .ruleset($0.summary.name) }
                    },
                    set: { item in
                        switch item {
                        case .ruleset(let name)?:
                            model.closeDraft(for: silo)
                            Task { await model.open(ruleset: name, of: silo) }
                        case .draft(let id)?: model.openDraft(id, for: silo)
                        case nil: break
                        }
                    }
                )
            ) {
                ForEach(names, id: \.self) { name in
                    let summary = model.rulesets[silo.id]?.first { $0.name == name }
                    VStack(alignment: .leading) {
                        Text(name)
                        Text(
                            summary.map { $0.standard.map { "standard at version \($0)" } ?? "no standard" }
                                ?? "not on the silo yet"
                        )
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
                        if !(model.trialJobs[silo.id] ?? []).isEmpty || !(model.trials[silo.id] ?? []).isEmpty
                            || !(model.trialRefusals[silo.id] ?? []).isEmpty
                        {
                            TrialsPanel(silo: silo, model: model)
                        }
                    }
                } else if model.rulesets[silo.id]?.isEmpty == true, (model.drafts[silo.id] ?? []).isEmpty {
                    ContentUnavailableView(
                        "No Rulesets",
                        systemImage: "list.bullet.rectangle",
                        description: Text("This silo holds no ruleset yet.")
                    )
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
                Text(
                    (draft.base.map { "from version \($0), " } ?? "")
                        + "edited \(draft.edited.formatted(.relative(presentation: .named)))"
                )
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
                    TextEditor(
                        text: Binding(
                            get: { model.draft(of: silo)?.text ?? draft.text },
                            set: { model.editDraft($0, for: silo) }
                        )
                    )
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
        var line =
            draft.base.map { "From version \($0)" + (draft.baseBranch.map { " on \($0)" } ?? "") } ?? "A new ruleset"
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
        case .refused(let reason)?:
            Label("The silo refuses it: \(reason)", systemImage: "exclamationmark.octagon").foregroundStyle(.red).font(
                .caption
            ).textSelection(.enabled)
        case nil: Label("Checking with the silo…", systemImage: "clock").foregroundStyle(.secondary).font(.caption)
        }
    }
}

/// Before a store: the draft's difference from its base and what it would put out of date, then where
/// it goes. When another version landed first, that version and how it differs from the base, with
/// the draft kept to be re-based or discarded; the console never merges.
struct ReviewSheet: View {
    let review: ConsoleModel.Review
    let model: ConsoleModel

    @State private var target = Target.baseBranch
    @State private var newBranch = ""
    @Environment(\.dismiss) private var dismiss

    enum Target: Hashable {
        case baseBranch
        case branch(String)
        case newBranch
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let landed = review.landed {
                Text("Version \(landed.version ?? 0) Landed First").font(.headline)
                Text(
                    "Nothing was stored. Version \(landed.version ?? 0) was stored on \(landed.branch ?? "the standard") after this draft's base, version \(review.draft.base ?? 0). How it differs from that base:"
                )
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
                        Text(review.draft.baseBranch.map { "its base's branch, \($0)" } ?? "the standard").tag(
                            Target.baseBranch
                        )
                        ForEach(
                            review.branches.filter { $0.name != (review.draft.baseBranch ?? "standard") && !$0.closed },
                            id: \.name
                        ) { branch in
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
struct PromotionSheet: View {
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
                            Text(
                                "Standard version \(version.version ?? 0), against the branch's base\(refused.base?.version.map { ", version \($0)" } ?? ""):"
                            )
                            .font(.callout.bold())
                            DifferenceView(
                                lines: LineDifference.lines(from: refused.base?.document ?? "", to: version.document)
                            )
                        }
                    }
                }
                HStack {
                    Button("Cancel", role: .cancel) { model.promotion = nil }
                    Spacer()
                    if let head = refused.notTakenIn.last?.version {
                        Button("Take In Version \(head)…") { Task { await model.takeIn(head, on: promotion) } }
                            .buttonStyle(.borderedProminent)
                            .help(
                                "A draft on \(promotion.branch) from its head, declaring it takes in standard version \(head)"
                            )
                    }
                }
            } else {
                Text(
                    promotion.impact.isEmpty
                        ? "Promoting would put no placed presentation out of date."
                        : "Promoting would put \(promotion.impact.count) placed presentation\(promotion.impact.count == 1 ? "" : "s") out of date. Nothing is made again."
                )
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
                Picker(
                    "Branch",
                    selection: Binding(
                        get: { branch },
                        set: { chosen in
                            if let head = opened.branches.first(where: { $0.name == chosen })?.head { choose(head) }
                        }
                    )
                ) {
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
                    ContentUnavailableView(
                        "No Reading",
                        systemImage: "questionmark.text.page",
                        description: Text("The silo sent no reading of this version.")
                    )
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
                            Text(
                                rule.conditions.isEmpty
                                    ? "always" : rule.conditions.map(\.text).joined(separator: " and ")
                            )
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
                                .help(
                                    "Every \(group.scope.rawValue) rule has conditions: a stream that meets none of them stops an application."
                                )
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
struct OutOfDatePane: View {
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
        return
            "From standard version \(base), at version \(head ?? base), up to date with standard version \(upToDateWith ?? base)"
            + (closed ? "; promoted, and closed" : "")
    }
}
#endif
