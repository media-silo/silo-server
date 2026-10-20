// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

#if canImport(SwiftUI)
import AppKit
import SiloAdminKit
import SiloClient
import SmdKit
import SwiftUI
import UniformTypeIdentifiers

/// A silo's libraries and the containers they hold: each library, and beneath it its tree, from the
/// containers at its top down through the children each sidecar names, listed and unlisted alike; and
/// above them the container drafts this Mac keeps for the silo. Everything shown is the silo's
/// reading; the console adds none of its own.
struct LibraryBrowser: View {
    let silo: AdminConsole.Silo
    let libraries: [SiloClient.SettingsReport.Library]
    let model: ConsoleModel

    var body: some View {
        List(
            selection: Binding(
                get: { model.browsed[silo.id] },
                set: { chosen in Task { await model.browse(chosen, on: silo) } }
            )
        ) {
            let drafts = model.containerDrafts[silo.id] ?? []
            if !drafts.isEmpty {
                Section("Drafts") {
                    ForEach(drafts) { draft in
                        Label {
                            Text(draft.title)
                            Text(draft.library).font(.caption).foregroundStyle(.secondary)
                        } icon: {
                            Image(
                                systemName: model.isBehind(draft, on: silo) ? "clock.badge.exclamationmark" : "pencil"
                            )
                        }
                        .tag(
                            ConsoleModel.Browsed.container(
                                ConsoleModel.ContainerKey(
                                    silo: silo.id,
                                    library: draft.library,
                                    container: draft.container
                                )
                            )
                        )
                    }
                }
            }
            Section("Libraries") {
                if libraries.isEmpty {
                    Text("None").foregroundStyle(.secondary)
                }
                ForEach(libraries, id: \.id) { library in
                    LibraryNode(silo: silo, library: library.id, model: model)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

/// One library in the browser, with the containers at its top beneath it.
private struct LibraryNode: View {
    let silo: AdminConsole.Silo
    let library: String
    let model: ConsoleModel
    @State private var expanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            let roots = model.containerRoots[silo.id]?[library] ?? []
            if roots.isEmpty {
                Text("No containers").foregroundStyle(.secondary)
            }
            ForEach(roots) { root in
                ContainerNode(
                    summary: root,
                    key: ConsoleModel.ContainerKey(silo: silo.id, library: library, container: root.id),
                    model: model
                )
            }
        } label: {
            HStack {
                Label(library, systemImage: "externaldrive")
                if model.libraries[silo.id]?.first(where: { $0.id == library })?.available == false
                    || model.lastWalks[silo.id]?[library]?.available == false
                {
                    Image(systemName: "externaldrive.badge.exclamationmark").foregroundStyle(.orange).help(
                        "Unavailable"
                    )
                }
                if let findings = model.lastWalks[silo.id]?[library]?.report.findings, !findings.isEmpty {
                    Image(
                        systemName: findings.contains { $0.severity == .error }
                            ? "exclamationmark.octagon" : "exclamationmark.triangle"
                    )
                    .foregroundStyle(findings.contains { $0.severity == .error } ? .red : .orange)
                    .help(
                        "The last walk found \(findings.count == 1 ? "something" : "\(findings.count) things") to report"
                    )
                }
                Spacer()
                Menu {
                    Button("Import from smddb…") {
                        model.importing = ConsoleModel.Importing(silo: silo, library: library)
                    }
                    Button("New Container…") {
                        model.newContainer = ConsoleModel.NewContainer(silo: silo, library: library, sequences: [])
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(model.database == nil)
                .help(
                    model.database == nil
                        ? "Choose a clone of smddb's data repository below to add containers to \(library)"
                        : "Add containers to \(library)"
                )
            }
        }
        .tag(ConsoleModel.Browsed.library(library))
    }
}

/// One container in the tree, and its children beneath it once it is opened: read from the silo when
/// it is first disclosed, since only the container's own reading names its children.
private struct ContainerNode: View {
    let summary: SiloClient.ContainerSummary
    let key: ConsoleModel.ContainerKey
    let model: ConsoleModel
    @State private var expanded = false

    var body: some View {
        if let opened = model.containers[key], opened.container.container.children.isEmpty {
            label.tag(ConsoleModel.Browsed.container(key))
        } else {
            DisclosureGroup(isExpanded: $expanded) {
                ForEach(model.containers[key]?.container.container.children ?? []) { child in
                    ContainerNode(
                        summary: child,
                        key: ConsoleModel.ContainerKey(silo: key.silo, library: key.library, container: child.id),
                        model: model
                    )
                }
            } label: {
                label
            }
            .tag(ConsoleModel.Browsed.container(key))
            .task(id: expanded) {
                if expanded, model.containers[key] == nil { await model.open(key) }
            }
        }
    }

    private var label: some View {
        HStack {
            Text(summary.displayTitle)
            if !summary.listed {
                Text("unlisted").font(.caption).foregroundStyle(.secondary)
            }
            if model.containerDraft(for: key) != nil {
                Image(systemName: "pencil").foregroundStyle(.secondary).help("A draft is kept for this container")
            }
            if let findings = model.containers[key]?.findings, !findings.isEmpty {
                Image(
                    systemName: findings.contains { $0.severity == .error }
                        ? "exclamationmark.octagon" : "exclamationmark.triangle"
                )
                .foregroundStyle(findings.contains { $0.severity == .error } ? .red : .orange)
            }
        }
    }
}

/// A container as its library's sidecar says it: its own fields, its alternatives and features, its
/// sequences and extras with each item's presentations in this library and the items that have none,
/// its children, its artwork, and what the library's last walk reported on its sidecar.
struct ContainerDetail: View {
    let key: ConsoleModel.ContainerKey
    let opened: AdminConsole.OpenedContainer
    let model: ConsoleModel

    private var container: SiloClient.Container { opened.container.container }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(container.displayTitle).font(.title2.bold())
                        Text(
                            "\(container.typeLabel ?? container.type.capitalized) in \(opened.container.library), at \(opened.container.path)"
                        )
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Spacer()
                    Button(model.containerDraft(for: key) == nil ? "Edit…" : "Open Draft") { model.editContainer(key) }
                        .buttonStyle(.borderedProminent)
                }

                HStack {
                    StandingLabel(standing: model.standings[key]).font(.caption)
                    Spacer()
                    if case .differs? = model.standings[key] {
                        Button("Take smddb's Record…") { Task { await model.takeSmddbRecord(of: key) } }
                    }
                    Button("New Child Container…") {
                        guard let silo = model.silos.first(where: { $0.id == key.silo }) else { return }
                        model.newContainer = ConsoleModel.NewContainer(
                            silo: silo,
                            library: key.library,
                            parent: key.container,
                            parentTitle: container.displayTitle,
                            sequences: container.sequences.compactMap(\.id)
                        )
                    }
                    .disabled(model.database == nil)
                    Button("Propose to smddb…") { Task { await model.beginProposal(of: key) } }
                        .disabled(model.database == nil)
                }

                if !opened.findings.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("The last walk found").font(.headline)
                        FindingsList(findings: opened.findings)
                    }
                }

                ArtworkStrip(key: key, held: opened.container.artwork, model: model)

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    field("Title", container.title)
                    field("Year", container.year.map(String.init))
                    field("Type", container.typeLabel.map { "\($0) (\(container.type))" } ?? container.type)
                    field("Listed", container.listed ? "Yes" : "No")
                    field("Outline", container.outline)
                    field(
                        "External references",
                        container.externalRefs.isEmpty
                            ? nil : container.externalRefs.map { "\($0.provider) \($0.value)" }.joined(separator: ", ")
                    )
                    field("Default alternative", container.defaultAlternative)
                }

                if !container.alternatives.isEmpty {
                    GroupBox("Alternatives") {
                        ForEach(container.alternatives, id: \.id) { alternative in
                            LabeledContent(
                                alternative.title ?? alternative.id,
                                value: "\(alternative.id), plays \(alternative.sequence)"
                            )
                        }
                    }
                }
                if !container.features.isEmpty {
                    GroupBox("Features") {
                        ForEach(container.features, id: \.id) { feature in
                            LabeledContent(feature.title ?? feature.id, value: "\(feature.id), \(feature.type)")
                        }
                    }
                }
                ForEach(Array(container.sequences.enumerated()), id: \.offset) { _, sequence in
                    GroupBox(sequence.id.map { "Sequence \($0)" } ?? "Sequence") {
                        ItemsList(items: sequence.items, key: key, model: model)
                    }
                }
                if !container.extras.isEmpty {
                    GroupBox("Extras") {
                        ItemsList(items: container.extras, key: key, model: model)
                    }
                }
                if !container.children.isEmpty {
                    GroupBox("Children") {
                        ForEach(container.children) { child in
                            Button(child.displayTitle) {
                                Task {
                                    await model.select(
                                        ConsoleModel.ContainerKey(
                                            silo: key.silo,
                                            library: key.library,
                                            container: child.id
                                        )
                                    )
                                }
                            }
                            .buttonStyle(.link)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func field(_ name: String, _ value: String?) -> some View {
        GridRow {
            Text(name).foregroundStyle(.secondary)
            Text(value ?? "—").textSelection(.enabled)
        }
    }
}

/// A sequence's or the extras' items, each with the presentations the library holds of it — by
/// display name, profile, alternative and file — or saying it has none.
private struct ItemsList: View {
    let items: [SiloClient.Container.Item]
    let key: ConsoleModel.ContainerKey
    let model: ConsoleModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(item.title ?? item.id ?? "an item declared elsewhere").bold()
                        Text([item.id, item.type].compactMap { $0 }.joined(separator: ", ")).font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let child = item.container {
                        Button("Container \(child)") {
                            Task {
                                await model.select(
                                    ConsoleModel.ContainerKey(silo: key.silo, library: key.library, container: child)
                                )
                            }
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    } else if item.presentations.isEmpty {
                        Text("No presentation in this library").font(.caption).foregroundStyle(.orange)
                    }
                    ForEach(item.presentations) { presentation in
                        Text(Self.describe(presentation))
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    static func describe(_ presentation: SiloClient.Container.Presentation) -> String {
        var parts = [presentation.displayName ?? "default"]
        if let profile = presentation.profile { parts.append("profile \(profile)") }
        if let alternative = presentation.alternative { parts.append("alternative \(alternative)") }
        parts.append(presentation.file)
        return parts.joined(separator: " · ")
    }
}

/// Findings in the silo's words: errors in red, warnings in orange.
struct FindingsList: View {
    let findings: [SiloClient.LastWalk.Finding]

    var body: some View {
        ForEach(findings, id: \.self) { finding in
            Label(
                finding.text,
                systemImage: finding.severity == .error ? "exclamationmark.octagon" : "exclamationmark.triangle"
            )
            .foregroundStyle(finding.severity == .error ? .red : .orange)
            .font(.caption)
            .textSelection(.enabled)
        }
    }
}

/// Folders the silo moves, or would move: each from its path in the library to its new one.
struct FolderMovesList: View {
    let moves: [SiloClient.FolderMove]

    var body: some View {
        ForEach(moves, id: \.self) { move in
            Label("\(move.from) → \(move.to)", systemImage: "folder")
                .font(.caption)
                .textSelection(.enabled)
        }
    }
}

/// Each artwork kind of a container: the image the silo serves for it, or a place to drop one. An
/// image dropped onto a kind, or chosen, is put; a kind held can be removed.
private struct ArtworkStrip: View {
    let key: ConsoleModel.ContainerKey
    let held: [String]
    let model: ConsoleModel

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(SiloClient.artworkKinds, id: \.self) { kind in
                    ArtworkWell(
                        kind: kind,
                        url: held.contains(kind) ? model.artworkURL(kind, of: key) : nil,
                        onPut: { image in
                            Task { await model.putArtwork(image, as: kind, of: key) }
                        },
                        onRemove: {
                            Task { await model.removeArtwork(kind, of: key) }
                        }
                    )
                }
            }
        }
    }
}

private struct ArtworkWell: View {
    let kind: String
    let url: URL?
    let onPut: (Data) -> Void
    let onRemove: () -> Void
    @State private var choosing = false
    @State private var targeted = false
    /// Changed by every put and removal, so the image is fetched again rather than kept.
    @State private var generation = 0

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        targeted ? Color.accentColor : Color.secondary.opacity(0.4),
                        style: StrokeStyle(lineWidth: 1, dash: url == nil ? [4] : [])
                    )
                if let url {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        ProgressView()
                    }
                    .id(generation)
                    .padding(2)
                } else {
                    Text("Drop a JPEG or PNG").font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(
                        .center
                    ).padding(4)
                }
            }
            .frame(width: 96, height: 96)
            .dropDestination(for: URL.self) { urls, _ in
                guard let file = urls.first, let image = try? Data(contentsOf: file) else { return false }
                put(image)
                return true
            } isTargeted: {
                targeted = $0
            }
            HStack(spacing: 4) {
                Text(kind).font(.caption)
                Button("Choose \(kind)…", systemImage: "photo.badge.plus") { choosing = true }
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
                if url != nil {
                    Button("Remove \(kind)", systemImage: "minus.circle", role: .destructive) {
                        generation += 1
                        onRemove()
                    }
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
                }
            }
        }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.jpeg, .png]) { result in
            guard case .success(let file) = result else { return }
            let scoped = file.startAccessingSecurityScopedResource()
            defer { if scoped { file.stopAccessingSecurityScopedResource() } }
            if let image = try? Data(contentsOf: file) { put(image) }
        }
    }

    private func put(_ image: Data) {
        generation += 1
        onPut(image)
    }
}

/// A container's own fields being edited, as a draft kept on this Mac: in a form or as its document,
/// with the silo's dry run of it beside, and the way to review and store it, re-base it or discard it.
struct ContainerEditor: View {
    let silo: AdminConsole.Silo
    let draft: ContainerDraft
    let model: ConsoleModel
    @State private var asText = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(draft.isNew ? "New: \(draft.title)" : "Editing \(draft.title)").font(.title3.bold())
                    Text(
                        draft.isNew
                            ? "To be made in \(draft.library)\(draft.creating?.parent.map { ", beneath \($0)" } ?? ", at its top"), as \(draft.container)"
                            : "In \(draft.library), from the sidecar \(draft.base.prefix(12))…"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("View", selection: $asText) {
                    Text("Form").tag(false)
                    Text("Text").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                if model.isBehind(draft, on: silo) {
                    Button("Re-base on the Latest") { Task { await model.rebaseContainerDraftOnLatest(for: silo) } }
                }
                Button("Close") { model.closeContainerDraft(for: silo) }
                Button("Discard", role: .destructive) { model.discardContainerDraft(for: silo) }
                Button("Review and Store…") { Task { await model.beginContainerReview(for: silo) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!storable)
            }
            ContainerVerdict(check: model.containerCheck(of: silo))
            if asText {
                TextEditor(
                    text: Binding(
                        get: { model.containerDraft(of: silo)?.text ?? draft.text },
                        set: { model.editContainerDraft($0, for: silo) }
                    )
                )
                .font(.system(.callout, design: .monospaced))
                .autocorrectionDisabled()
            } else if let value = draft.value {
                ContainerForm(container: value) { changed in
                    var edited = draft
                    edited.set(changed)
                    model.editContainerDraft(edited.text, for: silo)
                }
            } else {
                RefusalView(reason: "The document does not read as a container. Edit it as text.")
            }
        }
    }

    /// A draft is stored once it says something its base does not and the silo's dry run would write it.
    private var storable: Bool {
        guard case .wouldWrite? = model.containerCheck(of: silo) else { return false }
        return draft.isChanged
    }
}

/// What the silo's dry run made of the draft as last saved.
private struct ContainerVerdict: View {
    let check: AdminConsole.ContainerCheck?

    var body: some View {
        switch check {
        case .wouldWrite(let result)?:
            Label(
                result.findings.isEmpty ? "The silo would write it" : "The silo would write it, and says",
                systemImage: "checkmark.circle"
            )
            .foregroundStyle(.green).font(.caption)
            FindingsList(findings: result.findings)
            if !result.moves.isEmpty {
                Label("Stored, it moves its folders as their names change", systemImage: "folder.badge.gearshape")
                    .foregroundStyle(.secondary).font(.caption)
                FolderMovesList(moves: result.moves)
            }
        case .refused(let result)?:
            Label("The silo refuses it", systemImage: "exclamationmark.octagon").foregroundStyle(.red).font(.caption)
            FindingsList(findings: result.findings)
        case .behind(let reason)?:
            Label(
                "The sidecar has changed since this draft was made: \(reason)",
                systemImage: "clock.badge.exclamationmark"
            )
            .foregroundStyle(.orange).font(.caption).textSelection(.enabled)
        case .unreadable(let reason)?:
            Label("The silo cannot read it: \(reason)", systemImage: "exclamationmark.octagon")
                .foregroundStyle(.red).font(.caption).textSelection(.enabled)
        case nil:
            Label("Checking with the silo…", systemImage: "clock").foregroundStyle(.secondary).font(.caption)
        }
    }
}

/// Before a container draft is stored: its document's difference from the sidecar it was based on,
/// and the silo's findings. When another edit landed first, that sidecar's container and how it
/// differs from the base, with the draft kept to be re-based on it or discarded; the console never
/// merges.
struct ContainerReviewSheet: View {
    let review: ConsoleModel.ContainerReview
    let model: ConsoleModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let landed = review.landed {
                Text("Someone Edited \(review.draft.title) First").font(.title3.bold())
                Text(
                    "The library's sidecar changed after this draft was made. This is how what landed differs from the draft's base; the draft is kept as it is."
                )
                .foregroundStyle(.secondary)
                DifferenceView(
                    lines: LineDifference.lines(
                        from: review.draft.baseText,
                        to: (try? ContainerDraft.document(of: landed.sidecar)) ?? ""
                    )
                )
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { dismiss() }
                    Button("Discard the Draft", role: .destructive) { model.discardContainerDraft(for: review.silo) }
                    Button("Re-base on It") { model.rebaseContainerDraft(on: landed, for: review.silo) }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                Text(review.draft.isNew ? "Make \(review.draft.title)" : "Store the Edit to \(review.draft.title)")
                    .font(.title3.bold())
                Text(
                    review.draft.isNew
                        ? "A new container in \(review.draft.library), with no presentations\(review.draft.creating?.parent == nil ? "" : ". Its parent's own fields are edited to name it first")."
                        : "The difference from the sidecar it was based on, in \(review.draft.library). Only the container's own fields change; its presentations, children and rules stay as they are, and no folder is renamed."
                )
                .foregroundStyle(.secondary)
                DifferenceView(lines: LineDifference.changes(from: review.draft.baseText, to: review.draft.text))
                ContainerVerdict(check: review.check)
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { dismiss() }
                    Button("Store") { Task { await model.storeContainer() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(!storable)
                }
            }
        }
        .padding()
        .frame(minWidth: 560, minHeight: 360)
    }

    private var storable: Bool {
        if case .wouldWrite? = review.check { return true }
        return false
    }
}
#endif
