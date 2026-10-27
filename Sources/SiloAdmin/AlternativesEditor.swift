// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

#if canImport(SwiftUI)
import SiloAdminKit
import SmdKit
import SwiftUI

/// What is dragged between the specials and a container's alternatives and extras, as text: a special,
/// by its TMDb id, or one of a drafted alternative's entries, by the draft and its position.
enum AlternativeDrag: Equatable {
    case special(Int)
    case entry(draft: String, position: Int)

    var payload: String {
        switch self {
        case .special(let id): "silo-special:\(id)"
        case .entry(let draft, let index): "silo-entry:\(index):\(draft)"
        }
    }

    init?(_ payload: String) {
        let parts = payload.split(separator: ":", maxSplits: 2).map(String.init)
        switch parts.first {
        case "silo-special" where parts.count == 2:
            guard let id = Int(parts[1]) else { return nil }
            self = .special(id)
        case "silo-entry" where parts.count == 3:
            guard let index = Int(parts[1]) else { return nil }
            self = .entry(draft: parts[2], position: index)
        default:
            return nil
        }
    }
}

extension View {
    /// Dragged as a special, onto a container's alternatives or extras.
    func draggable(special: Int, title: String) -> some View {
        draggable(AlternativeDrag.special(special).payload) {
            Label(title, systemImage: "film").padding(6).background(.regularMaterial, in: .rect(cornerRadius: 6))
        }
    }
}

/// A container's alternatives, edited by dragging specials onto them: each sequence it has, cloned into a
/// new alternative; each alternative drafted for it, a special dropped on an entry in its place, between
/// two entries to add it, and its entries dragged to reorder them; and a special dropped on the heading
/// drafted into an alternative of its own. A walk's stop and a draft's container are edited alike.
struct AlternativesEditor<Drafting: AlternativeDrafting>: View {
    let drafting: Drafting
    let container: Container
    let change: ((inout Drafting) -> Void) -> Void
    /// A new container's id, from smddb's client.
    let provisionalID: () async -> ContainerID?
    @State private var naming: AlternativeNaming?
    /// The drop target being dragged over, to mark it.
    @State private var targeted: String?

    private var id: String { container.id.value }
    private var drafts: [DraftAlternative] { drafting.alternatives(draftedAt: id) }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                newAlternativeTarget
                // The first is the container's children, cloned from their heading.
                ForEach(container.sequences.indices.dropFirst(), id: \.self) { index in sequence(index) }
                ForEach(drafts) { draft in drafted(draft) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Alternatives")
        }
        .sheet(item: $naming) { naming in
            TitlePrompt(question: naming.question, initial: naming.initial, action: naming.action) { title, _ in
                name(naming, title.rawValue)
            }
        }
    }

    private func name(_ naming: AlternativeNaming, _ title: String) {
        switch naming {
        case .playing(let special, _):
            change { $0.draftAlternative(at: id, titled: title, playing: special) }
        case .cloning(let index, _):
            change { $0.cloneSequence(index, of: id, titled: title) }
        case .cloningDraft(let draft, _):
            change { $0.cloneDraft(draft, of: id, titled: title) }
        case .retitling(let draft, _):
            change { $0.retitle(draft, to: title, of: id) }
        case .containing(let draft, let type, _):
            guard let title = Title(title) else { return }
            Task {
                guard let new = await provisionalID() else { return }
                change { $0.addContainer(new, type: type, title: title, toAlternative: draft, of: id) }
            }
        }
    }

    // MARK: A new alternative

    private var newAlternativeTarget: some View {
        Text("Drop a special here for a new alternative playing it, or clone the children from their heading")
            .font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 28)
            .background(marked("new"), in: .rect(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary, style: StrokeStyle(dash: [4])))
            .dropDestination(for: String.self) { payloads, _ in
                guard case .special(let special)? = payloads.first.flatMap(AlternativeDrag.init) else { return false }
                naming = .playing(special, drafting.title(of: .special(special), at: id))
                return true
            } isTargeted: {
                target("new", $0)
            }
    }

    // MARK: The container's sequences

    @ViewBuilder
    private func sequence(_ index: Int) -> some View {
        let sequence = container.sequences[index]
        let title = sequenceTitle(sequence)
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(sequence.items.indices, id: \.self) { position in
                    Text(entryTitle(sequence.items[position])).font(.caption)
                }
            }
            .padding(.leading, 8)
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Text("\(sequence.items.count) items").font(.caption).foregroundStyle(.secondary)
                Spacer()
                ActionsMenu {
                    Button("Clone…") { naming = .cloning(index, title) }
                        .help("A new alternative playing what this sequence plays, to edit before it is stored.")
                }
            }
        }
    }

    private func sequenceTitle(_ sequence: SmdKit.Sequence) -> String {
        if let alternative = container.alternatives.first(where: { $0.sequence == sequence.id }) {
            return alternative.title ?? alternative.id
        }
        return sequence.id.map { "The \($0) sequence" } ?? "The sequence"
    }

    private func entryTitle(_ entry: Entry) -> String {
        if let item = entry.id { return drafting.title(ofItem: item.value, at: id) }
        if let ref = entry.reference, ref.container == nil || ref.container == container.id {
            return drafting.title(ofItem: ref.item.value, at: id)
        }
        return entry.reference.map { "\($0.container?.value ?? "")#\($0.item)" } ?? "an item"
    }

    // MARK: A drafted alternative

    @ViewBuilder
    private func drafted(_ draft: DraftAlternative) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(draft.title).bold()
                Text("new, made when stored").font(.caption).foregroundStyle(.green)
                Spacer()
                ActionsMenu {
                    Button("Clone…") { naming = .cloningDraft(draft.id, draft.title) }
                    Button("Rename…") { naming = .retitling(draft.id, draft.title) }
                    Menu("New Container") {
                        ForEach(ContainerType.allCases, id: \.self) { type in
                            Button("\(type.title)…") { naming = .containing(draft.id, type, draft.title) }
                        }
                    }
                    .help("A new container of the kind chosen, holding nothing yet, played in this alternative alone.")
                    Divider()
                    Button("Discard", role: .destructive) { change { $0.discard(draft.id, of: id) } }
                        .help("Its specials go back among the unassigned, but for those a clone of it plays.")
                }
            }
            .padding(.bottom, 4)
            gap(0, in: draft)
            ForEach(draft.entries.indices, id: \.self) { position in
                entry(position, in: draft)
                gap(position + 1, in: draft)
            }
            if draft.entries.isEmpty {
                Text("Plays nothing yet: drop specials here").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 6))
    }

    private func entry(_ position: Int, in draft: DraftAlternative) -> some View {
        let entry = draft.entries[position]
        let key = "\(draft.id):\(position)"
        return HStack {
            Image(systemName: entry.symbol).foregroundStyle(.secondary)
            Text(drafting.title(of: entry, at: id))
            Spacer()
            Button {
                change { $0.removeEntry(position, from: draft.id, of: id) }
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help(entry.removal)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(marked(key), in: .rect(cornerRadius: 4))
        .contentShape(.rect)
        .draggable(AlternativeDrag.entry(draft: draft.id, position: position).payload) {
            Text(drafting.title(of: entry, at: id)).padding(6).background(.regularMaterial, in: .rect(cornerRadius: 6))
        }
        .dropDestination(for: String.self) { payloads, _ in
            // A special dropped on an entry plays in its place.
            guard case .special(let special)? = payloads.first.flatMap(AlternativeDrag.init) else { return false }
            change { $0.replace(position, in: draft.id, with: special, of: id) }
            return true
        } isTargeted: {
            target(key, $0)
        }
    }

    /// Between two of a draft's entries: a special dropped here is added, an entry dragged here moved.
    private func gap(_ position: Int, in draft: DraftAlternative) -> some View {
        let key = "\(draft.id):gap:\(position)"
        return Rectangle()
            .fill(targeted == key ? Color.accentColor : .clear)
            .frame(height: targeted == key ? 4 : 6)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
            .dropDestination(for: String.self) { payloads, _ in
                switch payloads.first.flatMap(AlternativeDrag.init) {
                case .special(let special)?:
                    change { $0.insert(special, into: draft.id, at: position, of: id) }
                case .entry(let from, let index)? where from == draft.id:
                    change { $0.moveEntries([index], to: position, in: draft.id, of: id) }
                case .entry(let from, let index)?:
                    // A special from another draft moves into this one; an item stays where it was.
                    guard case .special(let special)? = drafts.first(where: { $0.id == from })?.entries[safe: index]
                    else { return false }
                    change { $0.insert(special, into: draft.id, at: position, of: id) }
                default:
                    return false
                }
                return true
            } isTargeted: {
                target(key, $0)
            }
    }

    private func marked(_ key: String) -> some ShapeStyle {
        targeted == key ? AnyShapeStyle(Color.accentColor.opacity(0.25)) : AnyShapeStyle(Color.clear)
    }

    private func target(_ key: String, _ isTargeted: Bool) {
        if isTargeted {
            targeted = key
        } else if targeted == key {
            targeted = nil
        }
    }
}

/// What an alternative being drafted is asked to be called.
private enum AlternativeNaming: Identifiable {
    /// A new alternative playing a special alone, titled from the special's own to begin with.
    case playing(Int, String)
    /// A new alternative cloned from one of the container's sequences.
    case cloning(Int, String)
    /// A new alternative cloned from one drafted already, its specials included.
    case cloningDraft(String, String)
    /// A drafted alternative titled again.
    case retitling(String, String)
    /// A new container of a kind, played in a drafted alternative alone.
    case containing(String, ContainerType, String)

    var id: String {
        switch self {
        case .playing(let special, _): "playing:\(special)"
        case .cloning(let index, _): "cloning:\(index)"
        case .cloningDraft(let draft, _): "cloning-draft:\(draft)"
        case .retitling(let draft, _): "retitling:\(draft)"
        case .containing(let draft, let type, _): "containing:\(type.rawValue):\(draft)"
        }
    }

    var question: String {
        switch self {
        case .playing(_, let title): "A new alternative playing \(title): what is it called?"
        case .cloning(_, let title), .cloningDraft(_, let title):
            "A new alternative playing what \(title) does: what is it called?"
        case .retitling(_, let title): "What is \(title) called?"
        case .containing(_, let type, let title):
            "A new \(type.title.lowercased()) played in \(title): what is it called?"
        }
    }

    var initial: String {
        switch self {
        case .playing(_, let title), .retitling(_, let title): title
        case .cloning, .cloningDraft, .containing: ""
        }
    }

    var action: String {
        switch self {
        case .playing: "Place"
        case .cloning, .cloningDraft: "Clone"
        case .retitling: "Rename"
        case .containing: "Add"
        }
    }
}

/// A container's primary sequence, under its children's heading: by the id it goes by, cloned into a
/// new alternative, or renamed, each once it is titled.
struct PrimarySequence: View {
    let name: String?
    let clone: (String) -> Void
    /// Renames it, and with true the primary sequence of each container beneath it too.
    let rename: (String, Bool) -> Void
    /// Adds a new container of a kind beneath, named last in it.
    let add: (ContainerType, Title) async -> Void
    @State private var asking: Asking?

    private enum Asking: Identifiable {
        case cloning, renaming
        case adding(ContainerType)

        var id: String {
            switch self {
            case .cloning: "cloning"
            case .renaming: "renaming"
            case .adding(let type): "adding:\(type.rawValue)"
            }
        }
    }

    var body: some View {
        HStack {
            Text("Primary sequence: \(name ?? "unnamed")").font(.callout).foregroundStyle(.secondary)
            Spacer()
            ActionsMenu {
                Button("Clone…") { asking = .cloning }
                    .help("A new alternative playing these children, to edit before it is stored.")
                Button("Rename…") { asking = .renaming }
                Menu("New Container") {
                    ForEach(ContainerType.allCases, id: \.self) { type in
                        Button("\(type.title)…") { asking = .adding(type) }
                    }
                }
                .help("A new container of the kind chosen, holding nothing yet, last among these children.")
            }
        }
        .font(.body)
        .sheet(item: $asking) { asking in
            switch asking {
            case .cloning:
                TitlePrompt(
                    question: "A new alternative playing these children: what is it called?",
                    initial: "",
                    action: "Clone",
                    done: { title, _ in clone(title.rawValue) }
                )
            case .renaming:
                TitlePrompt(
                    question:
                        "What is the primary sequence called? It is kept as an id: lower case, words joined by hyphens.",
                    initial: name ?? "",
                    action: "Rename",
                    option: TitlePrompt.Option(
                        label: "Also rename the primary sequence of each container beneath it",
                        help: "Each one refuses the name alone when another of its sequences has it."
                    ),
                    done: { title, beneath in rename(title.rawValue, beneath) }
                )
            case .adding(let type):
                TitlePrompt(
                    question: "A new \(type.title.lowercased()) last among these children: what is it called?",
                    initial: "",
                    action: "Add",
                    done: { title, _ in Task { await add(type, title) } }
                )
            }
        }
    }
}

/// A row's actions, behind an icon in its top right corner.
struct ActionsMenu<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Menu {
            content
        } label: {
            Image(systemName: "line.3.horizontal")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Actions")
    }
}

extension DraftAlternative.Entry {
    var isSpecial: Bool { if case .special = self { true } else { false } }

    var symbol: String {
        switch self {
        case .item: "arrow.turn.down.right"
        case .special: "film"
        case .container: "folder"
        }
    }

    /// What taking it out of the alternative does.
    var removal: String {
        switch self {
        case .item: "Not played by the alternative."
        case .special: "Out of the alternative, and unassigned."
        case .container: "Out of the alternative, and gone unless another alternative plays it."
        }
    }
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
#endif
