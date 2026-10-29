// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import SmdKit

extension TMDbWalk {
    /// The companion series the walk makes, in the order they were added.
    public var companionStops: [String] { companionOrder ?? [] }

    /// A new companion series beside the walked one, a stop of the walk with no parent, drafted holding
    /// what the series given holds: listed after the root's tree, shaped and confirmed as any new stop
    /// is, and made at the top of the library, before anything that refers to it, once it is confirmed.
    @discardableResult
    public mutating func addCompanion(_ series: Container) -> Bool {
        let id = series.id.value
        guard series.type == .series, drafts[id] == nil, stops[id] == nil else { return false }
        let tree = TMDbTree(
            library: library,
            record: TMDb.Record(.series, 0),
            creating: ContainerDraft.Creating(),
            containers: [series],
            top: series.id
        )
        drafts[id] = tree
        var stop = Stop(id: id, title: series.displayTitle, type: series.type.rawValue)
        stop.chosen = Set(offered(id, in: tree).map(\.id))
        stops[id] = stop
        companionOrder = companionStops + [id]
        return true
    }

    /// A companion series out of the walk, with every stop beneath it: the specials placed in it, or in
    /// it from another stop, are unassigned again, and those other stops are pending again.
    public mutating func dropCompanion(_ id: String) {
        guard companionStops.contains(id) else { return }
        for (special, placement) in placements {
            guard case .breakout(id, let from, _) = placement else { continue }
            placements[special] = nil
            unconfirm(from)
        }
        remove(id)
        companionOrder = companionStops.filter { $0 != id }
        if companionOrder?.isEmpty == true { companionOrder = nil }
    }

    /// Whether a placement goes into a companion series of the walk not yet confirmed, which storing
    /// makes nothing of: neither the special's entry in it nor the reference to that entry.
    func waitsOnCompanion(_ placement: SpecialPlacement?) -> Bool {
        guard case .breakout(let id, _, _)? = placement, companionStops.contains(id) else { return false }
        return stops[id]?.taken == nil
    }
}
