// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import SmdKit

extension TMDbTree {
    /// A special dropped among a container's children: placed in its primary sequence before the entry
    /// whose item id is given, or last with none.
    public mutating func place(_ special: Int, in parent: String, before target: String?) {
        place(special, .entry(in: parent, position: Self.position(before: target, in: container(parent))))
    }

    /// Where in a container's primary sequence an entry goes to be before the one given, or nil for last.
    static func position(before target: String?, in container: Container?) -> Int? {
        guard let target else { return nil }
        return container?.sequences.first?.items.firstIndex { $0.id?.value == target }
    }
}

extension TMDbWalk {
    /// A special dropped among a stop's children, before the child whose key is given or last with none:
    /// in a new stop placed in its draft's primary sequence there, and in a held stop placed in its
    /// primary sequence and moved before the child, as the operator would move it after placing it.
    public mutating func place(_ special: Int, at stop: String, before target: String?) {
        guard !isNew(stop) else {
            place(special, .entry(in: stop, position: TMDbTree.position(before: target, in: container(stop))))
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
