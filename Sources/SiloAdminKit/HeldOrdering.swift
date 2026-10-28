// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import SmdKit

/// One of a held stop's entries, in its primary sequence as storing would leave it.
public struct StopEntry: Hashable, Sendable, Identifiable {
    /// The key it is moved by: the container it names, the item it is when the container holds it
    /// already, or the TMDb record it carries.
    public let id: String
    public let title: String
    /// Whether it names a container beneath the stop.
    public let isContainer: Bool
    /// Whether storing adds it: an episode the library lacks, a group made of them, or a special placed.
    public let isAdded: Bool
}

extension TMDbWalk {
    /// A held stop's primary sequence as storing would leave it, were the stop confirmed with every child
    /// its children list ticked and what is placed there now, in the order the operator gave it: so an
    /// unticked child keeps its place, to be ticked there.
    public func storedEntries(at stop: String) -> [StopEntry] {
        guard !isNew(stop), let (before, after) = stored(stop, takingEveryChild: true),
            let sequence = after.sequences.first
        else {
            return []
        }
        let held = Set(before.itemIDs)
        let keys = Set((before.sequences.first?.items ?? []).compactMap { AdminConsole.key(of: $0, held: held) })
        return sequence.items.compactMap { entry in
            AdminConsole.key(of: entry, held: held).map { key in
                StopEntry(
                    id: key,
                    title: title(of: entry, in: after, at: stop),
                    isContainer: entry.childContainer != nil,
                    isAdded: !keys.contains(key)
                )
            }
        }
    }

    /// A held stop's children as its list shows them, in its primary sequence's order as storing would
    /// leave it: what it holds already and each special placed there in its place among the missing
    /// episodes, groups and containers held beneath, to be moved among them. A child storing does not
    /// name yet, as a group whose own stop is not drafted, is listed after the child its list shows it
    /// after, and where the operator moved it.
    public func sequence(at stop: String) -> [HeldStopChild] {
        let children = children(at: stop) + addedContainers(at: stop).map(HeldStopChild.added)
        let listed = Dictionary(children.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var seen: Set<String> = []
        var ordered = storedEntries(at: stop).compactMap { entry -> HeldStopChild? in
            guard seen.insert(entry.id).inserted else { return nil }
            return listed[entry.id] ?? .entry(entry)
        }
        var place = ordered.firstIndex { listed[$0.key] != nil } ?? ordered.endIndex
        for child in children {
            if let index = ordered.firstIndex(where: { $0.key == child.key }) {
                place = index + 1
            } else {
                ordered.insert(child, at: place)
                place += 1
            }
        }
        guard let order = arrangedEntries[stop] else { return ordered }
        return AdminConsole.arranged(ordered, by: order, key: \.key)
    }

    /// One of a held stop's entries, by its key, moved before another, or last with none: the order is
    /// kept with the walk, and the stop's edit puts its primary sequence in it. An entry the order does
    /// not name, as a special placed after the order was given, keeps its place.
    @discardableResult
    public mutating func arrange(_ key: String, at stop: String, before target: String?) -> Bool {
        let order = sequence(at: stop).map(\.key)
        guard key != target, let from = order.firstIndex(of: key) else { return false }
        var keys = order
        keys.remove(at: from)
        if let target {
            guard let place = keys.firstIndex(of: target) else { return false }
            keys.insert(key, at: place)
        } else {
            keys.append(key)
        }
        guard keys != order else { return false }
        arrangedEntries[stop] = keys
        unconfirm(stop)
        return true
    }

    /// A held stop's entries in the order storing would give them had none been moved.
    public mutating func unarrange(_ stop: String) {
        guard arrangedEntries[stop] != nil else { return }
        arrangedEntries[stop] = nil
        unconfirm(stop)
    }
}

extension HeldStopChild {
    /// The key it is moved by, as its entry in the stop's primary sequence goes by.
    public var key: String {
        switch self {
        case .episode(let episode): "tmdb:\(episode.id)"
        case .group(let group): "child:\(group.id)"
        case .held(let held): "child:\(held.id)"
        case .entry(let entry): entry.id
        case .added(let id): "child:\(id)"
        }
    }
}

extension AdminConsole {
    /// The key an entry of a held stop is moved by, given the items the stop holds already.
    public static func key(of entry: Entry, held: Set<ItemID>) -> String? {
        if let child = entry.childContainer { return "child:\(child.value)" }
        if let id = entry.id, held.contains(id) { return "item:\(id.value)" }
        if let ref = entry.externalRefs.first(where: { $0.provider == .tmdb }) { return "tmdb:\(ref.value)" }
        if let id = entry.id { return "item:\(id.value)" }
        return entry.reference.map { "ref:\($0.container?.value ?? ""):\($0.item.value)" }
    }

    /// Entries put in the order given: those it names fill the places they hold between them in that
    /// order, and the rest keep theirs.
    static func arranged(_ items: [Entry], by order: [String], held: Set<ItemID>) -> [Entry] {
        arranged(items, by: order) { key(of: $0, held: held) }
    }

    static func arranged<Item>(_ items: [Item], by order: [String], key: (Item) -> String?) -> [Item] {
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let ranked = items.map { item in key(item).flatMap { rank[$0] } }
        var named = zip(items, ranked).compactMap { item, rank in rank.map { (item, $0) } }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
            .makeIterator()
        return zip(items, ranked).map { item, rank in rank == nil ? item : named.next() ?? item }
    }
}
