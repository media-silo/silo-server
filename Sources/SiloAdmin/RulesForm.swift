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
/// decides, dragged to reorder, and its outputs. Every change is a splice of the draft's text, handed
/// back to be kept as an edit is, so the text shows exactly what changed and nothing else.
struct RulesForm: View {
    let text: RulesetText
    let apply: (String) -> Void

    @State private var editing: RuleEdit?
    @State private var editingOutput: OutputEdit?

    var body: some View {
        List {
            ForEach(Scope.allCases, id: \.self) { scope in
                Section {
                    ForEach(Array(text.rules(of: scope).enumerated()), id: \.element.element) { position, entry in
                        RuleRow(name: entry.rule.id ?? "#\(ruleNumber(of: entry.element))", rule: entry.rule)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { editing = RuleEdit(scope: scope, position: position, rule: entry.rule) }
                            .contextMenu {
                                Button("Edit…") { editing = RuleEdit(scope: scope, position: position, rule: entry.rule) }
                                Button("Delete", role: .destructive) { apply(text.deletingRule(position, of: scope)) }
                            }
                    }
                    .onMove { from, to in
                        guard let position = from.first else { return }
                        apply(text.movingRule(position, of: scope, to: to))
                    }
                } header: {
                    HStack {
                        Text(scope.rawValue.capitalized)
                        Spacer()
                        Button("Add Rule", systemImage: "plus") { editing = RuleEdit(scope: scope, position: nil, rule: Rule(scope: scope, action: .copy)) }
                            .buttonStyle(.borderless)
                            .labelStyle(.iconOnly)
                            .help("Add a \(scope.rawValue) rule after the scope's last")
                    }
                }
            }
            Section {
                ForEach(Array(text.outputs.enumerated()), id: \.element.element) { position, entry in
                    HStack {
                        Text(entry.output.profile ?? "unqualified")
                        Spacer()
                        Text(entry.output.container).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { editingOutput = OutputEdit(position: position, output: entry.output) }
                    .contextMenu {
                        Button("Edit…") { editingOutput = OutputEdit(position: position, output: entry.output) }
                        Button("Delete", role: .destructive) { apply(text.deletingOutput(position)) }
                    }
                }
            } header: {
                HStack {
                    Text("Outputs")
                    Spacer()
                    Button("Add Output", systemImage: "plus") { editingOutput = OutputEdit(position: nil, output: OutputPolicy(profile: "mobile", container: "mp4")) }
                        .buttonStyle(.borderless)
                        .labelStyle(.iconOnly)
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

    /// A rule's position among all the document's rules, as a recipe names one without an id.
    private func ruleNumber(of element: RulesetText.Element) -> Int {
        (text.rules.firstIndex { $0.element == element } ?? 0) + 1
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

private struct RuleRow: View {
    let name: String
    let rule: Rule

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(name).font(.body.monospaced())
                Spacer()
                Text(rule.action.summary).foregroundStyle(.secondary)
            }
            Text(rule.conditions.isEmpty ? "every stream" : rule.conditions.map { condition in
                let (test, value) = condition.test.attribute
                return "\(condition.fact.rawValue) \(test) \(value)"
            }.joined(separator: " and "))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

/// One rule's fields: its id, its conditions chosen from the facts its scope can test, each offering
/// only the tests the fact takes and, where its values are a closed set, only those, and its action.
private struct RuleEditor: View {
    let edit: RuleEdit
    let save: (Rule) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var id = ""
    @State private var conditions: [ConditionRow] = []
    @State private var action = ActionKind.copy
    @State private var codec = "aac"
    @State private var preset = ""
    @State private var crf = ""
    @State private var bitrate = ""
    @State private var channels = ""
    @State private var pixelFormat = ""

    struct ConditionRow: Identifiable {
        let id = UUID()
        var fact: FactKey
        var test: String
        var value: String
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
                        HStack {
                            Picker("Fact", selection: $row.fact) {
                                ForEach(facts, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                            .labelsHidden()
                            .onChange(of: row.fact) { _, fact in
                                if !fact.tests.contains(row.test) { row.test = "is" }
                                if let values = fact.values, !values.contains(row.value) { row.value = values[0] }
                            }
                            Picker("Test", selection: $row.test) {
                                ForEach(row.fact.tests, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden()
                            .fixedSize()
                            if let values = row.fact.values, row.test != "in" {
                                Picker("Value", selection: $row.value) {
                                    ForEach(values, id: \.self) { Text($0).tag($0) }
                                }
                                .labelsHidden()
                            } else {
                                TextField("Value", text: $row.value, prompt: Text(row.test == "in" ? "a, b, c" : "value"))
                                    .labelsHidden()
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
                        TextField("Codec", text: $codec)
                        TextField("Preset", text: $preset)
                        TextField("CRF", text: $crf)
                        TextField("Bitrate", text: $bitrate, prompt: Text("96k"))
                        TextField("Channels", text: $channels)
                        TextField("Pixel format", text: $pixelFormat)
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
            let (test, value) = condition.test.attribute
            return ConditionRow(fact: condition.fact, test: test, value: value)
        }
        switch edit.rule.action {
        case .copy: action = .copy
        case .drop: action = .drop
        case .encode(let settings):
            action = .encode
            codec = settings.codec
            preset = settings.preset ?? ""
            crf = settings.crf.map(String.init) ?? ""
            bitrate = settings.bitrate ?? ""
            channels = settings.channels.map(String.init) ?? ""
            pixelFormat = settings.pixelFormat ?? ""
        }
    }

    /// What the fields say is wrong, before the reader is asked.
    private var problem: String? {
        if let row = conditions.first(where: { Condition.Test(attribute: $0.test, value: $0.value) == nil }) {
            return "\(row.fact.rawValue) \(row.test) needs a number"
        }
        if action == .encode {
            if codec.trimmingCharacters(in: .whitespaces).isEmpty { return "An encode needs a codec" }
            if !crf.isEmpty, Int(crf) == nil { return "CRF is a whole number" }
            if !channels.isEmpty, Int(channels) == nil { return "Channels is a whole number" }
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
            settings.codec = codec.trimmingCharacters(in: .whitespaces)
            settings.preset = preset.isEmpty ? nil : preset
            settings.crf = Int(crf)
            settings.bitrate = bitrate.isEmpty ? nil : bitrate
            settings.channels = Int(channels)
            settings.pixelFormat = pixelFormat.isEmpty ? nil : pixelFormat
            made = .encode(settings)
        }
        let trimmed = id.trimmingCharacters(in: .whitespaces)
        return Rule(
            id: trimmed.isEmpty ? nil : trimmed,
            scope: edit.scope,
            conditions: conditions.compactMap { row in Condition.Test(attribute: row.test, value: row.value).map { Condition(row.fact, $0) } },
            action: made
        )
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
