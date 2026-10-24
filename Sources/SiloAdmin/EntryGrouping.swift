// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

#if canImport(SwiftUI)
import SiloAdminKit
import SmdKit
import SwiftUI

/// A draft container's entries, grouped into containers beneath it by the operator: entries are
/// selected, then made a new group of a kind the operator names or added to a group made already. A
/// group is selected whole, and its entries are shown in it, each only to be taken out of it. Runs of
/// entries TMDb titles as the parts of one story are bracketed, and offered as a serial titled by it.
struct EntryGrouping: View {
    let tree: TMDbTree
    let parent: String
    /// Changes the draft, as the sheet the grouping is in keeps it.
    let update: ((inout TMDbTree) -> Void) -> Void
    let provisionalID: () async -> ContainerID?
    @State private var selected: Set<ItemID> = []
    @State private var forming = false
    @State private var groupTitle = ""
    @State private var groupType: ContainerType = .serial
    @State private var groupLabel = ""

    private var container: Container? { tree.container(parent) }
    private var suggested: [SuggestedGroup] { tree.suggestedGroups(in: parent) }

    var body: some View {
        if let container {
            GroupBox {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(container.sequences.flatMap(\.items), id: \.self) { entry in row(entry) }
                    actions
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Text("Its entries: select some to group them into a container beneath it")
            }
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func row(_ entry: Entry) -> some View {
        if let child = entry.childContainer {
            if let group = tree.container(child.value), tree.documents[child.value] != nil, let item = entry.id {
                groupRow(group, item: item)
            } else {
                Text("↳ \(tree.container(child.value)?.displayTitle ?? child.value)").foregroundStyle(.secondary)
            }
        } else if let item = entry.id {
            HStack(spacing: 4) {
                bracket(item)
                Toggle(isOn: selecting(item)) { Text(title(of: entry)) }
                if let suggestion = suggested.first(where: { $0.items.first == item }) {
                    Spacer()
                    Text("] group as \(suggestion.title)").font(.caption).foregroundStyle(.blue)
                    Button("Group") { Task { await group(suggestion) } }.buttonStyle(.borderless).font(.caption)
                }
            }
        }
    }

    private func groupRow(_ group: Container, item: ItemID) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Toggle(isOn: selecting(item)) {
                    Text("\(group.typeLabel ?? group.type.title): \(group.displayTitle)").bold()
                }
                Spacer()
                Button("Ungroup") { change { $0.ungroup(group.id.value) } }.buttonStyle(.borderless).font(.caption)
            }
            ForEach(group.sequences.flatMap(\.items), id: \.self) { member in
                HStack {
                    // Taken with the group: only to be taken out of it.
                    Toggle(isOn: .constant(true)) { Text(title(of: member)) }.disabled(true)
                    if let id = member.id {
                        Button("Remove from Group") { change { $0.remove(id, from: group.id.value) } }
                            .buttonStyle(.borderless).font(.caption)
                    }
                }
                .padding(.leading, 20)
            }
        }
    }

    /// The bracket a suggested run's entries are drawn with: its top, its middle and its foot.
    @ViewBuilder
    private func bracket(_ item: ItemID) -> some View {
        let run = suggested.first { $0.items.contains(item) }
        let mark =
            switch run.map({ ($0.items.first == item, $0.items.last == item) }) {
            case (true, _)?: "┐"
            case (_, true)?: "┘"
            case _?: "│"
            case nil: " "
            }
        Text(mark).font(.body.monospaced()).foregroundStyle(.blue).frame(width: 10)
    }

    private func title(of entry: Entry) -> String {
        let tmdb = entry.externalRefs.first { $0.provider == .tmdb }
        return tmdb.flatMap { tree.episodeTitles[$0.value] } ?? entry.title ?? entry.id?.value ?? "a reference"
    }

    private func selecting(_ item: ItemID) -> Binding<Bool> {
        Binding(
            get: { selected.contains(item) },
            set: { on in
                if on { selected.insert(item) } else { selected.remove(item) }
            }
        )
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        if !selected.isEmpty {
            HStack {
                Text("\(selected.count) selected").font(.caption).foregroundStyle(.secondary)
                Button("New Group…") { forming = true }
                let groups = tree.groups(in: parent).filter { group in
                    !selected.contains { item in isEntry(item, of: group) }
                }
                if !groups.isEmpty {
                    Menu("Add to Group") {
                        ForEach(groups, id: \.id) { group in
                            Button(group.displayTitle) {
                                let items = leaves(of: selected)
                                change { $0.add(items, to: group.id.value) }
                            }
                        }
                    }
                    .fixedSize()
                }
                Button("Clear") { selected = [] }.buttonStyle(.borderless)
            }
            if forming {
                HStack {
                    TextField("Title", text: $groupTitle)
                    Picker("Kind", selection: $groupType) {
                        ForEach(ContainerType.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .fixedSize()
                    TextField("Label", text: $groupLabel).frame(maxWidth: 80)
                    Button("Group") { Task { await formGroup() } }.disabled(Title(groupTitle) == nil)
                    Button("Cancel") { forming = false }
                }
            }
        }
        if suggested.count > 1 {
            Button("Group All \(suggested.count) Suggested as Serials") {
                Task { for suggestion in suggested { await group(suggestion) } }
            }
            .font(.caption)
        }
    }

    /// Whether an entry of the container is the one that holds a group.
    private func isEntry(_ item: ItemID, of group: Container) -> Bool {
        container?.sequences.flatMap(\.items).contains { $0.id == item && $0.childContainer == group.id } ?? false
    }

    /// The selected entries that are not groups, in the container's order.
    private func leaves(of items: Set<ItemID>) -> [ItemID] {
        (container?.sequences.flatMap(\.items) ?? []).filter { $0.childContainer == nil }.compactMap(\.id)
            .filter(items.contains)
    }

    private func change(_ body: @escaping (inout TMDbTree) -> Void) {
        update(body)
        selected = []
    }

    private func formGroup() async {
        guard let title = Title(groupTitle), let id = await provisionalID() else { return }
        let order = (container?.sequences.flatMap(\.items) ?? []).compactMap(\.id).filter(selected.contains)
        let (type, label) = (groupType, groupLabel.isEmpty ? nil : groupLabel)
        change { $0.regroup(order, in: parent, into: id, type: type, typeLabel: label, title: title) }
        forming = false
        groupTitle = ""
        groupLabel = ""
    }

    private func group(_ suggestion: SuggestedGroup) async {
        guard let title = Title(suggestion.title), let id = await provisionalID() else { return }
        let parent = parent
        update { $0.regroup(suggestion.items, in: parent, into: id, type: .serial, title: title) }
        selected.subtract(suggestion.items)
    }
}
#endif
