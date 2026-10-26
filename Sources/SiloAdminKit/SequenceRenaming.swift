// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import SmdKit

extension Container {
    /// One of its sequences under a new id, each alternative naming it renamed with it; false, and
    /// nothing renamed, when the id is no sequence id or another sequence has it.
    @discardableResult
    mutating func renameSequence(_ index: Int, to id: String) -> Bool {
        guard sequences.indices.contains(index), !id.isEmpty, id == Slug.make(from: id),
            !sequences.enumerated().contains(where: { $0.offset != index && $0.element.id == id })
        else { return false }
        let old = sequences[index].id
        sequences[index].id = id
        if let old {
            for alternative in alternatives.indices where alternatives[alternative].sequence == old {
                alternatives[alternative].sequence = id
            }
        }
        return true
    }
}

extension SpecialPlacement {
    /// An entry placed in a container's sequence, the sequence named by its new id once it is renamed.
    func renaming(_ old: String?, to id: String, in container: String) -> SpecialPlacement {
        guard case .entry(let home, let sequence, let position) = self, home == container, sequence == old,
            old != nil
        else { return self }
        return .entry(in: home, sequence: id, position: position)
    }
}

extension TMDbTree {
    /// A container's sequence under a new id, as a sequence id is written: the name given, made one.
    /// The alternatives and the placed specials that name it are renamed with it.
    /// With `beneath`, the primary sequence of each container of the tree beneath it is renamed too,
    /// at any depth, each refused alone when one of its own sequences has the name.
    @discardableResult
    public mutating func renameSequence(_ index: Int, of id: String, to name: String, beneath: Bool = false) -> Bool {
        guard rename(index, of: id, to: name) else { return false }
        guard beneath else { return true }
        var queue = container(id)?.childContainerIDs.map(\.value) ?? []
        var seen: Set<String> = [id]
        while !queue.isEmpty {
            let child = queue.removeFirst()
            guard seen.insert(child).inserted, container(child) != nil else { continue }
            rename(0, of: child, to: name)
            queue += container(child)?.childContainerIDs.map(\.value) ?? []
        }
        return true
    }

    @discardableResult
    private mutating func rename(_ index: Int, of id: String, to name: String) -> Bool {
        guard var container = container(id) else { return false }
        let old = container.sequences.indices.contains(index) ? container.sequences[index].id : nil
        let new = Slug.make(from: name)
        guard container.renameSequence(index, to: new) else { return false }
        set(container)
        placements = placements.mapValues { $0.renaming(old, to: new, in: id) }
        return true
    }
}

extension TMDbWalk {
    /// The id a stop's sequence goes by: as the operator renamed it, or as the container has it.
    public func sequenceName(_ index: Int, at stop: String) -> String? {
        if let renamed = renamedSequences[stop]?[index] { return renamed }
        guard let sequences = container(stop)?.sequences, sequences.indices.contains(index) else { return nil }
        return sequences[index].id
    }

    /// A stop's sequence under a new id, as a sequence id is written: the name given, made one. A new
    /// stop's draft is shaped with it; a held stop's change renames it, and the alternatives naming it,
    /// when the walk is stored. The specials placed in it are renamed with it, and the stop is pending
    /// again.
    /// With `beneath`, the primary sequence of each container beneath it the walk knows is renamed too,
    /// at any depth: each the container or a stop lists beneath it, a held one not yet read renamed when it
    /// is stored, unless one of its own sequences has the name by then.
    @discardableResult
    public mutating func renameSequence(
        _ index: Int,
        at stop: String,
        to name: String,
        beneath: Bool = false
    )
        -> Bool
    {
        guard rename(index, at: stop, to: name) else { return false }
        guard beneath else { return true }
        for child in containers(beneath: stop) { rename(0, at: child, to: name) }
        return true
    }

    /// The containers beneath a stop the walk knows, at any depth, nearest first: those its container
    /// lists, and the stops beneath it.
    public func containers(beneath stop: String) -> [String] {
        func children(_ id: String) -> [String] {
            (container(id)?.childContainerIDs.map(\.value) ?? []) + (stops[id]?.children ?? [])
        }
        var found: [String] = []
        var queue = children(stop)
        while !queue.isEmpty {
            let child = queue.removeFirst()
            guard child != stop, !found.contains(child) else { continue }
            found.append(child)
            queue += children(child)
        }
        return found
    }

    @discardableResult
    private mutating func rename(_ index: Int, at stop: String, to name: String) -> Bool {
        let new = Slug.make(from: name)
        let old = sequenceName(index, at: stop)
        if isNew(stop) {
            var renamed = false
            shape(stop) { renamed = $0.renameSequence(index, of: stop, to: name) }
            guard renamed else { return false }
        } else if container(stop) == nil {
            // Not read yet, it is renamed as its edit is made, if it is.
            guard !new.isEmpty else { return false }
            renamedSequences[stop, default: [:]][index] = new
            unconfirm(stop)
        } else {
            guard var container = container(stop) else { return false }
            for (renamed, id) in renamedSequences[stop] ?? [:] { container.renameSequence(renamed, to: id) }
            guard container.renameSequence(index, to: new) else { return false }
            renamedSequences[stop, default: [:]][index] = new
            unconfirm(stop)
        }
        placements = placements.mapValues { $0.renaming(old, to: new, in: stop) }
        return true
    }
}
