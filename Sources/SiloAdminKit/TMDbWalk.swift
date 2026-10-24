// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SmdKit
import SmdSidecar

/// A held container's tree reviewed against TMDb a container at a time: the stops the walk has found,
/// each with its reading and what the operator chose, the series' specials beside every stop, and
/// where each was placed. Nothing of it reaches the silo until the walk is stored, and then only what a
/// confirmed stop took. `TmdbWalk.md`.
public struct TMDbWalk: Hashable, Sendable, Identifiable {
    /// Where a stop stands: queued and not yet confirmed, confirmed with a change pending, or confirmed
    /// with nothing taken.
    public enum StopState: Hashable, Sendable {
        case pending
        case changed
        case lookedAt
    }

    /// One container of the walk: its differences as last read, the ones ticked now, and the ones
    /// confirming it last kept, which are what storing the walk stores.
    public struct Stop: Hashable, Sendable, Identifiable {
        public var id: String
        public var title: String
        public var type: String
        public var parent: String?
        /// The stops beneath it, in the order its sequences hold them, once it is confirmed.
        public var children: [String] = []
        public var comparison: AdminConsole.TMDbComparison?
        public var chosen: Set<String> = []
        /// What confirming it last kept; nil until it is confirmed.
        public var taken: Set<String>?

        public init(id: String, title: String, type: String, parent: String? = nil) {
            self.id = id
            self.title = title
            self.type = type
            self.parent = parent
        }
    }

    public let id: UUID
    public var library: String
    public var root: String
    public var stops: [String: Stop]
    /// The series whose specials sit beside every stop: the root, or the nearest series above it.
    public var series: String?
    /// The series' specials nothing covers, in TMDb's season 0 order, placed or not.
    public var specials: [Special] = []
    /// The specials the series' sidecar declines, which may be placed after all.
    public var declined: [Special] = []
    public var suggestions: [Int: AdminConsole.SpecialSuggestion] = [:]
    /// Where each special goes, by its TMDb id; one with none is unassigned.
    public var placements: [Int: SpecialPlacement] = [:]
    /// Series of the operator's own the walk makes for specials, by id, as documents: each made at the
    /// top of the library before anything that refers to it.
    public var companions: [String: String] = [:]
    /// The steps a store made, by id, so a store after a refusal makes only the rest.
    public var stored: Set<String> = []

    public init(library: String, root: Stop) {
        id = UUID()
        self.library = library
        self.root = root.id
        stops = [root.id: root]
    }

    /// The walk's stops depth first, each container's children in the order its sequences hold them.
    public var order: [String] {
        var ordered: [String] = []
        func visit(_ id: String) {
            guard let stop = stops[id], !ordered.contains(id) else { return }
            ordered.append(id)
            stop.children.forEach(visit)
        }
        visit(root)
        return ordered
    }

    /// The first stop in the tree's order not yet confirmed.
    public var next: String? { order.first { stops[$0]?.taken == nil } }

    public func state(of id: String) -> StopState {
        guard let taken = stops[id]?.taken else { return .pending }
        return taken.isEmpty && placed(in: id).isEmpty ? .lookedAt : .changed
    }

    /// The container whose pending change a placement is part of: the one the special goes in, the one
    /// that refers to it, or, for a decline, the series.
    public func home(of placement: SpecialPlacement) -> String? {
        switch placement {
        case .entry(let id, _, _), .extra(let id, _), .child(let id, _, _), .edition(let id, _), .version(let id, _, _):
            id
        case .duplicate(_, _, _, let from, _), .breakout(_, let from, _): from
        case .declined: series
        }
    }

    /// The specials placed as part of a stop's pending change.
    public func placed(in stop: String) -> [Special] {
        (specials + declined).filter { special in
            placements[special.id].map { home(of: $0) == stop } ?? false
        }
    }

    public var unassigned: [Special] { specials.filter { placements[$0.id] == nil } }

    /// A stop's reading, as far as it has got. The series' specials are taken from it to sit beside
    /// every stop, rather than as its own differences.
    public mutating func read(_ comparison: AdminConsole.TMDbComparison) {
        stops[comparison.container]?.comparison = comparison
        stops[comparison.container]?.title = comparison.title
        if comparison.container == series {
            pool(comparison)
        } else {
            suggestAlternatives(of: [comparison])
        }
    }

    /// The series' specials, from its reading, each suggested as an alternative of a stop read already
    /// where that is stronger than the series' reading suggests.
    public mutating func pool(_ comparison: AdminConsole.TMDbComparison) {
        specials = comparison.differences.compactMap { if case .special(let special) = $0 { special } else { nil } }
        declined = comparison.declined
        suggestions = comparison.suggestions
        suggestAlternatives(of: order.compactMap { $0 == series ? nil : stops[$0]?.comparison })
    }

    /// Each unassigned special suggested as another way to play a container a stop read, unless what it
    /// is suggested for already rests on something stronger.
    private mutating func suggestAlternatives(of readings: [AdminConsole.TMDbComparison]) {
        let held = readings.compactMap { reading in
            (try? SidecarFile.sidecar(from: reading.opened.sidecar)).map { (reading, $0.container) }
        }
        guard !held.isEmpty else { return }
        for special in unassigned where (suggestions[special.id]?.basis ?? .title) > .alternative {
            for (reading, container) in held {
                guard
                    let suggestion = AdminConsole.alternative(
                        of: special,
                        in: [container],
                        titles: reading.episodeTitles,
                        runtimes: reading.runtimes
                    )
                else { continue }
                suggestions[special.id] = suggestion
                break
            }
        }
    }

    /// Keeps what is ticked as the stop's pending change, and adds the stops found beneath it.
    public mutating func confirm(_ id: String, beneath: [Stop]) {
        guard var stop = stops[id] else { return }
        stop.taken = stop.chosen
        // Confirmed again after a store made its edit, its edit is to be made again.
        stored.remove("edit:\(id)")
        for child in beneath where stops[child.id] == nil { stops[child.id] = child }
        stop.children = beneath.map(\.id)
        stops[id] = stop
    }

    /// Puts a special where the operator says, or, with nil, back among the unassigned. A new companion
    /// series it names is kept with the walk until the walk is stored.
    public mutating func place(_ special: Int, _ placement: SpecialPlacement?, companion: Container? = nil) {
        placements[special] = placement
        if let companion { companions[companion.id.value] = TMDbTree.text(companion) }
    }

    /// A companion series new in the walk, as its document says it.
    public func companion(_ id: String) -> Container? {
        companions[id].flatMap { try? ContainerFile.container(from: Data($0.utf8)) }
    }
}
