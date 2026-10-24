// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SmdKit
import SmdSidecar
import Synchronization

/// A held container's tree reviewed against TMDb a container at a time: the stops the walk has found,
/// each with its reading and what the operator chose, the series' specials beside every stop, and
/// where each was placed. Nothing of it reaches the silo until the walk is stored, and then only what a
/// confirmed stop took. `TmdbWalk.md`.
public struct TMDbWalk: Hashable, Sendable, Identifiable, Codable {
    /// Where a stop stands: queued and not yet confirmed, confirmed with a change pending, or confirmed
    /// with nothing taken.
    public enum StopState: Hashable, Sendable {
        case pending
        case changed
        case lookedAt
    }

    /// One container of the walk: its differences as last read, the ones ticked now, and the ones
    /// confirming it last kept, which are what storing the walk stores.
    public struct Stop: Hashable, Sendable, Identifiable, Codable {
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

        /// A new stop for a container of a draft, everything it is offered with chosen to begin with.
        init(newIn tree: TMDbTree, _ id: String, parent: String, offering: [AdminConsole.TMDbDifference]) {
            let container = tree.container(id)
            self.init(
                id: id,
                title: container?.displayTitle ?? id,
                type: container?.type.rawValue ?? "",
                parent: parent
            )
            chosen = Set(offering.map(\.id))
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
    /// The containers the walk makes, a missing child chosen at a stop and what is beneath it, each as a
    /// draft from TMDb by the id of its top: every container of a draft is a new stop.
    public var drafts: [String: TMDbTree] = [:]
    /// When the walk was last kept on this Mac.
    public var edited: Date
    /// The season of TMDb's the operator said each held season carrying no TMDb id is, by TMDb id: what
    /// the season and the containers beneath it are read as. Absent from a walk kept before it was asked.
    private var identifiedSeasons: [String: Int]?

    public var identified: [String: Int] { identifiedSeasons ?? [:] }

    public init(library: String, root: Stop) {
        id = UUID()
        self.library = library
        self.root = root.id
        stops = [root.id: root]
        edited = .now
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

    /// Says which of TMDb's seasons a held season carrying no TMDb id is, or, given none, that it is
    /// unmatched again. The season and every stop read beneath it are to be read again, and the season's
    /// TMDb id is chosen to be taken.
    public mutating func identify(_ stop: String, as season: Int?) {
        var identified = identified
        identified[stop] = season
        identifiedSeasons = identified
        stops[stop]?.chosen = season.map { ["ref::tmdb:\($0)"] } ?? []
        for id in [stop] + beneath(stop) where !isNew(id) {
            stops[id]?.comparison = nil
            stops[id]?.taken = nil
        }
    }

    /// The stops beneath a stop, all the way down.
    private func beneath(_ stop: String) -> [String] {
        (stops[stop]?.children ?? []).flatMap { [$0] + beneath($0) }
    }

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

    /// Keeps what is ticked as the stop's pending change, and adds the stops found beneath it: the
    /// containers the library holds there, then each missing child chosen, as a new stop. A missing child
    /// no longer chosen leaves, with every stop beneath it.
    public mutating func confirm(_ id: String, beneath: [Stop], drafts new: [TMDbTree] = []) {
        guard var stop = stops[id] else { return }
        stop.taken = stop.chosen
        // Confirmed again after a store made its edit, its edit is to be made again.
        stored.remove("edit:\(id)")
        for top in leaving(confirming: id) { remove(top) }
        // A season drafted already, by a confirm made twice at once, is not drafted again.
        let drafted = Set(drafts.values.map(Self.missing))
        for tree in new where !drafted.contains(Self.missing(tree)) {
            drafts[tree.top] = tree
            stops[tree.top] = Stop(newIn: tree, tree.top, parent: id, offering: offered(tree.top, in: tree))
        }
        for child in beneath where stops[child.id] == nil { stops[child.id] = child }
        let tops = drafts.values.filter { $0.creating.parent == id }.map(\.top).sorted()
        stop.children = beneath.map(\.id) + tops.filter { !beneath.map(\.id).contains($0) }
        stops[id] = stop
    }

    /// The new stops confirming a stop would take out of the walk: those whose missing child is no longer
    /// chosen there.
    public func leaving(confirming id: String) -> [String] {
        guard let chosen = stops[id]?.chosen else { return [] }
        return drafts.values.filter { tree in
            tree.creating.parent == id && !chosen.contains(Self.missing(tree))
        }
        .map(\.top).sorted()
    }

    /// The difference a draft is the missing child of.
    static func missing(_ tree: TMDbTree) -> String {
        let ref = tree.container(tree.top)?.externalRefs.first { $0.provider == .tmdb }
        return "season:\(ref?.value ?? "")"
    }

    /// A new stop and every container beneath it out of the walk, the specials placed in them unassigned
    /// again.
    private mutating func remove(_ top: String) {
        guard let tree = drafts.removeValue(forKey: top) else { return }
        let ids = Set(tree.containers.map(\.id.value))
        for id in ids { stops[id] = nil }
        for (special, placement) in placements where home(of: placement).map(ids.contains) ?? false {
            placements[special] = nil
        }
        if let parent = tree.creating.parent { stops[parent]?.children.removeAll { $0 == top } }
    }

    /// The draft a new stop is a container of.
    public func draft(holding id: String) -> TMDbTree? {
        drafts.values.first { $0.documents[id] != nil }
    }

    public func isNew(_ id: String) -> Bool { draft(holding: id) != nil }

    /// A stop's container: as its draft has it for a new stop, as its reading found it otherwise.
    public func container(_ id: String) -> Container? {
        if let tree = draft(holding: id) { return tree.container(id) }
        return (stops[id]?.comparison?.opened.sidecar).flatMap { try? SidecarFile.sidecar(from: $0).container }
    }

    /// What a new stop is created with that the operator may leave out: its year, its outline, attributed
    /// to TMDb, and its references.
    public func offered(_ id: String, in tree: TMDbTree? = nil) -> [AdminConsole.TMDbDifference] {
        guard let container = (tree ?? draft(holding: id))?.container(id) else { return [] }
        var offered: [AdminConsole.TMDbDifference] = []
        if let year = container.year { offered.append(.year(year)) }
        let record = container.externalRefs.first { $0.provider == .tmdb }?.value ?? ""
        if let outline = container.outline, !outline.isEmpty { offered.append(.outline(outline, record: record)) }
        offered += container.externalRefs.map { .reference(item: nil, $0) }
        return offered
    }

    /// Reshapes a new stop's draft, as a draft from TMDb is shaped: a container of it set, or its entries
    /// regrouped. Each container the shaping makes beneath a new stop is a new stop once that stop is
    /// confirmed.
    public mutating func shape(_ id: String, _ change: (inout TMDbTree) -> Void) {
        guard let top = draft(holding: id)?.top, var tree = drafts[top] else { return }
        change(&tree)
        drafts[top] = tree
        for container in tree.containers where stops[container.id.value] != nil {
            stops[container.id.value]?.title = container.displayTitle
            stops[container.id.value]?.type = container.type.rawValue
        }
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

/// The walks this Mac keeps, by the `ServerID` of the silo each is for, until each is stored or
/// discarded: one JSON object rewritten atomically whole on every change, as the drafts are. The silo
/// holds nothing of a walk.
public final class TMDbWalkStore: Sendable {
    public let file: URL
    private let entries: Mutex<[String: [TMDbWalk]]>

    public init(file: URL) {
        self.file = file
        entries = Mutex(Self.read(file))
    }

    /// In memory only, for tests and for platforms where the app passes no file.
    public init() {
        file = URL(fileURLWithPath: "/dev/null")
        entries = Mutex([:])
    }

    /// A silo's walks, most recently kept first.
    public func walks(of silo: String) -> [TMDbWalk] {
        entries.withLock { $0[silo] ?? [] }.sorted { $0.edited > $1.edited }
    }

    /// The walk kept for a container's tree, rooted at it.
    public func walk(rootedAt container: String, in library: String, of silo: String) -> TMDbWalk? {
        walks(of: silo).first { $0.root == container && $0.library == library }
    }

    /// Keeps a walk, in place of the one it was and of any other rooted at the same container.
    public func save(_ walk: TMDbWalk, for silo: String) throws {
        try entries.withLock { entries in
            var walks = entries[silo] ?? []
            walks.removeAll { $0.id == walk.id || ($0.root == walk.root && $0.library == walk.library) }
            walks.append(walk)
            entries[silo] = walks
            try Self.persist(entries, to: file)
        }
    }

    public func remove(_ id: TMDbWalk.ID, of silo: String) throws {
        try entries.withLock { entries in
            guard let index = entries[silo]?.firstIndex(where: { $0.id == id }) else { return }
            entries[silo]?.remove(at: index)
            if entries[silo]?.isEmpty == true { entries[silo] = nil }
            try Self.persist(entries, to: file)
        }
    }

    /// Every walk for the silo, gone: forgetting's share.
    public func removeAll(of silo: String) throws {
        try entries.withLock { entries in
            guard entries.removeValue(forKey: silo) != nil else { return }
            try Self.persist(entries, to: file)
        }
    }

    private static func persist(_ entries: [String: [TMDbWalk]], to file: URL) throws {
        guard file.path != "/dev/null" else { return }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(entries).write(to: file, options: .atomic)
    }

    private static func read(_ file: URL) -> [String: [TMDbWalk]] {
        (try? JSONDecoder().decode([String: [TMDbWalk]].self, from: Data(contentsOf: file))) ?? [:]
    }
}
