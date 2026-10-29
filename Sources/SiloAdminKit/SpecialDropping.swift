// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import SmdKit

/// One of a drafted container's children as its list shows them: an entry of one of its sequences, or a
/// special placed in its primary sequence, in its place among the entries.
public enum DraftChild: Hashable, Sendable {
    case entry(Entry)
    case special(Special)

    /// The key it is moved by: an entry's item id, or the special's TMDb id marked as a special's.
    public var key: String {
        switch self {
        case .entry(let entry): entry.id?.value ?? ""
        case .special(let special): Self.key(of: special.id)
        }
    }

    static func key(of special: Int) -> String { "special:\(special)" }

    /// The special a key names, when it names one.
    public static func special(_ key: String) -> Int? {
        key.hasPrefix("special:") ? Int(key.dropFirst("special:".count)) : nil
    }
}

extension TMDbTree {
    /// A drafted container's children: its primary sequence's entries with each special placed in it
    /// before the entry at its position, or after them all with none, then its other sequences' entries.
    public static func children(
        of container: Container?,
        placements: [Int: SpecialPlacement],
        specials: [Special]
    ) -> [DraftChild] {
        guard let container else { return [] }
        let primary = container.sequences.first?.items ?? []
        let placed = specials.compactMap { special in
            position(of: special.id, in: container, placements: placements).map { (special, $0) }
        }
        var children: [DraftChild] = []
        for (index, entry) in primary.enumerated() {
            children += placed.filter { $0.1 == index }.map { .special($0.0) }
            children.append(.entry(entry))
        }
        children += placed.filter { $0.1 >= primary.count }.map { .special($0.0) }
        return children + container.sequences.dropFirst().flatMap(\.items).map(DraftChild.entry)
    }

    /// Where a special is placed in a container's primary sequence, past its last entry when no position
    /// is given; nil when it is placed elsewhere.
    static func position(of special: Int, in container: Container, placements: [Int: SpecialPlacement]) -> Int? {
        guard case .entry(let home, let sequence, let position) = placements[special], home == container.id.value,
            sequence == nil || sequence == container.sequences.first?.id
        else { return nil }
        return position ?? container.sequences.first?.items.count ?? 0
    }

    /// Where in a container's primary sequence a special goes to be before the child whose key is given:
    /// an entry's position, or the position of the special placed there; nil for last.
    static func position(
        before target: String?,
        in container: Container?,
        placements: [Int: SpecialPlacement]
    ) -> Int? {
        guard let target, let container else { return nil }
        if let special = DraftChild.special(target) {
            return position(of: special, in: container, placements: placements)
        }
        return container.sequences.first?.items.firstIndex { $0.id?.value == target }
    }

    /// The entry an entry moved before the child whose key is given goes before: that entry, or the one a
    /// special there is placed before; nil for last.
    public static func entry(
        before target: String?,
        in container: Container?,
        placements: [Int: SpecialPlacement]
    ) -> ItemID? {
        guard let target else { return nil }
        guard DraftChild.special(target) != nil else { return ItemID(target) }
        let items = container?.sequences.first?.items ?? []
        return position(before: target, in: container, placements: placements)
            .flatMap { items.indices.contains($0) ? items[$0].id : nil }
    }

    /// A special dropped among a container's children: placed in its primary sequence before the child
    /// whose key is given, or last with none.
    public mutating func place(_ special: Int, in parent: String, before target: String?) {
        let position = Self.position(before: target, in: container(parent), placements: placements)
        place(special, .entry(in: parent, position: position))
    }
}

extension TMDbWalk {
    /// A special dropped among a stop's children, before the child whose key is given or last with none:
    /// in a new stop placed in its draft's primary sequence there, and in a held stop placed in its
    /// primary sequence and moved before the child, as the operator would move it after placing it.
    public mutating func place(_ special: Int, at stop: String, before target: String?) {
        guard !isNew(stop) else {
            let position = TMDbTree.position(before: target, in: container(stop), placements: placements)
            place(special, .entry(in: stop, position: position))
            return
        }
        // Unplaced first, so one placed here already is found where it is placed again.
        place(special, nil)
        let listed = Set(sequence(at: stop).map(\.key))
        place(special, .entry(in: stop))
        guard let key = sequence(at: stop).map(\.key).first(where: { !listed.contains($0) }) else { return }
        arrange(key, at: stop, before: target)
    }
}
