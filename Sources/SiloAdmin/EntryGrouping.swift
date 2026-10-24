// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

#if canImport(SwiftUI)
import SiloAdminKit
import SmdKit
import SwiftUI

/// One entry a grouping list shows, by the key it is selected by.
struct GroupingMember: Identifiable, Hashable {
    let id: String
    let title: String
}

/// A group made in a grouping list: the container its entries are to be in.
struct GroupingGroup: Identifiable {
    let id: String
    /// What it is selected by among the members, to be grouped itself; nil when it is not.
    var key: String?
    let title: String
    let kind: String
    let members: [GroupingMember]
}

enum GroupingRow: Identifiable {
    case member(GroupingMember)
    case group(GroupingGroup)
    /// An entry shown and never grouped, as a container held beneath already is.
    case fixed(id: String, String)

    var id: String {
        switch self {
        case .member(let member): "member:\(member.id)"
        case .group(let group): "group:\(group.id)"
        case .fixed(let id, _): "fixed:\(id)"
        }
    }
}

/// A run of entries TMDb titles as the parts of one story, offered as a group titled by it.
struct GroupingSuggestion: Hashable {
    let title: String
    let members: [String]
}

/// Entries grouped into containers by the operator, the actions first, in one menu: the entries chosen
/// made a new group of the kind chosen, or put into a group made already. A group is ticked whole, and
/// its entries are shown in it, each only to be taken out of it. A group, and each run TMDb titles as
/// one story's parts, is bracketed on the right of its entries' titles, its title or the suggestion
/// beside the bracket's middle. No kind is assumed: the kind the container's own groups are is offered
/// first, and the operator chooses. How many are chosen is said by the list's heading.
struct GroupingList: View {
    let rows: [GroupingRow]
    let suggestions: [GroupingSuggestion]
    let defaultKind: ContainerType?
    /// The word for the members chosen: selected to be grouped, or ticked to be taken and grouped.
    let chosenWord: String
    @Binding var chosen: Set<String>
    let groupTick: (GroupingGroup) -> Binding<Bool>
    let form: (_ members: [String], _ title: Title, _ type: ContainerType, _ label: String?) async -> Void
    let add: (_ members: [String], _ group: String) -> Void
    let remove: (_ member: String, _ group: String) -> Void
    let ungroup: (_ group: String) -> Void
    /// The kind of the new group being titled, while it is.
    @State private var forming: ContainerType?
    @State private var groupTitle = ""
    @State private var groupLabel = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            actions
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                ForEach(segments, id: \.id) { segment in view(of: segment) }
            }
        }
    }

    // MARK: Actions

    private var members: [GroupingMember] {
        rows.compactMap { if case .member(let member) = $0 { member } else { nil } }
    }

    private var groups: [GroupingGroup] {
        rows.compactMap { if case .group(let group) = $0 { group } else { nil } }
    }

    /// The members chosen, and the groups selected among them, in the list's order.
    private var chosenMembers: [String] {
        rows.compactMap { row in
            switch row {
            case .member(let member): member.id
            case .group(let group): group.key
            case .fixed: nil
            }
        }
        .filter(chosen.contains)
    }

    /// Every kind a group may be, the one the container's own groups are first.
    private var kinds: [ContainerType] {
        (defaultKind.map { [$0] } ?? []) + ContainerType.allCases.filter { $0 != defaultKind }
    }

    /// One menu, so the row holds at any width: the members chosen made a new group of a kind, or put
    /// into a group made already. Every suggestion grouped at once is a menu on a row of its own, there
    /// only while there are suggestions.
    @ViewBuilder
    private var actions: some View {
        Menu("Group \(chosenWord.capitalized)") {
            Section("\(chosenMembers.count) \(chosenWord)") {
                Menu("New Group") {
                    ForEach(kinds, id: \.self) { kind in Button(kind.title) { forming = kind } }
                }
                ForEach(groups) { group in
                    Button("Into \(group.title)") { add(chosenMembers, group.id) }
                }
            }
        }
        .fixedSize()
        .disabled(chosenMembers.isEmpty)
        // The suggestions on a row of their own, so accepting them is not hidden among the chosen's actions.
        if !suggestions.isEmpty {
            Menu(suggestions.count == 1 ? "Group the Suggested, as" : "Group All \(suggestions.count) Suggested, as") {
                ForEach(kinds, id: \.self) { kind in
                    Button(kind.title) {
                        Task { for suggestion in suggestions { await group(suggestion, as: kind) } }
                    }
                }
            }
            .fixedSize()
        }
        if let forming {
            HStack {
                Text("New \(forming.title)").font(.caption)
                TextField("Title", text: $groupTitle)
                TextField("Label", text: $groupLabel).frame(maxWidth: 100)
                Button("Group") { Task { await formGroup(as: forming) } }.disabled(Title(groupTitle) == nil)
                Button("Cancel") { self.forming = nil }
            }
        }
    }

    private func formGroup(as kind: ContainerType) async {
        guard let title = Title(groupTitle) else { return }
        let label = groupLabel.trimmingCharacters(in: .whitespaces)
        await form(chosenMembers, title, kind, label.isEmpty ? nil : label)
        forming = nil
        groupTitle = ""
        groupLabel = ""
    }

    private func group(_ suggestion: GroupingSuggestion, as kind: ContainerType) async {
        guard let title = Title(suggestion.title) else { return }
        await form(suggestion.members, title, kind, nil)
    }

    // MARK: Rows

    private enum Segment {
        case row(GroupingRow)
        case suggested(GroupingSuggestion, [GroupingMember])

        var id: String {
            switch self {
            case .row(let row): row.id
            case .suggested(let suggestion, _): "suggested:\(suggestion.members.first ?? suggestion.title)"
            }
        }
    }

    /// The rows, each run suggested as a group gathered to be bracketed together.
    private var segments: [Segment] {
        var segments: [Segment] = []
        var index = rows.startIndex
        while index < rows.endIndex {
            if case .member(let member) = rows[index],
                let suggestion = suggestions.first(where: { $0.members.first == member.id })
            {
                let run = rows[index...].prefix(suggestion.members.count).compactMap { row -> GroupingMember? in
                    if case .member(let member) = row, suggestion.members.contains(member.id) { member } else { nil }
                }
                if run.count == suggestion.members.count {
                    segments.append(.suggested(suggestion, run))
                    index += run.count
                    continue
                }
            }
            segments.append(.row(rows[index]))
            index += 1
        }
        return segments
    }

    @ViewBuilder
    private func view(of segment: Segment) -> some View {
        switch segment {
        case .row(.member(let member)):
            Toggle(isOn: choosing(member.id)) { Text(member.title) }
        case .row(.fixed(_, let title)):
            Text("↳ \(title)").foregroundStyle(.secondary)
        case .row(.group(let group)):
            Bracketed(ids: group.members.map(\.id)) {
                ForEach(group.members) { member in
                    HStack(spacing: 4) {
                        Button {
                            remove(member.id, group.id)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove from Group")
                        // Taken with the group: only to be taken out of it.
                        Toggle(isOn: .constant(true)) { Text(member.title) }.disabled(true)
                    }
                    .bracketRow(member.id)
                }
            } label: {
                HStack {
                    Toggle(isOn: groupTick(group)) {
                        Text("\(group.kind): \(group.title)").bold()
                    }
                    Button("Ungroup") { ungroup(group.id) }.buttonStyle(.borderless).font(.caption)
                }
            }
        case .suggested(let suggestion, let run):
            Bracketed(ids: run.map(\.id)) {
                ForEach(run) { member in
                    Toggle(isOn: choosing(member.id)) { Text(member.title) }.bracketRow(member.id)
                }
            } label: {
                HStack {
                    Text("group as \(suggestion.title)").foregroundStyle(.tint)
                    Menu("Group") {
                        ForEach(kinds, id: \.self) { kind in
                            Button("As a \(kind.title)") { Task { await group(suggestion, as: kind) } }
                        }
                    }
                    .menuStyle(.borderlessButton).font(.caption).fixedSize()
                }
            }
        }
    }

    private func choosing(_ member: String) -> Binding<Bool> {
        Binding(
            get: { chosen.contains(member) },
            set: { on in
                if on { chosen.insert(member) } else { chosen.remove(member) }
            }
        )
    }
}

/// Rows bracketed on the right of their widest: a line from the middle of the first to the middle of
/// the last, a stub from each row's middle to it, and the label beside the line's middle.
private struct Bracketed<Rows: View, Label: View>: View {
    let ids: [String]
    @ViewBuilder let rows: Rows
    @ViewBuilder let label: Label
    @State private var middles: [String: CGFloat] = [:]

    private var placed: [CGFloat] { ids.compactMap { middles[$0] } }
    private var middle: CGFloat { ((placed.first ?? 0) + (placed.last ?? 0)) / 2 }

    var body: some View {
        let middle = middle
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 4) { rows }
                .coordinateSpace(.named(BracketRow.space))
                .onPreferenceChange(BracketRow.self) { middles = $0 }
            BracketLine(middles: placed)
                .stroke(.tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .frame(width: 16, height: (placed.last ?? 0) + 1)
            label.alignmentGuide(.top) { $0[VerticalAlignment.center] - middle }
        }
    }
}

/// The middle of each bracketed row, in the bracket's rows' space.
private struct BracketRow: PreferenceKey {
    static let space = "bracketed"
    static let defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Says where a bracketed row's middle is, for the bracket to reach.
    fileprivate func bracketRow(_ id: String) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: BracketRow.self,
                    value: [id: proxy.frame(in: .named(BracketRow.space)).midY]
                )
            }
        )
    }
}

/// A stub left from the line at each row's middle, the line from the first to the last, and a stub
/// right at its middle, toward the label.
private struct BracketLine: Shape {
    let middles: [CGFloat]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = middles.first, let last = middles.last else { return path }
        let line = rect.maxX - 5
        for middle in middles {
            path.move(to: CGPoint(x: rect.minX, y: middle))
            path.addLine(to: CGPoint(x: line, y: middle))
        }
        path.move(to: CGPoint(x: line, y: first))
        path.addLine(to: CGPoint(x: line, y: last))
        path.move(to: CGPoint(x: line, y: (first + last) / 2))
        path.addLine(to: CGPoint(x: rect.maxX, y: (first + last) / 2))
        return path
    }
}

// MARK: - A draft's entries

/// A draft container's entries, grouped into containers beneath it: each group is a container of the
/// draft, made with it.
struct EntryGrouping: View {
    let tree: TMDbTree
    let parent: String
    /// Changes the draft, as the sheet the grouping is in keeps it.
    let update: ((inout TMDbTree) -> Void) -> Void
    let provisionalID: () async -> ContainerID?
    @State private var selected: Set<String> = []

    private var container: Container? { tree.container(parent) }

    var body: some View {
        if let container {
            GroupBox {
                GroupingList(
                    rows: container.sequences.flatMap(\.items).compactMap(row),
                    suggestions: tree.suggestedGroups(in: parent).map {
                        GroupingSuggestion(title: $0.title, members: $0.items.map(\.value))
                    },
                    defaultKind: Self.kind(of: tree.groups(in: parent)),
                    chosenWord: "selected",
                    chosen: $selected,
                    groupTick: { group in
                        Binding(
                            get: { group.key.map(selected.contains) ?? false },
                            set: { on in
                                guard let key = group.key else { return }
                                if on { selected.insert(key) } else { selected.remove(key) }
                            }
                        )
                    },
                    form: formGroup,
                    add: { members, group in
                        let leaves = Set(
                            tree.container(parent)?.sequences.flatMap(\.items).filter { $0.childContainer == nil }
                                .compactMap(\.id?.value) ?? []
                        )
                        change { $0.add(members.filter(leaves.contains).compactMap(ItemID.init), to: group) }
                    },
                    remove: { member, group in
                        guard let item = ItemID(member) else { return }
                        change { $0.remove(item, from: group) }
                    },
                    ungroup: { group in change { $0.ungroup(group) } }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Text(selected.isEmpty ? "Its entries" : "Its entries, \(selected.count) selected")
            }
        }
    }

    private func row(_ entry: Entry) -> GroupingRow? {
        guard let item = entry.id else { return nil }
        guard let child = entry.childContainer else {
            return .member(GroupingMember(id: item.value, title: title(of: entry)))
        }
        guard let group = tree.container(child.value), tree.documents[child.value] != nil else {
            return .fixed(id: item.value, tree.container(child.value)?.displayTitle ?? child.value)
        }
        return .group(
            GroupingGroup(
                id: child.value,
                key: item.value,
                title: group.displayTitle,
                kind: group.typeLabel ?? group.type.title,
                members: group.sequences.flatMap(\.items).compactMap { member in
                    member.id.map { GroupingMember(id: $0.value, title: title(of: member)) }
                }
            )
        )
    }

    /// The kind most of a container's groups are, when it has any.
    static func kind(of groups: [Container]) -> ContainerType? {
        let counts = Dictionary(groups.map { ($0.type, 1) }, uniquingKeysWith: +)
        return counts.max { $0.value < $1.value }?.key
    }

    private func title(of entry: Entry) -> String {
        if let child = entry.childContainer { return tree.container(child.value)?.displayTitle ?? child.value }
        let tmdb = entry.externalRefs.first { $0.provider == .tmdb }
        return tmdb.flatMap { tree.episodeTitles[$0.value] } ?? entry.title ?? entry.id?.value ?? "a reference"
    }

    private func change(_ body: @escaping (inout TMDbTree) -> Void) {
        update(body)
        selected = []
    }

    private func formGroup(_ members: [String], _ title: Title, _ type: ContainerType, _ label: String?) async {
        guard let id = await provisionalID() else { return }
        let order = (container?.sequences.flatMap(\.items) ?? []).compactMap(\.id).filter { members.contains($0.value) }
        let parent = parent
        var made: String?
        update { tree in
            tree.regroup(order, in: parent, into: id, type: type, typeLabel: label, title: title)
            made = tree.container(parent)?.sequences.flatMap(\.items).first { $0.childContainer == id }?.id?.value
        }
        // The group made is selected in its members' place, as a group made at a held stop is ticked.
        selected.subtract(members)
        if let made { selected.insert(made) }
    }
}
#endif
