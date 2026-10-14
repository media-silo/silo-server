// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

#if canImport(SwiftUI)
import SwiftUI
import SiloAdminKit
import SiloKit

/// The form over a draft the reader can read; over one it cannot, the reader's refusal, for the text
/// to be edited until it reads.
struct DraftForm: View {
    let draft: Draft
    let apply: (String) -> Void

    var body: some View {
        if let text = try? RulesetText(draft.text) {
            RulesForm(text: text, apply: apply)
        } else if case .refused(let reason) = draft.reading {
            RefusalView(reason: reason + "\n\nThe form edits a draft the reader can read: edit the text until it reads.")
        }
    }
}

/// A draft edited in a form built from the rule language: its rules by scope in the order that
/// decides, each read as IF its conditions THEN its action, dragged by its handle to reorder, and its
/// outputs. Every change is a splice of the draft's text, handed back to be kept as an edit is, so
/// the text shows exactly what changed and nothing else.
struct RulesForm: View {
    let text: RulesetText
    let apply: (String) -> Void

    @State private var editing: RuleEdit?
    @State private var editingOutput: OutputEdit?

    var body: some View {
        // Each section's heading is its first row rather than its header, so that no heading is
        // pinned above the others while the list scrolls.
        List {
            ForEach(Scope.allCases, id: \.self) { scope in
                Section {
                    Heading(title: scope.rawValue.capitalized, add: "Add \(scope.rawValue.capitalized) Rule") {
                        editing = RuleEdit(scope: scope, position: nil, rule: Rule(scope: scope, action: .copy))
                    }
                    ForEach(Array(text.rules(of: scope).enumerated()), id: \.element.element) { position, entry in
                        let edit = { editing = RuleEdit(scope: scope, position: position, rule: entry.rule) }
                        let delete = { apply(text.deletingRule(position, of: scope)) }
                        ItemRow(edit: edit, delete: delete) {
                            RuleRow(rule: entry.rule, afterOthers: position > 0)
                        }
                    }
                    .onMove { from, to in
                        guard let position = from.first else { return }
                        apply(text.movingRule(position, of: scope, to: to))
                    }
                }
            }
            Section {
                Heading(title: "Outputs", add: "Add Output") {
                    editingOutput = OutputEdit(position: nil, output: OutputPolicy(profile: "mobile", container: "mp4"))
                }
                ForEach(Array(text.outputs.enumerated()), id: \.element.element) { position, entry in
                    let edit = { editingOutput = OutputEdit(position: position, output: entry.output) }
                    ItemRow(edit: edit, delete: { apply(text.deletingOutput(position)) }) {
                        HStack {
                            Text(entry.output.profile ?? "unqualified")
                            Spacer()
                            Text(entry.output.container).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .sheet(item: $editing) { edit in
            RuleEditor(edit: edit) { rule in
                if let position = edit.position {
                    apply(text.replacingRule(position, of: edit.scope, with: rule))
                } else {
                    apply(text.addingRule(rule))
                }
            }
        }
        .sheet(item: $editingOutput) { edit in
            OutputEditor(edit: edit) { output in
                if let position = edit.position {
                    apply(text.replacingOutput(position, with: output))
                } else {
                    apply(text.addingOutput(output))
                }
            }
        }
    }
}

struct RuleEdit: Identifiable {
    let id = UUID()
    var scope: Scope
    /// Its position within its scope; nil for a rule being added.
    var position: Int?
    var rule: Rule
}

struct OutputEdit: Identifiable {
    let id = UUID()
    var position: Int?
    var output: OutputPolicy
}

/// A section's heading, as a row of its own, with the button that adds to it.
private struct Heading: View {
    let title: String
    let add: String
    let action: () -> Void

    var body: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Button(add, systemImage: "plus", action: action)
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
                .help(add)
        }
        .padding(.top, 8)
        .listRowSeparator(.hidden)
    }
}

/// A rule or an output as a row: a handle to drag it by, what it is, and its edit button; swiped,
/// or from its menu, edited or deleted, and double-clicked, edited.
private struct ItemRow<Content: View>: View {
    let edit: () -> Void
    let delete: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            DragHandle()
            content
            Spacer(minLength: 0)
            Button("Edit", systemImage: "pencil", action: edit)
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
                .help("Edit")
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: edit)
        .contextMenu {
            Button("Edit…", action: edit)
            Button("Delete", role: .destructive, action: delete)
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive, action: delete)
            Button("Edit", systemImage: "pencil", action: edit).tint(.accentColor)
        }
    }
}

/// Two columns of three dots: the conventional mark of a row that can be dragged.
private struct DragHandle: View {
    var body: some View {
        Grid(horizontalSpacing: 3, verticalSpacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                GridRow {
                    Circle().frame(width: 3, height: 3)
                    Circle().frame(width: 3, height: 3)
                }
            }
        }
        .foregroundStyle(.tertiary)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .pointerStyle(.grabIdle)
        .help("Drag to reorder")
    }
}

/// A rule read as its clauses: its id when it has one, its conditions on a line, and its action on the
/// next, each line flowing onto another where the row is too narrow for it.
private struct RuleRow: View {
    let rule: Rule
    /// Whether another rule of its scope comes before it, so that it is reached only otherwise.
    let afterOthers: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let id = rule.id {
                Text(id).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            ForEach(Array(rule.reading(afterOthers: afterOthers).enumerated()), id: \.offset) { _, clauses in
                FlowLayout(spacing: 6, lineSpacing: 2) {
                    ForEach(Array(clauses.enumerated()), id: \.offset) { _, clause in
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(clause.keyword)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(clause.text)
                        }
                    }
                }
            }
        }
    }
}

/// Its subviews in a row, left to right, starting another row below when the next would not fit.
private struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, within: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, arrange(subviews, within: bounds.width).frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    /// Where each subview goes, and the size they take together. A subview wider than the whole
    /// width is given the whole width, to wrap within it.
    private func arrange(_ subviews: Subviews, within width: CGFloat) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            if size.width > width { size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil)) }
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (frames, CGSize(width: widest, height: y + rowHeight))
    }
}

/// One rule's fields: its id, its conditions chosen from the facts its scope can test, each offering
/// only the tests the fact takes, named in words, and, where its values are a closed set, only those,
/// or otherwise any with the values it is commonly met with suggested; and its action, an encode
/// starting with an encoder of the rule's scope.
private struct RuleEditor: View {
    let edit: RuleEdit
    let save: (Rule) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var id = ""
    @State private var conditions: [ConditionRow] = []
    @State private var action = ActionKind.copy
    @State private var codec = ""
    @State private var preset = ""
    @State private var crf = ""
    @State private var bitrate = ""
    @State private var channels = ""
    @State private var pixelFormat = ""

    struct ConditionRow: Identifiable {
        let id = UUID()
        var fact: FactKey
        var test: String
        /// The value of every test but `in`.
        var value: String
        /// The values of an `in`, each a field of its own.
        var members: [String] = []

        /// The value as the document writes it.
        var attributeValue: String {
            test == "in" ? members.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: ",") : value
        }
    }

    enum ActionKind: String, CaseIterable, Identifiable {
        case copy, drop, encode
        var id: String { rawValue }
    }

    private var facts: [FactKey] { FactKey.allCases.filter { $0.isVisible(in: edit.scope) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(edit.position == nil ? "New \(edit.scope.rawValue.capitalized) Rule" : "Edit \(edit.scope.rawValue.capitalized) Rule").font(.headline)
            Form {
                TextField("Id", text: $id, prompt: Text("none: named by its position"))
                Section("Conditions") {
                    ForEach($conditions) { $row in
                        HStack(alignment: .firstTextBaseline) {
                            Picker("Fact", selection: $row.fact) {
                                ForEach(facts, id: \.self) { Text($0.name(in: edit.scope)).tag($0) }
                            }
                            .labelsHidden()
                            .onChange(of: row.fact) { _, fact in
                                if !fact.tests.contains(row.test) { row.test = "is" }
                                if let values = fact.values {
                                    if !values.contains(row.value) { row.value = values[0] }
                                    row.members = row.members.filter(values.contains)
                                }
                            }
                            Picker("Test", selection: $row.test) {
                                ForEach(row.fact.tests, id: \.self) { Text(Condition.Test.label(of: $0)).tag($0) }
                            }
                            .labelsHidden()
                            .fixedSize()
                            .onChange(of: row.test) { previous, test in
                                if test == "in", row.members.isEmpty {
                                    row.members = row.value.isEmpty ? [""] : [row.value]
                                } else if previous == "in", let first = row.members.first(where: { !$0.isEmpty }) {
                                    row.value = first
                                }
                            }
                            if row.test == "in" {
                                MembersField(fact: row.fact, members: $row.members)
                            } else if let values = row.fact.values {
                                Picker("Value", selection: $row.value) {
                                    ForEach(values, id: \.self) { Text($0).tag($0) }
                                }
                                .labelsHidden()
                            } else {
                                SuggestedField(title: "Value", text: $row.value, prompt: row.fact.isNumeric ? "number" : "value", suggestions: row.fact.suggestedValues)
                            }
                            Button("Remove", systemImage: "minus.circle") { conditions.removeAll { $0.id == row.id } }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                        }
                    }
                    Button("Add Condition", systemImage: "plus") {
                        let fact = facts[0]
                        conditions.append(ConditionRow(fact: fact, test: "is", value: fact.values?.first ?? ""))
                    }
                    .buttonStyle(.borderless)
                }
                Section("Action") {
                    Picker("Action", selection: $action) {
                        ForEach(ActionKind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if action == .encode {
                        SuggestedField(title: "Codec", text: $codec, prompt: edit.scope.codecs[0].codec, suggestions: edit.scope.codecs.map(\.codec), labelled: true)
                        if takes(.preset) { TextField("Preset", text: $preset) }
                        if takes(.crf) { TextField("CRF", text: $crf) }
                        if takes(.bitrate) { TextField("Bitrate", text: $bitrate, prompt: Text(edit.scope == .video ? "8M" : "96k")) }
                        if takes(.channels) { TextField("Channels", text: $channels) }
                        if takes(.pixelFormat) { TextField("Pixel format", text: $pixelFormat) }
                        if edit.scope.settings(forCodec: codec).isEmpty {
                            Text("A \(edit.scope.rawValue) encode takes no settings.").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.caption)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button(edit.position == nil ? "Add" : "Save") {
                    if let rule { save(rule); dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(rule == nil)
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 420)
        .onAppear(perform: load)
    }

    private func load() {
        id = edit.rule.id ?? ""
        conditions = edit.rule.conditions.map { condition in
            if case .oneOf(let members) = condition.test {
                return ConditionRow(fact: condition.fact, test: "in", value: members.first ?? "", members: members)
            }
            let (test, value) = condition.test.attribute
            return ConditionRow(fact: condition.fact, test: test, value: value)
        }
        codec = edit.scope.codecs[0].codec
        switch edit.rule.action {
        case .copy: action = .copy
        case .drop: action = .drop
        case .encode(let settings):
            action = .encode
            codec = edit.scope.codec(ofEncoder: settings.codec)
            preset = settings.preset ?? ""
            crf = settings.crf.map(String.init) ?? ""
            bitrate = settings.bitrate ?? ""
            channels = settings.channels.map(String.init) ?? ""
            pixelFormat = settings.pixelFormat ?? ""
        }
    }

    /// Whether the encode's codec takes the setting, and so shows its field.
    private func takes(_ setting: EncodeSetting) -> Bool {
        edit.scope.settings(forCodec: codec.trimmingCharacters(in: .whitespaces)).contains(setting)
    }

    /// What the fields say is wrong, before the reader is asked.
    private var problem: String? {
        if let row = conditions.first(where: { $0.test == "in" && $0.attributeValue.isEmpty }) {
            return "\(row.fact.name(in: edit.scope)) one of needs a value"
        }
        if let row = conditions.first(where: { Condition.Test(attribute: $0.test, value: $0.attributeValue) == nil }) {
            return "\(row.fact.name(in: edit.scope)) \(Condition.Test.label(of: row.test)) needs a number"
        }
        if action == .encode {
            if codec.trimmingCharacters(in: .whitespaces).isEmpty { return "An encode needs a codec" }
            if takes(.crf), !crf.isEmpty, Int(crf) == nil { return "CRF is a whole number" }
            if takes(.channels), !channels.isEmpty, Int(channels) == nil { return "Channels is a whole number" }
        }
        return nil
    }

    /// The rule the fields make, keeping what the form does not show — an encode's filters and options.
    private var rule: Rule? {
        guard problem == nil else { return nil }
        let made: Action
        switch action {
        case .copy: made = .copy
        case .drop: made = .drop
        case .encode:
            var settings: EncodeSettings
            if case .encode(let existing) = edit.rule.action { settings = existing } else { settings = EncodeSettings(codec: codec) }
            settings.codec = edit.scope.encoder(forCodec: codec.trimmingCharacters(in: .whitespaces))
            // A setting the codec does not take is not written, whatever its field held before the
            // codec changed.
            settings.preset = takes(.preset) && !preset.isEmpty ? preset : nil
            settings.crf = takes(.crf) ? Int(crf) : nil
            settings.bitrate = takes(.bitrate) && !bitrate.isEmpty ? bitrate : nil
            settings.channels = takes(.channels) ? Int(channels) : nil
            settings.pixelFormat = takes(.pixelFormat) && !pixelFormat.isEmpty ? pixelFormat : nil
            made = .encode(settings)
        }
        let trimmed = id.trimmingCharacters(in: .whitespaces)
        return Rule(
            id: trimmed.isEmpty ? nil : trimmed,
            scope: edit.scope,
            conditions: conditions.compactMap { row in Condition.Test(attribute: row.test, value: row.attributeValue).map { Condition(row.fact, $0) } },
            action: made
        )
    }
}

/// The values of a `one of`: each a field of its own, added and removed one by one; for a fact whose
/// values are a closed set, a checkbox for each instead.
private struct MembersField: View {
    let fact: FactKey
    @SwiftUI.Binding var members: [String]

    var body: some View {
        if let values = fact.values {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(values, id: \.self) { value in
                    Toggle(value, isOn: SwiftUI.Binding(
                        get: { members.contains(value) },
                        set: { on in members = values.filter { $0 == value ? on : members.contains($0) } }
                    ))
                    .toggleStyle(.checkbox)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(members.indices, id: \.self) { index in
                    HStack {
                        SuggestedField(title: "Value", text: $members[index], prompt: fact.isNumeric ? "number" : "value", suggestions: fact.suggestedValues)
                        Button("Remove Value", systemImage: "minus") { members.remove(at: index) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .disabled(members.count == 1)
                    }
                }
                Button("Add Value", systemImage: "plus") { members.append("") }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Add another value")
            }
        }
    }
}

/// A field that takes any text, with the values it is commonly given offered from a menu beside it.
private struct SuggestedField: View {
    let title: String
    @SwiftUI.Binding var text: String
    var prompt: String
    var suggestions: [String]
    /// Whether the title shows, as a form's field shows it; a condition's value hides it.
    var labelled = false

    var body: some View {
        HStack(spacing: 4) {
            if labelled {
                TextField(title, text: $text, prompt: Text(prompt))
            } else {
                TextField(title, text: $text, prompt: Text(prompt)).labelsHidden()
            }
            if !suggestions.isEmpty {
                Menu {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button(suggestion) { text = suggestion }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(.borderless)
                .fixedSize()
                .help("Common values")
            }
        }
    }
}

private struct OutputEditor: View {
    let edit: OutputEdit
    let save: (OutputPolicy) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var profile = ""
    @State private var container = "mkv"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(edit.position == nil ? "New Output" : "Edit Output").font(.headline)
            Form {
                TextField("Profile", text: $profile, prompt: Text("none: the unqualified output"))
                TextField("Container", text: $container)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button(edit.position == nil ? "Add" : "Save") {
                    save(OutputPolicy(profile: profile.isEmpty ? nil : profile, container: container))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(container.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 380)
        .onAppear {
            profile = edit.output.profile ?? ""
            container = edit.output.container
        }
    }
}
#endif
