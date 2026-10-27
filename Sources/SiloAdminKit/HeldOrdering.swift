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
    /// A held stop's primary sequence as storing would leave it, were the stop confirmed with what is
    /// chosen and placed there now, in the order the operator gave it.
    public func storedEntries(at stop: String) -> [StopEntry] {
        guard !isNew(stop), let (before, after) = stored(stop), let sequence = after.sequences.first else {
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

    /// One of a held stop's entries, by its key, moved before another, or last with none: the order is
    /// kept with the walk, and the stop's edit puts its primary sequence in it. An entry the order does
    /// not name, as a special placed after the order was given, keeps its place.
    @discardableResult
    public mutating func arrange(_ key: String, at stop: String, before target: String?) -> Bool {
        let order = storedEntries(at: stop).map(\.id)
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
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let ranked = items.map { entry in key(of: entry, held: held).flatMap { rank[$0] } }
        var named = zip(items, ranked).compactMap { entry, rank in rank.map { (entry, $0) } }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
            .makeIterator()
        return zip(items, ranked).map { entry, rank in rank == nil ? entry : named.next() ?? entry }
    }
}
