// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SmdKit

/// An alternative being drafted for a container, made as a sequence of its own and an alternative naming
/// it when the container is made or edited: its title, and what it plays, in order, each one of the
/// container's items referred to, or a special placed in it.
public struct DraftAlternative: Hashable, Sendable, Codable, Identifiable {
    public enum Entry: Hashable, Sendable, Codable {
        /// One of the container's items, by its id, referred to as an alternative refers to one.
        case item(String)
        /// A special placed in the alternative, by its TMDb id.
        case special(Int)
    }

    public let id: String
    public var title: String
    public var entries: [Entry]

    public init(id: String = UUID().uuidString, title: String, entries: [Entry]) {
        self.id = id
        self.title = title
        self.entries = entries
    }

    /// The specials it plays.
    public var specials: [Int] {
        entries.compactMap { if case .special(let id) = $0 { id } else { nil } }
    }

    /// What a sequence of a container plays, as a drafted alternative's entries: each item it declares,
    /// and each of the container's own it refers to; a reference to another container's is left out.
    static func entries(of sequence: Sequence, in container: Container) -> [Entry] {
        sequence.items.compactMap { entry in
            if let id = entry.id { return .item(id.value) }
            guard let ref = entry.reference, ref.container == nil || ref.container == container.id else { return nil }
            return .item(ref.item.value)
        }
    }

    /// A container's drafted alternatives made in it, in order: each a sequence holding its entries, a
    /// special as an entry carrying its references, an item as a reference to it, then an alternative
    /// with its title naming that sequence. An item the container no longer holds, or a special not
    /// among those given, is left out, and an alternative left with nothing to play is not made.
    static func make(_ drafts: [DraftAlternative], specials: [Special], in container: inout Container) {
        // A special in more than one is an entry in the first, and referred to from the rest.
        var made: [Int: ItemID] = [:]
        for draft in drafts {
            let held = container.itemIDs
            let sequence = Slug.unique(from: draft.title, avoiding: Set(container.sequences.compactMap(\.id)))
            container.sequences.append(Sequence(id: sequence, items: []))
            let index = container.sequences.count - 1
            for entry in draft.entries {
                switch entry {
                case .item(let item):
                    guard let id = ItemID(item), held.contains(id) else { continue }
                    container.sequences[index].items.append(.ref(EntryRef(item: id)))
                case .special(let id):
                    if let item = made[id] {
                        container.sequences[index].items.append(.ref(EntryRef(item: item)))
                        continue
                    }
                    guard let special = specials.first(where: { $0.id == id }) else { continue }
                    let leaf = TMDbTree.leaf(special, type: .episode, in: container)
                    made[id] = leaf.id
                    container.sequences[index].items.append(leaf)
                }
            }
            guard !container.sequences[index].items.isEmpty else {
                container.sequences.remove(at: index)
                continue
            }
            container.alternatives.append(
                Alternative(
                    id: Slug.unique(from: draft.title, avoiding: Set(container.alternatives.map(\.id))),
                    sequence: sequence,
                    title: draft.title
                )
            )
        }
    }
}

/// What places a series' specials and drafts alternatives of its containers: a walk, or a draft from
/// TMDb. A special in a drafted alternative is placed in the first of its container's that plays it; a
/// clone of an alternative plays its specials too, referring to them where the first does.
public protocol AlternativeDrafting {
    var placements: [Int: SpecialPlacement] { get set }
    /// The alternatives drafted for each container, by its id, in the order they are made.
    var draftedAlternatives: [String: [DraftAlternative]] { get set }
    /// Every special that may be placed.
    var placeable: [Special] { get }
    func container(_ id: String) -> Container?
    /// The title of one of a container's items, by its id.
    func title(ofItem item: String, at container: String) -> String
    /// A container's specials or alternatives changed: for a walk, its stop pending again.
    mutating func alternativesChanged(at container: String)
}

extension AlternativeDrafting {
    /// A container's drafted alternatives.
    public func alternatives(draftedAt container: String) -> [DraftAlternative] {
        draftedAlternatives[container] ?? []
    }

    /// One of a drafted alternative's entries, by its title.
    public func title(of entry: DraftAlternative.Entry, at container: String) -> String {
        switch entry {
        case .item(let item): title(ofItem: item, at: container)
        case .special(let id): placeable.first { $0.id == id }?.episode.title ?? String(id)
        }
    }

    /// A new alternative of a container, titled as given, playing the special given alone or nothing yet.
    @discardableResult
    public mutating func draftAlternative(
        at container: String,
        titled title: String,
        playing special: Int? = nil
    )
        -> String
    {
        let draft = DraftAlternative(title: title, entries: [])
        draftedAlternatives[container, default: []].append(draft)
        alternativesChanged(at: container)
        if let special { insert(special, into: draft.id, at: 0, of: container) }
        return draft.id
    }

    /// A new alternative of a container, titled as given, playing what one of its sequences does: each
    /// item it declares or refers to of the container's own, by reference.
    @discardableResult
    public mutating func cloneSequence(_ index: Int, of container: String, titled title: String) -> String? {
        guard let held = self.container(container), held.sequences.indices.contains(index) else { return nil }
        let draft = DraftAlternative(
            title: title,
            entries: DraftAlternative.entries(of: held.sequences[index], in: held)
        )
        draftedAlternatives[container, default: []].append(draft)
        alternativesChanged(at: container)
        return draft.id
    }

    /// A new alternative of a container, titled as given, playing what one drafted for it does, its
    /// specials included.
    @discardableResult
    public mutating func cloneDraft(_ draft: String, of container: String, titled title: String) -> String? {
        guard let index = index(of: draft, at: container) else { return nil }
        let clone = DraftAlternative(title: title, entries: draftedAlternatives[container]![index].entries)
        draftedAlternatives[container]!.append(clone)
        alternativesChanged(at: container)
        return clone.id
    }

    /// A special placed in a drafted alternative at a position, out of wherever it was placed before,
    /// every drafted alternative it was in included.
    public mutating func insert(_ special: Int, into draft: String, at position: Int, of container: String) {
        guard let index = index(of: draft, at: container) else { return }
        var position = position
        if let was = draftedAlternatives[container]?[index].entries.firstIndex(of: .special(special)), was < position {
            position -= 1
        }
        unplace(special)
        let count = draftedAlternatives[container]![index].entries.count
        draftedAlternatives[container]![index].entries.insert(.special(special), at: min(max(position, 0), count))
        placements[special] = .alternative(of: container, draft: draft)
        alternativesChanged(at: container)
    }

    /// A special in a drafted alternative in place of one of its entries; a special it replaces is
    /// unassigned again.
    public mutating func replace(_ position: Int, in draft: String, with special: Int, of container: String) {
        guard let index = index(of: draft, at: container),
            draftedAlternatives[container]![index].entries.indices.contains(position)
        else { return }
        let replaced = draftedAlternatives[container]![index].entries[position]
        guard replaced != .special(special) else { return }
        removeEntry(position, from: draft, of: container)
        insert(special, into: draft, at: position, of: container)
    }

    /// A drafted alternative's entries moved, as a list moves its rows.
    public mutating func moveEntries(_ offsets: IndexSet, to destination: Int, in draft: String, of container: String) {
        guard let index = index(of: draft, at: container) else { return }
        var entries = draftedAlternatives[container]![index].entries
        let moving = offsets.filter(entries.indices.contains).map { entries[$0] }
        let before = offsets.filter { $0 < destination }.count
        for offset in offsets.sorted(by: >) where entries.indices.contains(offset) { entries.remove(at: offset) }
        entries.insert(contentsOf: moving, at: min(max(destination - before, 0), entries.count))
        draftedAlternatives[container]![index].entries = entries
        alternativesChanged(at: container)
    }

    /// One of a drafted alternative's entries out of it: an item no longer played, or a special
    /// unassigned again.
    public mutating func removeEntry(_ position: Int, from draft: String, of container: String) {
        guard let index = index(of: draft, at: container),
            draftedAlternatives[container]![index].entries.indices.contains(position)
        else { return }
        let removed = draftedAlternatives[container]![index].entries.remove(at: position)
        if case .special(let special) = removed { placeInFirst(special, at: container) }
        alternativesChanged(at: container)
    }

    public mutating func retitle(_ draft: String, to title: String, of container: String) {
        guard let index = index(of: draft, at: container) else { return }
        draftedAlternatives[container]![index].title = title
        alternativesChanged(at: container)
    }

    /// A drafted alternative discarded, the specials it played unassigned again.
    public mutating func discard(_ draft: String, of container: String) {
        guard let index = index(of: draft, at: container) else { return }
        let removed = draftedAlternatives[container]!.remove(at: index)
        for special in removed.specials { placeInFirst(special, at: container) }
        if draftedAlternatives[container]?.isEmpty == true { draftedAlternatives[container] = nil }
        alternativesChanged(at: container)
    }

    /// The containers' drafted alternatives discarded with them, once they leave.
    mutating func discardAlternatives(of containers: Set<String>) {
        for container in containers { draftedAlternatives[container] = nil }
    }

    /// A special out of every drafted alternative it is in, and unassigned.
    mutating func unplace(_ special: Int) {
        if let home = placements[special]?.container { alternativesChanged(at: home) }
        if case .alternative(let container, _)? = placements[special], var drafts = draftedAlternatives[container] {
            for index in drafts.indices { drafts[index].entries.removeAll { $0 == .special(special) } }
            draftedAlternatives[container] = drafts
            alternativesChanged(at: container)
        }
        placements[special] = nil
    }

    /// A special taken out of one of a container's drafted alternatives placed in the first that still
    /// plays it, or unassigned when none does.
    private mutating func placeInFirst(_ special: Int, at container: String) {
        placements[special] = draftedAlternatives[container]?.first { $0.entries.contains(.special(special)) }
            .map { .alternative(of: container, draft: $0.id) }
    }

    /// A placement as it is kept: another version of a container, or of one of its items, as a drafted
    /// alternative the special is placed in; any other as it is. A version of an item the container does
    /// not hold is kept as it is, and makes nothing.
    mutating func settle(_ special: Int, _ placement: SpecialPlacement?) -> SpecialPlacement? {
        switch placement {
        case .edition(let container, let title)?:
            let draft = DraftAlternative(title: title, entries: [.special(special)])
            draftedAlternatives[container, default: []].append(draft)
            return .alternative(of: container, draft: draft.id)
        case .version(let container, let item, let title)?:
            guard let held = self.container(container),
                let source = held.sequences.first(where: { $0.items.contains { $0.id?.value == item } })
            else { return placement }
            let entries = DraftAlternative.entries(of: source, in: held).map {
                $0 == .item(item) ? .special(special) : $0
            }
            let draft = DraftAlternative(title: title, entries: entries)
            draftedAlternatives[container, default: []].append(draft)
            return .alternative(of: container, draft: draft.id)
        default:
            return placement
        }
    }

    /// Every special kept as another version of a container, or of one of its items, placed again as a
    /// drafted alternative, as a walk or draft kept before alternatives were drafted is read.
    mutating func settlingVersions() {
        for (special, placement) in placements.sorted(by: { $0.key < $1.key }) {
            switch placement {
            case .edition, .version: placements[special] = settle(special, placement)
            default: continue
            }
        }
    }

    private func index(of draft: String, at container: String) -> Int? {
        draftedAlternatives[container]?.firstIndex { $0.id == draft }
    }
}

extension TMDbTree: AlternativeDrafting {
    public var draftedAlternatives: [String: [DraftAlternative]] {
        get { alternativeDrafts ?? [:] }
        set { alternativeDrafts = newValue.isEmpty ? nil : newValue }
    }

    public var placeable: [Special] { specials }

    public mutating func alternativesChanged(at container: String) { edited = .now }

    /// The title of one of a container's items, by its id: its own, or TMDb's for the episode it carries.
    public func title(ofItem item: String, at id: String) -> String {
        guard let entry = container(id)?.sequences.flatMap(\.items).first(where: { $0.id?.value == item }) else {
            return item
        }
        if let title = entry.title { return title }
        let ref = entry.externalRefs.first { $0.provider == .tmdb }
        return ref.flatMap { episodeTitles[$0.value] } ?? specials.first { $0.episode.ref == ref }?.episode.title
            ?? item
    }
}
