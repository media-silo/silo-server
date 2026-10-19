// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

#if canImport(SwiftUI)
import SiloAdminKit
import SmdKit
import SwiftUI

/// A container's own fields as a form: its title, year, type, type label, outline, whether it is
/// listed, and its external references; and its alternatives, features, sequences, items and extras,
/// each added, edited, removed and reordered. Every change hands back the whole container, which the
/// draft writes as its document; what the change does to the library's facts is the silo's dry run
/// to say, not the form's.
struct ContainerForm: View {
    let container: Container
    let onChange: (Container) -> Void

    var body: some View {
        Form {
            Section("Container") {
                TextField("Title", text: bind({ $0.title.rawValue }, { container, text in
                    if let title = Title(text) { container.title = title }
                }))
                Picker("Type", selection: bind({ $0.type }, { $0.type = $1 })) {
                    ForEach(ContainerType.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                TextField("Type label", text: bind({ $0.typeLabel ?? "" }, { $0.typeLabel = $1.isEmpty ? nil : $1 }))
                TextField("Year", text: bind({ $0.year.map(String.init) ?? "" }, { container, text in
                    let trimmed = text.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty { container.year = nil } else if let year = Int(trimmed) { container.year = year }
                }))
                Toggle("Year in title", isOn: bind({ $0.yearInTitle }, { $0.yearInTitle = $1 }))
                TextField("Outline", text: bind({ $0.outline ?? "" }, { $0.outline = $1.isEmpty ? nil : $1 }), axis: .vertical)
                    .lineLimit(2...6)
                Toggle("Listed", isOn: bind({ $0.listed }, { $0.listed = $1 }))
            }

            Section("External references") {
                ReferencesEditor(references: container.externalRefs) { references in
                    change { $0.externalRefs = references }
                }
            }

            Section("Alternatives") {
                ForEach(Array(container.alternatives.enumerated()), id: \.offset) { index, alternative in
                    HStack {
                        TextField("Id", text: bind({ $0.alternatives[index].id }, { $0.alternatives[index].id = $1 }))
                            .frame(maxWidth: 140)
                        Picker("Plays", selection: bind({ $0.alternatives[index].sequence }, { $0.alternatives[index].sequence = $1 })) {
                            ForEach(sequenceIDs(including: alternative.sequence), id: \.self) { Text($0).tag($0) }
                        }
                        .frame(maxWidth: 180)
                        TextField("Title", text: bind({ $0.alternatives[index].title ?? "" }, { $0.alternatives[index].title = $1.isEmpty ? nil : $1 }))
                        RowControls(index: index, count: container.alternatives.count) { from, to in
                            change { $0.alternatives.swapAt(from, to) }
                        } remove: {
                            change { $0.alternatives.remove(at: index) }
                        }
                    }
                }
                Picker("Default", selection: bind({ $0.defaultAlternative ?? "" }, { $0.defaultAlternative = $1.isEmpty ? nil : $1 })) {
                    Text("None").tag("")
                    ForEach(container.alternatives, id: \.id) { Text($0.title ?? $0.id).tag($0.id) }
                }
                Button("Add Alternative", systemImage: "plus") {
                    change { container in
                        container.alternatives.append(Alternative(id: Self.fresh("alternative", taken: container.alternatives.map(\.id)), sequence: container.sequences.first?.id ?? ""))
                    }
                }
            }

            Section("Features") {
                ForEach(Array(container.features.enumerated()), id: \.offset) { index, _ in
                    HStack {
                        TextField("Id", text: bind({ $0.features[index].id }, { $0.features[index].id = $1 }))
                            .frame(maxWidth: 140)
                        TextField("Type", text: bind({ $0.features[index].type.rawValue }, { $0.features[index].type = FeatureType(rawValue: $1) }))
                            .frame(maxWidth: 140)
                        TextField("Title", text: bind({ $0.features[index].title ?? "" }, { $0.features[index].title = $1.isEmpty ? nil : $1 }))
                        RowControls(index: index, count: container.features.count) { from, to in
                            change { $0.features.swapAt(from, to) }
                        } remove: {
                            change { $0.features.remove(at: index) }
                        }
                    }
                }
                Button("Add Feature", systemImage: "plus") {
                    change { container in
                        container.features.append(Feature(id: Self.fresh("feature", taken: container.features.map(\.id)), type: .commentary))
                    }
                }
            }

            ForEach(Array(container.sequences.enumerated()), id: \.offset) { index, sequence in
                Section {
                    HStack {
                        TextField("Sequence id", text: bind({ $0.sequences[index].id ?? "" }, { $0.sequences[index].id = $1.isEmpty ? nil : $1 }))
                        Picker("Exploded", selection: bind({ $0.sequences[index].exploded }, { $0.sequences[index].exploded = $1 })) {
                            ForEach(Exploded.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .frame(maxWidth: 200)
                        RowControls(index: index, count: container.sequences.count) { from, to in
                            change { $0.sequences.swapAt(from, to) }
                        } remove: {
                            change { $0.sequences.remove(at: index) }
                        }
                    }
                    EntriesEditor(entries: sequence.items, newType: .episode, taken: takenItemIDs) { items in
                        change { $0.sequences[index].items = items }
                    }
                } header: {
                    Text(sequence.id.map { "Sequence \($0)" } ?? "Sequence")
                }
            }
            Section {
                Button("Add Sequence", systemImage: "plus") {
                    change { container in
                        container.sequences.append(Sequence(id: Self.fresh("sequence", taken: container.sequences.compactMap(\.id))))
                    }
                }
            }

            Section("Extras") {
                EntriesEditor(entries: container.extras, newType: .featurette, taken: takenItemIDs) { extras in
                    change { $0.extras = extras }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var takenItemIDs: [String] {
        (container.sequences.flatMap(\.items) + container.extras).compactMap { $0.id?.value }
    }

    private func sequenceIDs(including current: String) -> [String] {
        let ids = container.sequences.compactMap(\.id)
        return ids.contains(current) ? ids : ids + [current]
    }

    private func change(_ edit: (inout Container) -> Void) {
        var changed = container
        edit(&changed)
        onChange(changed)
    }

    private func bind<Value>(_ get: @escaping (Container) -> Value, _ set: @escaping (inout Container, Value) -> Void) -> Binding<Value> {
        Binding(get: { get(container) }, set: { value in change { set(&$0, value) } })
    }

    /// An id not yet taken: the stem, then the stem with the first number that is free.
    static func fresh(_ stem: String, taken: [String]) -> String {
        guard taken.contains(stem) else { return stem }
        var number = 2
        while taken.contains("\(stem)\(number)") { number += 1 }
        return "\(stem)\(number)"
    }
}

/// A sequence's items, or the extras: each leaf's id, type and title, each child's id and title
/// beside the container it names, and each one moved, removed or added to.
private struct EntriesEditor: View {
    let entries: [Entry]
    let newType: EntryType
    let taken: [String]
    let onChange: ([Entry]) -> Void

    var body: some View {
        ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
            HStack {
                switch entry {
                case .leaf(let leaf):
                    TextField("Id", text: Binding(get: { leaf.id.value }, set: { text in
                        guard let id = ItemID(text) else { return }
                        update(index) { if case .leaf(var leaf) = $0 { leaf.id = id; $0 = .leaf(leaf) } }
                    }))
                    .frame(maxWidth: 120)
                    TextField("Type", text: Binding(get: { leaf.type.rawValue }, set: { text in
                        guard let type = EntryType(rawValue: text) else { return }
                        update(index) { if case .leaf(var leaf) = $0 { leaf.type = type; $0 = .leaf(leaf) } }
                    }))
                    .frame(maxWidth: 120)
                    TextField("Title", text: Binding(get: { leaf.title ?? "" }, set: { text in
                        update(index) { if case .leaf(var leaf) = $0 { leaf.title = text.isEmpty ? nil : text; $0 = .leaf(leaf) } }
                    }))
                case .child(let child):
                    TextField("Id", text: Binding(get: { child.id.value }, set: { text in
                        guard let id = ItemID(text) else { return }
                        update(index) { if case .child(var child) = $0 { child.id = id; $0 = .child(child) } }
                    }))
                    .frame(maxWidth: 120)
                    Text("container \(child.container.value)").font(.caption.monospaced()).foregroundStyle(.secondary)
                    TextField("Title", text: Binding(get: { child.title ?? "" }, set: { text in
                        update(index) { if case .child(var child) = $0 { child.title = text.isEmpty ? nil : text; $0 = .child(child) } }
                    }))
                case .ref:
                    Text("An item declared elsewhere").foregroundStyle(.secondary)
                    Spacer()
                }
                RowControls(index: index, count: entries.count) { from, to in
                    var moved = entries
                    moved.swapAt(from, to)
                    onChange(moved)
                } remove: {
                    var removed = entries
                    removed.remove(at: index)
                    onChange(removed)
                }
            }
        }
        Button("Add Item", systemImage: "plus") {
            let id = ContainerForm.fresh(newType == .featurette ? "extra" : "item", taken: taken)
            onChange(entries + [.leaf(Entry.Leaf(id: ItemID(id)!, type: newType))])
        }
    }

    private func update(_ index: Int, _ edit: (inout Entry) -> Void) {
        var changed = entries
        edit(&changed[index])
        onChange(changed)
    }
}

/// A container's external references: each a provider and a value.
private struct ReferencesEditor: View {
    let references: [ExternalRef]
    let onChange: ([ExternalRef]) -> Void

    var body: some View {
        ForEach(Array(references.enumerated()), id: \.offset) { index, reference in
            HStack {
                TextField("Provider", text: Binding(get: { reference.provider.rawValue }, set: { text in
                    var changed = references
                    changed[index].provider = Provider(rawValue: text)
                    onChange(changed)
                }))
                .frame(maxWidth: 140)
                TextField("Value", text: Binding(get: { reference.value }, set: { text in
                    var changed = references
                    changed[index].value = text
                    onChange(changed)
                }))
                RowControls(index: index, count: references.count) { from, to in
                    var moved = references
                    moved.swapAt(from, to)
                    onChange(moved)
                } remove: {
                    var removed = references
                    removed.remove(at: index)
                    onChange(removed)
                }
            }
        }
        Button("Add Reference", systemImage: "plus") {
            onChange(references + [ExternalRef(provider: .tmdb, value: "")])
        }
    }
}

/// Moving a row up or down among its siblings, and removing it.
private struct RowControls: View {
    let index: Int
    let count: Int
    let move: (Int, Int) -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Button("Move Up", systemImage: "chevron.up") { move(index, index - 1) }
                .disabled(index == 0)
            Button("Move Down", systemImage: "chevron.down") { move(index, index + 1) }
                .disabled(index == count - 1)
            Button("Remove", systemImage: "minus.circle", role: .destructive, action: remove)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
    }
}
#endif
