// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import SmdKit

/// One of a container's sequences reordered: which sequence, and for each place in it now, the place its
/// entry had before.
struct Reordering: Equatable {
    let sequence: Int
    let id: String?
    let order: [Int]
}

extension SpecialPlacement {
    /// An entry placed in a reordered sequence, kept after the entry it followed, or first when it was.
    func reordered(_ reordering: Reordering, in container: String) -> SpecialPlacement {
        guard case .entry(let home, let sequence, let position?) = self, home == container, position > 0,
            sequence == reordering.id || (sequence == nil && reordering.sequence == 0),
            let followed = reordering.order.firstIndex(of: min(position, reordering.order.count) - 1)
        else { return self }
        return .entry(in: home, sequence: sequence, position: followed + 1)
    }
}

extension TMDbTree {
    /// One of a container's entries moved before another of the same sequence, or, with none, last in
    /// it: an episode, or a group as the entry naming it. The specials placed in the sequence keep after
    /// the entries they followed.
    @discardableResult
    public mutating func move(_ item: ItemID, in parentID: String, before target: ItemID?) -> Bool {
        guard let reordering = reorder(item, in: parentID, before: target) else { return false }
        placements = placements.mapValues { $0.reordered(reordering, in: parentID) }
        return true
    }

    mutating func reorder(_ item: ItemID, in parentID: String, before target: ItemID?) -> Reordering? {
        guard item != target, var parent = container(parentID),
            let sequence = parent.sequences.firstIndex(where: { $0.items.contains { $0.id == item } }),
            let from = parent.sequences[sequence].items.firstIndex(where: { $0.id == item })
        else { return nil }
        var order = Array(parent.sequences[sequence].items.indices)
        order.remove(at: from)
        if let target {
            guard let place = order.firstIndex(where: { parent.sequences[sequence].items[$0].id == target })
            else { return nil }
            order.insert(from, at: place)
        } else {
            order.append(from)
        }
        guard order != Array(order.indices) else { return nil }
        parent.sequences[sequence].items = order.map { parent.sequences[sequence].items[$0] }
        documents[parentID] = Self.text(parent)
        edited = .now
        return Reordering(sequence: sequence, id: parent.sequences[sequence].id, order: order)
    }
}

extension TMDbWalk {
    /// One of a new stop's entries moved before another of the same sequence, or, with none, last in it,
    /// as a draft's are; the specials the walk places in the sequence keep after the entries they
    /// followed.
    @discardableResult
    public mutating func move(_ item: ItemID, at stop: String, before target: ItemID?) -> Bool {
        var reordering: Reordering?
        shape(stop) { reordering = $0.reorder(item, in: stop, before: target) }
        guard let reordering else { return false }
        placements = placements.mapValues { $0.reordered(reordering, in: stop) }
        return true
    }
}
