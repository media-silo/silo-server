// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

#if canImport(SwiftUI)
import SiloAdminKit
import SiloClient
import SmdKit
import SwiftUI

/// The clone of smddb's data repository this Mac reads, named in its settings: where it is, why it
/// cannot be read when it cannot, and the way to choose it or read it again. The console never clones,
/// pulls, commits or pushes; that is the operator's, in the clone.
struct SmddbCloneBar: View {
    let model: ConsoleModel
    @State private var choosing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Label("smddb", systemImage: "books.vertical").font(.caption.bold())
                Spacer()
                Button("Choose…") { choosing = true }.buttonStyle(.borderless).font(.caption)
                if model.smddbFolder != nil {
                    Button("Read Again") { Task { await model.readClone() } }.buttonStyle(.borderless).font(.caption)
                }
            }
            if let problem = model.smddbProblem {
                Text(problem).font(.caption2).foregroundStyle(.orange).textSelection(.enabled)
            } else if let folder = model.smddbFolder {
                Text(folder.path).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                    .help(folder.path)
            }
        }
        .padding(.horizontal, 8)
        .task { await model.readClone() }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.folder]) { result in
            guard case .success(let folder) = result else { return }
            Task { await model.chooseClone(folder) }
        }
    }
}

/// How a library's container stands against smddb's record of it.
struct StandingLabel: View {
    let standing: AdminConsole.Standing?

    var body: some View {
        switch standing {
        case .matches?:
            Label("As smddb has it", systemImage: "checkmark.seal").foregroundStyle(.green)
        case .differs?:
            Label("Differs from smddb", systemImage: "arrow.left.arrow.right").foregroundStyle(.orange)
        case .absent?:
            Label("Not in smddb", systemImage: "questionmark.square.dashed").foregroundStyle(.secondary)
        case nil:
            EmptyView()
        }
    }
}

/// Bringing a container from smddb into a library, as three steps: finding it in the clone, choosing
/// what of the tree beneath it comes with it, and checking with the silo what the import would make
/// before it is made. A container the library holds opens as an edit from smddb's record instead; a
/// parent older than smddb's record is offered as one first.
struct ImportSheet: View {
    let importing: ConsoleModel.Importing
    let model: ConsoleModel
    @Environment(\.dismiss) private var dismiss

    private enum Step: Int, CaseIterable {
        case find, choose, check

        var title: String {
            switch self {
            case .find: "Find"
            case .choose: "Choose"
            case .check: "Check"
            }
        }
    }

    @State private var step: Step = .find
    @State private var query = ""
    @State private var found: [Container] = []
    @State private var picked: ContainerID?
    @State private var plan: AdminConsole.ImportPlan?
    @State private var chosen: Set<ContainerID> = []
    @State private var outcome: AdminConsole.ImportOutcome?
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Import from smddb into \(importing.library)").font(.title3.bold())
                Spacer()
                ForEach(Step.allCases, id: \.self) { each in
                    Text("\(each.rawValue + 1). \(each.title)")
                        .font(.caption)
                        .foregroundStyle(each == step ? .primary : .secondary)
                        .fontWeight(each == step ? .semibold : .regular)
                }
            }
            switch step {
            case .find: findStep
            case .choose: chooseStep
            case .check: checkStep
            }
            HStack {
                if step != .find, !isMade {
                    Button("Back") { back() }
                }
                Spacer()
                if isMade {
                    Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
                } else {
                    Button("Cancel", role: .cancel) { dismiss() }
                    switch step {
                    case .find:
                        Button("Continue") { Task { await planPicked() } }
                            .buttonStyle(.borderedProminent)
                            .disabled(picked == nil || working)
                    case .choose:
                        Button("Continue") { step = .check }.buttonStyle(.borderedProminent)
                    case .check:
                        Button("Import") { Task { await run(dryRun: false) } }
                            .buttonStyle(.borderedProminent)
                            .disabled(!isWouldMake || working)
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 560, minHeight: 440)
    }

    // MARK: Steps

    private var findStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Title, or a provider's id such as tvdb:76107", text: $query)
                .textFieldStyle(.roundedBorder)
                .task(id: query) {
                    try? await Task.sleep(for: .milliseconds(200))
                    found = await model.searchSmddb(query)
                }
            List(found, id: \.id, selection: $picked) { container in
                VStack(alignment: .leading) {
                    Text(container.displayTitle)
                    Text("\(container.type.title), \(container.id)").font(.caption).foregroundStyle(.secondary)
                }
                .tag(container.id)
            }
        }
    }

    @ViewBuilder
    private var chooseStep: some View {
        if let plan {
            Text(plan.parent.map { "Beneath \($0), which the library holds." } ?? "At the top of the library.")
                .foregroundStyle(.secondary)
            List {
                ForEach(plan.ancestors, id: \.id) { ancestor in
                    Label("\(ancestor.displayTitle), made above it", systemImage: "arrow.up")
                }
                ImportTreeNode(plan: plan, container: plan.picked, chosen: $chosen, depth: 0, included: true)
            }
        }
    }

    @ViewBuilder
    private var checkStep: some View {
        if let plan {
            let documents = plan.documents(choosing: chosen).count
            Text(
                "\(documents) container\(documents == 1 ? "" : "s") from smddb, with no presentations, "
                    + (plan.parent.map { "beneath \($0)." } ?? "at the top of the library.")
            )
            .foregroundStyle(.secondary)
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                switch outcome {
                case .wouldMake(let result)?:
                    Label("The silo would write", systemImage: "checkmark.circle").foregroundStyle(.green)
                    writes(result)
                    FindingsList(findings: result.findings)
                case .made(let result)?:
                    Label("Imported", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    writes(result)
                case .refused(let result, let parentDraft)?:
                    Label("The silo refuses it", systemImage: "exclamationmark.octagon").foregroundStyle(.red)
                    FindingsList(findings: result.findings)
                    if let parentDraft {
                        Text(
                            "\(parentDraft.title) in this library does not yet name what is being imported beneath it. Bring its fields from smddb, store that edit, and import again."
                        )
                        .font(.caption)
                        Button("Bring \(parentDraft.title)'s Fields from smddb…") {
                            model.open(parentDraft, for: importing.silo)
                            dismiss()
                        }
                    }
                case nil:
                    Label("Checking with the silo…", systemImage: "clock").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: chosen) {
            outcome = nil
            await run(dryRun: true)
        }
    }

    private func writes(_ result: SiloClient.ContainerCreateResult) -> some View {
        ForEach(result.writes, id: \.path) { write in
            Text("\(write.creates ? "write " : "update") \(write.path)")
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
    }

    // MARK: Actions

    private func back() {
        switch step {
        case .find: break
        case .choose:
            step = .find
            plan = nil
        case .check:
            step = .choose
            outcome = nil
        }
    }

    /// Works out the import of the container picked; one the library holds closes the sheet and opens
    /// as an edit from smddb's record.
    private func planPicked() async {
        guard let picked else { return }
        working = true
        defer { working = false }
        guard let planned = await model.planImport(picked, into: importing.library, on: importing.silo) else { return }
        plan = planned
        chosen = Set(planned.descendants.map(\.id))
        step = .choose
    }

    private func run(dryRun: Bool) async {
        guard let plan else { return }
        working = true
        defer { working = false }
        outcome = await model.runImport(plan, choosing: chosen, dryRun: dryRun, on: importing.silo)
    }

    private var isWouldMake: Bool {
        if case .wouldMake? = outcome { return true }
        return false
    }

    private var isMade: Bool {
        if case .made? = outcome { return true }
        return false
    }
}

/// One container of an import's tree, and the containers beneath it once disclosed. The picked
/// container is always made; each one below has a box of its own, and one with children a second,
/// three-state box for every container beneath it — all, none, or some — with how many of them are
/// chosen. A container not made makes nothing beneath it, so its children are shown and not chosen.
/// The containers the library holds already are shown in their place, and cannot be chosen.
private struct ImportTreeNode: View {
    let plan: AdminConsole.ImportPlan
    let container: Container
    @Binding var chosen: Set<ContainerID>
    let depth: Int
    /// Whether every container above this one is made, so that choosing this one means anything.
    let included: Bool
    @State private var expanded: Bool?

    var body: some View {
        let children = plan.children(of: container.id)
        let held = plan.heldChildren(of: container.id)
        if children.isEmpty && held.isEmpty {
            row(children: children)
        } else {
            DisclosureGroup(
                isExpanded: Binding(get: { expanded ?? (depth == 0) }, set: { expanded = $0 })
            ) {
                ForEach(children, id: \.id) { child in
                    ImportTreeNode(
                        plan: plan,
                        container: child,
                        chosen: $chosen,
                        depth: depth + 1,
                        included: makes
                    )
                }
                ForEach(held, id: \.id) { child in
                    Label("\(child.displayTitle), which the library holds", systemImage: "checkmark")
                        .foregroundStyle(.secondary)
                }
            } label: {
                row(children: children)
            }
        }
    }

    /// Whether this container is made: the picked one always, and one below when it and all above
    /// it are chosen.
    private var makes: Bool { depth == 0 || (included && chosen.contains(container.id)) }

    private func row(children: [Container]) -> some View {
        HStack {
            if depth == 0 {
                Label(container.displayTitle, systemImage: "shippingbox").bold()
            } else {
                Toggle(
                    container.displayTitle,
                    isOn: Binding(
                        get: { chosen.contains(container.id) },
                        set: { if $0 { chosen.insert(container.id) } else { chosen.remove(container.id) } }
                    )
                )
                .toggleStyle(.checkbox)
                .disabled(!included)
            }
            Spacer()
            if !children.isEmpty {
                let below = plan.subtree(of: container.id)
                Toggle(
                    sources: below.map { id in
                        Binding(
                            get: { chosen.contains(id) },
                            set: { if $0 { chosen.insert(id) } else { chosen.remove(id) } }
                        )
                    },
                    isOn: \.self
                ) {
                    Text("\(below.filter(chosen.contains).count) of \(below.count) below")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .toggleStyle(.checkbox)
                .disabled(!makes)
                .help("Choose every container beneath \(container.displayTitle), or none")
            }
        }
    }
}

/// Naming a new container: its type and title, and, beneath a parent, which of the parent's sequences
/// it joins and where. Its id comes from smddb's client; it then opens in the editor as a draft.
struct NewContainerSheet: View {
    let request: ConsoleModel.NewContainer
    let model: ConsoleModel
    @Environment(\.dismiss) private var dismiss
    @State private var type: ContainerType = .movie
    @State private var title = ""
    @State private var sequence = ""
    @State private var position = ""

    var body: some View {
        Form {
            Text(
                request.parentTitle.map { "A new container beneath \($0), in \(request.library)" }
                    ?? "A new container at the top of \(request.library)"
            )
            .font(.title3.bold())
            Picker("Type", selection: $type) {
                ForEach(ContainerType.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            TextField("Title", text: $title)
            if request.parent != nil {
                Picker("Sequence", selection: $sequence) {
                    ForEach(request.sequences, id: \.self) { Text($0).tag($0) }
                    if request.sequences.isEmpty { Text("A new sequence").tag("") }
                }
                TextField("Position, from 0; empty for the end", text: $position)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Create Draft") {
                    let creating = ContainerDraft.Creating(
                        parent: request.parent,
                        sequence: sequence.isEmpty ? nil : sequence,
                        position: Int(position)
                    )
                    Task {
                        await model.makeNewContainer(
                            type,
                            titled: title,
                            at: creating,
                            in: request.library,
                            on: request.silo
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(Title(title) == nil)
            }
        }
        .padding()
        .frame(minWidth: 420)
        .onAppear {
            sequence = request.sequences.first ?? ""
            if request.parent != nil { type = .season }
        }
    }
}

/// Proposing a library's container to smddb: its document's difference from smddb's record, the
/// containers it names that smddb lacks, offered with it, those neither has, and, once offered, the
/// files written in the clone for the operator to commit there.
struct ProposeSheet: View {
    let proposal: ConsoleModel.Proposing
    let model: ConsoleModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Propose \(proposal.plan.container.displayTitle) to smddb").font(.title3.bold())
            Text(
                proposal.plan.record == nil
                    ? "smddb has no record of this container: every line is new."
                    : "How \(proposal.plan.library)'s sidecar differs from smddb's record. Only its own fields are offered; its presentations, children's paths and rules stay the library's."
            )
            .foregroundStyle(.secondary)
            DifferenceView(lines: proposal.plan.difference)
            if !proposal.plan.offered.isEmpty {
                GroupBox("Containers it names that smddb does not have") {
                    ForEach(proposal.plan.offered, id: \.id) { offered in
                        Toggle(
                            offered.displayTitle,
                            isOn: Binding(
                                get: { model.proposing?.chosen.contains(offered.id) ?? false },
                                set: { on in
                                    if on {
                                        model.proposing?.chosen.insert(offered.id)
                                    } else {
                                        model.proposing?.chosen.remove(offered.id)
                                    }
                                }
                            )
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            if !proposal.plan.unavailable.isEmpty {
                Label(
                    "It names \(proposal.plan.unavailable.map(\.value).joined(separator: ", ")), which neither smddb nor this library has, so smddb would refuse it.",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange).font(.caption)
            }
            if let refusal = proposal.refusal {
                Label(refusal, systemImage: "exclamationmark.octagon").foregroundStyle(.red).font(.caption)
                    .textSelection(.enabled)
            }
            if let written = proposal.written {
                Label("Written in the clone; commit them there:", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.caption)
                ForEach(written, id: \.self) { Text($0.path).font(.caption.monospaced()).textSelection(.enabled) }
            }
            HStack {
                Spacer()
                if proposal.written == nil {
                    Button("Cancel", role: .cancel) { dismiss() }
                    Button("Propose") { Task { await model.propose() } }.buttonStyle(.borderedProminent)
                } else {
                    Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .frame(minWidth: 560, minHeight: 420)
    }
}
#endif
