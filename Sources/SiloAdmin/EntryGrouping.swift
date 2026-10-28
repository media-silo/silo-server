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
    /// The key it is moved by, when that is not the one it is selected by.
    var key: String?

    var moveKey: String { key ?? id }
}

/// A group made in a grouping list: the container its entries are to be in.
struct GroupingGroup: Identifiable {
    let id: String
    /// The entry naming it in the container, in a draft; nil when it has none yet.
    var entry: String?
    let title: String
    let kind: String
    let members: [GroupingMember]
    /// Held already, beneath a held container: entries may be added to it and taken out again, and it is
    /// neither ticked nor ungrouped.
    var held = false
    /// Whether entries may be put into it here; one shaped at a stop of its own takes none.
    var accepts = true
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
    /// The part number TMDb gives each member, in their order.
    let parts: [Int]

    /// The parts a renaming titles, by their numbers, as `Part 1 to 6`.
    func renamed(as word: String) -> String {
        "\(word) \(parts.first ?? 1) to \(parts.last ?? members.count)"
    }
}

/// Entries grouped into containers by the operator. A tick only says whether an entry is taken, or
/// made: grouping works on the entries selected, clicked, shift-clicked to a range or command-clicked
/// one at a time, then, from the pinned menu or a right-click on the selection, made a new group of the kind chosen or put into a group made already, after which
/// nothing is selected. A group is never selected, so groups are made of entries alone and a deeper
/// shape is made a level at a time. A group is ticked whole, and its entries are shown in it, each only
/// to be taken out of it. A container held beneath already is shown in its place, and entries may be put
/// into it as into a group, each only to be taken out of it again. A group, and each run TMDb titles as one story's parts, is bracketed on the
/// right of its entries' titles, its title or the suggestion beside the bracket's middle. No kind is
/// assumed: the kind the container's own groups are is offered first, and the operator chooses. The
/// heading and the actions are the header of a section, pinned while the list scrolls beneath them in a
/// lazy stack that pins its sections' headers.
struct GroupingList<Heading: View>: View {
    let rows: [GroupingRow]
    let suggestions: [GroupingSuggestion]
    let defaultKind: ContainerType?
    /// The entries grouped in none that are ticked.
    @Binding var chosen: Set<String>
    let groupTick: (GroupingGroup) -> Binding<Bool>
    let form: (_ members: [String], _ title: Title, _ type: ContainerType, _ label: String?) async -> Void
    let add: (_ members: [String], _ group: String) -> Void
    let remove: (_ member: String, _ group: String) -> Void
    let ungroup: (_ group: String) -> Void
    /// The run of the container's own story's parts, already grouped, to be titled by its part numbers
    /// rather than grouped again.
    var renaming: GroupingSuggestion?
    var rename: (_ word: String) -> Void = { _ in }
    /// Moves a child, by the key its row goes by, before another's, or last with none; nil when the
    /// children keep the order they are in.
    var move: ((_ child: String, _ before: String?) -> Void)?
    @ViewBuilder let heading: Heading
    /// The entries selected to be grouped.
    @State private var selected: Set<String> = []
    /// Where a shift-click's range runs from.
    @State private var anchor: String?
    /// The kind of the new group being titled, while it is.
    @State private var forming: ContainerType?
    @State private var groupTitle = ""
    @State private var groupLabel = ""
    @FocusState private var titling: Bool
    /// The child a dragged one is over, to go before it, or the end of the list.
    @State private var dropping: String?
    /// The child whose grab handle the pointer is on.
    @State private var grabbing: String?

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(segments, id: \.id) { segment in view(of: segment) }
                end
            }
            .padding(.leading, 4)
            .padding(.bottom, 8)
        } header: {
            VStack(alignment: .leading, spacing: 6) {
                heading.font(.headline)
                actions
                Divider()
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background)
        }
    }

    // MARK: Actions

    private var members: [GroupingMember] {
        rows.compactMap { if case .member(let member) = $0 { member } else { nil } }
    }

    private var groups: [GroupingGroup] {
        rows.compactMap { if case .group(let group) = $0 { group } else { nil } }
    }

    /// The entries selected, in the list's order; only entries grouped in none are ever selected.
    private var selectedMembers: [String] { members.map(\.id).filter(selected.contains) }

    /// Every kind a group may be, the one the container's own groups are first.
    private var kinds: [ContainerType] {
        (defaultKind.map { [$0] } ?? []) + ContainerType.allCases.filter { $0 != defaultKind }
    }

    /// One menu, so the row holds at any width: the entries selected made a new group of a kind, or put
    /// into a group made already. Every suggestion grouped at once is a menu on a row of its own, there
    /// only while there are suggestions.
    @ViewBuilder
    private var actions: some View {
        HStack {
            Menu("Group Selected") { grouping(selectedMembers) }
                .fixedSize()
                .disabled(selectedMembers.isEmpty)
            if selectedMembers.isEmpty {
                Text(
                    "Click entries to select them, ⇧-click for a range or ⌘-click for one more, then right-click to group."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        // The suggestions on a row of their own, so accepting them is not hidden among the selection's.
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
                    .focused($titling)
                    .onSubmit { Task { await formGroup(as: forming) } }
                TextField("Label", text: $groupLabel).frame(maxWidth: 100)
                Button("Group") { Task { await formGroup(as: forming) } }.disabled(Title(groupTitle) == nil)
                Button("Cancel") { self.forming = nil }
            }
            // Ready to type the title once the kind is chosen.
            .task(id: forming) { titling = true }
        }
    }

    /// What may be done with the entries given: made a new group of a kind, titled in the header, or put
    /// into a group made already. The pinned menu offers it for the selection, and a right-click for the
    /// entry clicked, with the selection when the entry is part of it.
    @ViewBuilder
    private func grouping(_ entries: [String]) -> some View {
        Section("\(entries.count) selected") {
            Menu("New Group") {
                ForEach(kinds, id: \.self) { kind in
                    Button(kind.title) {
                        selected = Set(entries)
                        forming = kind
                    }
                }
            }
            ForEach(groups.filter(\.accepts)) { group in
                Button("Into \(group.title)") {
                    add(entries, group.id)
                    selected = []
                }
            }
        }
    }

    private func formGroup(as kind: ContainerType) async {
        guard let title = Title(groupTitle) else { return }
        let label = groupLabel.trimmingCharacters(in: .whitespaces)
        let members = selectedMembers
        // Nothing selected once a group is made, for the next to be selected.
        selected = []
        forming = nil
        groupTitle = ""
        groupLabel = ""
        await form(members, title, kind, label.isEmpty ? nil : label)
    }

    private func group(_ suggestion: GroupingSuggestion, as kind: ContainerType) async {
        guard let title = Title(suggestion.title) else { return }
        selected.subtract(suggestion.members)
        await form(suggestion.members, title, kind, nil)
    }

    // MARK: Rows

    private enum Segment {
        case row(GroupingRow)
        case suggested(GroupingSuggestion, [GroupingMember], renaming: Bool)

        var id: String {
            switch self {
            case .row(let row): row.id
            case .suggested(let suggestion, _, _): "suggested:\(suggestion.members.first ?? suggestion.title)"
            }
        }
    }

    /// The rows, each run suggested as a group gathered to be bracketed together.
    private var segments: [Segment] {
        var segments: [Segment] = []
        var index = rows.startIndex
        while index < rows.endIndex {
            if case .member(let member) = rows[index],
                let suggestion = (suggestions + (renaming.map { [$0] } ?? [])).first(where: {
                    $0.members.first == member.id
                })
            {
                let run = rows[index...].prefix(suggestion.members.count).compactMap { row -> GroupingMember? in
                    if case .member(let member) = row, suggestion.members.contains(member.id) { member } else { nil }
                }
                if run.count == suggestion.members.count {
                    segments.append(.suggested(suggestion, run, renaming: suggestion == renaming))
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
            entry(member)
        case .row(.fixed(let id, let title)):
            // Held already, it is part of the walk whatever is ticked.
            movable(Toggle(isOn: .constant(true)) { Text(title) }.disabled(true), id, titled: title)
                .contextMenu { moving(id) }
        case .row(.group(let group)) where group.held && group.members.isEmpty:
            // Held already, it is part of the walk whatever is ticked, and entries may be put into it.
            movable(
                Toggle(isOn: .constant(true)) { Text("\(group.kind): \(group.title), held here").bold() }
                    .disabled(true),
                group.entry,
                titled: group.title
            )
            .contextMenu { group.entry.map(moving) }
        case .row(.group(let group)) where group.members.isEmpty:
            // Added holding nothing yet: entries are put into it as into any group.
            movable(
                HStack {
                    Toggle(isOn: groupTick(group)) { Text("\(group.kind): \(group.title)").bold() }
                    Text(group.accepts ? "holds nothing yet" : "new, shaped at its own stop")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Remove") { ungroup(group.id) }.buttonStyle(.borderless).font(.caption)
                },
                group.entry,
                titled: group.title
            )
            .contextMenu { group.entry.map(moving) }
        case .row(.group(let group)):
            movable(bracketed(group), group.entry, titled: group.title, group: true)
                .contextMenu { group.entry.map(moving) }
        case .suggested(let suggestion, let run, renaming: true):
            Bracketed {
                ForEach(run) { member in entry(member).bracketRow() }
            } label: {
                HStack {
                    Text("Rename?").foregroundStyle(.tint)
                    Menu("As") {
                        Button(suggestion.renamed(as: "Episode")) { rename("Episode") }
                        Button(suggestion.renamed(as: "Part")) { rename("Part") }
                    }
                    .menuStyle(.borderlessButton).font(.caption).fixedSize()
                }
            }
        case .suggested(let suggestion, let run, renaming: false):
            Bracketed {
                ForEach(run) { member in entry(member).bracketRow() }
            } label: {
                HStack {
                    Text("\(suggestion.title)?").foregroundStyle(.tint)
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

    /// A group, its entries bracketed, each only to be taken out of it, and its title beside them.
    private func bracketed(_ group: GroupingGroup) -> some View {
        Bracketed {
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
                .bracketRow()
            }
        } label: {
            if group.held {
                Toggle(isOn: .constant(true)) { Text("\(group.kind): \(group.title), held here").bold() }
                    .disabled(true)
            } else {
                HStack {
                    Toggle(isOn: groupTick(group)) {
                        Text("\(group.kind): \(group.title)").bold()
                    }
                    Button("Ungroup") { ungroup(group.id) }.buttonStyle(.borderless).font(.caption)
                }
            }
        }
    }

    /// An entry grouped in none: its tick, and its title, clicked to select it, dragged to move it.
    private func entry(_ member: GroupingMember) -> some View {
        movable(selectable(member), member.moveKey, titled: member.title)
    }

    private func selectable(_ member: GroupingMember) -> some View {
        HStack(spacing: 6) {
            Toggle("Ticked", isOn: ticking(member.id)).labelsHidden()
            Text(member.title)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    selected.contains(member.id) ? Color.accentColor.opacity(0.25) : .clear,
                    in: RoundedRectangle(cornerRadius: 4)
                )
                .contentShape(Rectangle())
                .onTapGesture { select(member.id) }
        }
        .contextMenu {
            // A right-click groups the selection when the entry is part of it, and the entry alone when not.
            grouping(selected.contains(member.id) ? selectedMembers : [member.id])
            moving(member.moveKey)
        }
    }

    // MARK: Moving

    /// The keys the children are moved by, in their order: an entry's, the entry naming a group, and a
    /// held container's.
    private var order: [String] {
        rows.compactMap { row in
            switch row {
            case .member(let member): member.moveKey
            case .group(let group): group.entry
            case .fixed(let id, _): id
            }
        }
    }

    private var mover: ChildMoving? {
        move.map { ChildMoving(order: order, move: $0, dropping: $dropping, grabbing: $grabbing) }
    }

    private func movable(_ row: some View, _ key: String?, titled title: String, group: Bool = false) -> some View {
        row.movable(key, titled: title, by: mover, group: group)
    }

    @ViewBuilder
    private var end: some View {
        if let mover { ChildEnd(mover: mover) }
    }

    @ViewBuilder
    private func moving(_ key: String) -> some View {
        if let mover { mover.menu(key) }
    }

    /// A click selects the entry alone, a command-click adds or takes it out, and a shift-click selects
    /// the range from the last one clicked.
    private func select(_ member: String) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.shift), let anchor, let from = members.firstIndex(where: { $0.id == anchor }),
            let to = members.firstIndex(where: { $0.id == member })
        {
            selected.formUnion(members[min(from, to)...max(from, to)].map(\.id))
            return
        }
        if flags.contains(.command) {
            if selected.remove(member) == nil { selected.insert(member) }
        } else {
            selected = selected == [member] ? [] : [member]
        }
        anchor = member
    }

    private func ticking(_ member: String) -> Binding<Bool> {
        Binding(
            get: { chosen.contains(member) },
            set: { on in
                if on { chosen.insert(member) } else { chosen.remove(member) }
            }
        )
    }
}

/// Rows bracketed on the right of their widest: a line from the middle of the first to the middle of
/// the last, a stub from each row's middle to it, and the label beside the line's middle. The rows and
/// the label are placed by one layout, and the bracket is drawn from the rows' frames as laid out, so it
/// reaches every row however the titles wrap.
struct Bracketed<Rows: View, Label: View>: View {
    @ViewBuilder let rows: Rows
    @ViewBuilder let label: Label

    var body: some View {
        BracketLayout {
            rows
            label
        }
        .backgroundPreferenceValue(BracketRow.self) { anchors in
            GeometryReader { proxy in
                BracketLine(frames: anchors.map { proxy[$0] })
                    .stroke(.tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

/// The rows one under another, each given what width the label leaves, and the label, the last
/// subview, past the bracket's room and centred on the middle between the first row's middle and the
/// last's.
private struct BracketLayout: Layout {
    /// The room the bracket takes between the widest row and the label.
    static let bracket: CGFloat = 24
    let spacing: CGFloat = 4

    private struct Placed {
        var rows: [CGRect]
        var label: CGRect
        var size: CGSize
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        placed(proposal, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // Laid out as it was sized, from what was proposed: the bounds are the narrower size it gave,
        // and the label laid out in them wraps taller than it was sized, over what is beneath.
        let placed = placed(proposal, subviews)
        for (subview, frame) in zip(subviews.dropLast(), placed.rows) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
        subviews.last?.place(
            at: CGPoint(x: bounds.minX + placed.label.minX, y: bounds.minY + placed.label.minY),
            proposal: ProposedViewSize(placed.label.size)
        )
    }

    private func placed(_ proposal: ProposedViewSize, _ subviews: Subviews) -> Placed {
        guard let label = subviews.last else { return Placed(rows: [], label: .zero, size: .zero) }
        let rows = subviews.dropLast()
        let width = proposal.width ?? .infinity
        let ideal = label.sizeThatFits(.unspecified)
        // The label takes what it would, up to half of what the rows and it share.
        let labelWidth = min(ideal.width, max(0, (width - Self.bracket) / 2))
        let labelSize = label.sizeThatFits(ProposedViewSize(width: labelWidth, height: nil))
        let rowsWidth = width.isFinite ? max(0, width - Self.bracket - labelSize.width) : nil
        var frames: [CGRect] = []
        var top: CGFloat = 0
        for row in rows {
            let size = row.sizeThatFits(ProposedViewSize(width: rowsWidth, height: nil))
            frames.append(CGRect(origin: CGPoint(x: 0, y: top), size: size))
            top += size.height + spacing
        }
        let middle = ((frames.first?.midY ?? 0) + (frames.last?.midY ?? 0)) / 2
        // A label taller than the rows above its middle pushes the rows down, never off the top.
        let inset = max(0, labelSize.height / 2 - middle)
        frames = frames.map { $0.offsetBy(dx: 0, dy: inset) }
        let widest = frames.map(\.maxX).max() ?? 0
        let labelFrame = CGRect(
            origin: CGPoint(x: widest + Self.bracket, y: inset + middle - labelSize.height / 2),
            size: labelSize
        )
        let height = max((frames.last?.maxY ?? 0), labelFrame.maxY)
        return Placed(rows: frames, label: labelFrame, size: CGSize(width: labelFrame.maxX, height: height))
    }
}

/// Each bracketed row's bounds, in the order the rows are.
private struct BracketRow: PreferenceKey {
    static let defaultValue: [Anchor<CGRect>] = []

    static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    /// Says where a bracketed row is, for the bracket to reach.
    fileprivate func bracketRow() -> some View {
        anchorPreference(key: BracketRow.self, value: .bounds) { [$0] }
    }
}

/// A stub from the right of the widest row at each row's middle to the line, the line from the first
/// row's middle to the last's, and a stub at its middle toward the label.
private struct BracketLine: Shape {
    let frames: [CGRect]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = frames.first, let last = frames.last, let widest = frames.map(\.maxX).max() else {
            return path
        }
        let (start, line, end) = (widest + 4, widest + 14, widest + BracketLayout.bracket - 4)
        for frame in frames {
            path.move(to: CGPoint(x: start, y: frame.midY))
            path.addLine(to: CGPoint(x: line, y: frame.midY))
        }
        path.move(to: CGPoint(x: line, y: first.midY))
        path.addLine(to: CGPoint(x: line, y: last.midY))
        let middle = (first.midY + last.midY) / 2
        path.move(to: CGPoint(x: line, y: middle))
        path.addLine(to: CGPoint(x: end, y: middle))
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
    /// Clones the container's primary sequence into a new alternative of the title given.
    let clone: (String) -> Void
    /// Renames the container's primary sequence, and with true each container's beneath it.
    let rename: (String, Bool) -> Void
    /// Moves one of the container's entries before another, or last with none.
    let move: (_ item: ItemID, _ before: ItemID?) -> Void

    private var container: Container? { tree.container(parent) }
    private var rows: [GroupingRow] { (container?.sequences.flatMap(\.items) ?? []).compactMap(row) }

    var body: some View {
        if container != nil {
            GroupingList(
                rows: rows,
                suggestions: tree.suggestedGroups(in: parent).map {
                    GroupingSuggestion(title: $0.title, members: $0.items.map(\.value), parts: $0.parts)
                },
                defaultKind: Self.kind(of: tree.groups(in: parent)),
                chosen: ticked,
                groupTick: { group in group.entry.map(including) ?? .constant(true) },
                form: formGroup,
                add: { members, group in
                    update { $0.add(members.compactMap(ItemID.init), to: group) }
                },
                remove: { member, group in
                    guard let item = ItemID(member) else { return }
                    update { $0.remove(item, from: group) }
                },
                ungroup: { group in update { $0.ungroup(group) } },
                renaming: tree.suggestedRenaming(in: parent).map {
                    GroupingSuggestion(title: $0.title, members: $0.items.map(\.value), parts: $0.parts)
                },
                rename: { word in
                    let parent = parent
                    guard let items = tree.suggestedRenaming(in: parent)?.items else { return }
                    update { $0.title(items, in: parent, as: word) }
                },
                move: { child, before in
                    guard let item = ItemID(child) else { return }
                    move(item, before.flatMap(ItemID.init))
                }
            ) {
                // Ticks every child that may be ticked or none, a group as one, and shows as mixed while
                // some are ticked.
                let tickable = rows.compactMap { row -> String? in
                    switch row {
                    case .member(let member): member.id
                    case .group(let group): group.entry
                    case .fixed: nil
                    }
                }
                let count = tickable.filter { !isLeftOut($0) }.count
                VStack(alignment: .leading, spacing: 4) {
                    if tickable.isEmpty {
                        Text("Children, each held already")
                    } else {
                        Toggle(sources: tickable.map(including), isOn: \.self) {
                            Text("Children, \(count) of \(tickable.count) ticked")
                        }
                    }
                    if let container, !container.sequences.isEmpty {
                        PrimarySequence(
                            name: container.sequences[0].id,
                            clone: clone,
                            rename: rename,
                            add: addContainer
                        )
                    }
                }
            }
        }
    }

    private func isLeftOut(_ item: String) -> Bool {
        ItemID(item).map { tree.isLeftOut($0, in: parent) } ?? false
    }

    /// An entry ticked to be made with the container, or unticked to be left out.
    private func including(_ item: String) -> Binding<Bool> {
        let parent = parent
        return Binding(
            get: { !isLeftOut(item) },
            set: { on in
                guard let id = ItemID(item) else { return }
                update { $0.include(id, in: parent, on) }
            }
        )
    }

    /// The entries grouped in none that are ticked.
    private var ticked: Binding<Set<String>> {
        let members = rows.compactMap { if case .member(let member) = $0 { member.id } else { nil } }
        return Binding(
            get: { Set(members.filter { !isLeftOut($0) }) },
            set: { on in
                for member in members where on.contains(member) == isLeftOut(member) {
                    including(member).wrappedValue = on.contains(member)
                }
            }
        )
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
                entry: item.value,
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
        // The operator's own title, as a part renamed has, before TMDb's.
        if let title = entry.title { return title }
        let tmdb = entry.externalRefs.first { $0.provider == .tmdb }
        return tmdb.flatMap { tree.episodeTitles[$0.value] } ?? entry.id?.value ?? "a reference"
    }

    /// A new container, holding nothing yet, last among the children.
    private func addContainer(_ type: ContainerType, _ title: Title) async {
        guard let id = await provisionalID() else { return }
        let parent = parent
        update { $0.addContainer(id, type: type, title: title, beneath: parent) }
    }

    private func formGroup(_ members: [String], _ title: Title, _ type: ContainerType, _ label: String?) async {
        guard let id = await provisionalID() else { return }
        let order = (container?.sequences.flatMap(\.items) ?? []).compactMap(\.id).filter { members.contains($0.value) }
        let parent = parent
        // Made in their place, and ticked.
        update { $0.regroup(order, in: parent, into: id, type: type, typeLabel: label, title: title) }
    }
}
#endif
