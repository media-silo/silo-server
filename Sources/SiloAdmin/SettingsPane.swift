// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

#if canImport(SwiftUI)
import SwiftUI
import SiloAdminKit
import SiloClient

/// A with-access silo's settings, as the silo reports them: what a route changes, editable, and
/// the facts of its machine — where it listens, its id, where its state lives — read-only, since no
/// route changes them. Each change goes to the silo as it is made, and what the silo answers is what
/// the pane then shows. The libraries have a section of their own.
struct SettingsPane: View {
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
                        Toggle(
                            "Encode on this silo",
                            isOn: Binding(
                                get: { report.editable.embeddedNode },
                                set: { save(SiloClient.SettingsPatch(embeddedNode: $0)) }
                            )
                        )
                        Toggle(
                            "Advertise on the network",
                            isOn: Binding(
                                get: { report.editable.advertise },
                                set: { save(SiloClient.SettingsPatch(advertise: $0)) }
                            )
                        )
                    }
                    Section {
                        LabeledContent("Listens on", value: "\(report.readOnly.host):\(report.readOnly.port)")
                        LabeledContent("Server ID", value: report.readOnly.serverID)
                        LabeledContent("State directory", value: report.readOnly.stateDirectory)
                            .textSelection(.enabled)
                        LabeledContent(
                            "Library roots",
                            value: report.readOnly.libraryRoots.isEmpty
                                ? "None" : report.readOnly.libraryRoots.joined(separator: "\n")
                        )
                        .textSelection(.enabled)
                    } header: {
                        Text("This Silo's Machine")
                    } footer: {
                        Text(
                            "Set in silo.json on the silo's machine. The state directory is where operator-credential.reset goes; a library added from the console must lie within one of the library roots."
                        )
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
struct LibrariesPane: View {
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
                                    description: Text(
                                        report.editable.libraries.isEmpty
                                            ? "Add a library within the roots the silo's owner named."
                                            : "Choose a library to see its path and last walk, or a container in it to see what its sidecar says."
                                    )
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
                onCheck: { id, folder, root, create in
                    await model.checkLibrary(id: id, folder: folder, within: root, create: create, on: silo)
                },
                onAdd: { id, folder, root, create in
                    await model.addLibrary(id: id, folder: folder, within: root, create: create, on: silo)
                }
            )
        }
        .sheet(item: $model.containerReview) { review in
            ContainerReviewSheet(review: review, model: model)
        }
        .alert(
            "Remove \(removingLibrary ?? "the library")?",
            isPresented: Binding(
                get: { removingLibrary != nil },
                set: { if !$0 { removingLibrary = nil } }
            )
        ) {
            Button("Remove", role: .destructive) {
                if let library = removingLibrary {
                    Task { await model.removeLibrary(library, on: silo) }
                }
            }
            Button("Cancel", role: .cancel) { removingLibrary = nil }
        } message: {
            Text(
                "The silo forgets the library and its index. Nothing on the silo's disk is touched: every sidecar and media file stays where it is."
            )
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
                        Label(
                            "Unavailable: its folder is missing, or holds nothing where the silo's index holds something. Its containers are kept, and it is walked again when the folder returns.",
                            systemImage: "externaldrive.badge.exclamationmark"
                        )
                        .foregroundStyle(.orange)
                    }
                    LabeledContent("Last walk") {
                        if let walk {
                            Text(
                                walk.walkedAt.formatted(.relative(presentation: .named))
                                    + (walk.available
                                        ? ": \(walk.report.read) read, \(walk.report.unchanged) unchanged, \(walk.report.removed) removed"
                                        : "")
                            )
                        } else {
                            Text("Not yet walked")
                        }
                    }
                    ForEach(walk?.report.findings ?? [], id: \.self) { finding in
                        Label(
                            finding.path.map { "\($0): \(finding.text)" } ?? finding.text,
                            systemImage: finding.severity == .error
                                ? "exclamationmark.octagon" : "exclamationmark.triangle"
                        )
                        .foregroundStyle(finding.severity == .error ? .red : .orange)
                        .textSelection(.enabled)
                    }
                    Picker(
                        "Standard",
                        selection: Binding(
                            get: { listed?.ruleset ?? "" },
                            set: { chosen in
                                Task {
                                    await model.setStandard(chosen.isEmpty ? nil : chosen, of: library.id, on: silo)
                                }
                            }
                        )
                    ) {
                        Text("None").tag("")
                        ForEach(model.rulesets[silo.id] ?? [], id: \.name) { Text($0.name).tag($0.name) }
                    }
                } footer: {
                    Text(
                        "A library's standard is the ruleset an application takes when it names none. The silo walks each library itself — at startup, when a missing folder returns, and every five minutes — so there is nothing to rescan."
                    )
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
                return (
                    "A library cannot be created at ",
                    ". The \(folders) in red \(count == 1 ? "does" : "do") not exist."
                )
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
                Text(
                    "This silo has no library roots. Its owner names the folders a library may be added within in silo.json, on the silo's machine; until then nothing can be added from here."
                )
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
                        Text(
                            "\(saying.before)\(Text(check.present).foregroundStyle(.green))\(Text(check.absent).foregroundStyle(absentColor(check)))\(saying.after)"
                        )
                        .font(.callout)
                        .textSelection(.enabled)
                        if !check.creates.isEmpty, check.refusal?.status != 403 {
                            Toggle(
                                check.creates.count == 1
                                    ? "Create the missing folder" : "Create the \(check.creates.count) missing folders",
                                isOn: $create
                            )
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
            } else if let check = current, let refusal = check.refusal, !name.isEmpty,
                !check.refusesPath(create: create)
            {
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
#endif
