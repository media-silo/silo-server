// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import SmdKit

extension TMDbTree {
    /// A new container beneath one of the tree's, holding nothing yet, named last in its primary sequence
    /// and made with it: entries are added to it as to a group, and its primary sequence goes by the id
    /// of the one's it is beneath.
    @discardableResult
    public mutating func addContainer(
        _ id: ContainerID,
        type: ContainerType,
        typeLabel: String? = nil,
        title: Title,
        beneath parentID: String
    ) -> Bool {
        guard documents[id.value] == nil, var parent = container(parentID) else { return false }
        if parent.sequences.isEmpty { parent.sequences = [Sequence()] }
        var child = Container(id: id, type: type, typeLabel: typeLabel, title: title)
        child.sequences = [Sequence(id: parent.sequences[0].id)]
        let item = ItemID(Slug.unique(from: title.rawValue, avoiding: Set(parent.itemIDs.map(\.value))))!
        parent.sequences[0].items.append(.child(Entry.Child(id: item, container: id)))
        documents[parentID] = Self.text(parent)
        documents[id.value] = Self.text(child)
        edited = .now
        return true
    }
}

extension TMDbWalk {
    /// A new container beneath a stop, holding nothing yet. Beneath a new stop it is a container of the
    /// stop's draft, as one added to a draft is. Beneath a held stop it is a new stop of the walk, its
    /// primary sequence going by the id of the held one's, ticked there as a missing child is: specials
    /// are placed in it and its own children shaped at its stop, and it is made beneath the held one when
    /// the walk is stored, once both are confirmed. Unticked, it leaves the walk once the held stop is
    /// confirmed.
    @discardableResult
    public mutating func addContainer(
        _ id: ContainerID,
        type: ContainerType,
        typeLabel: String? = nil,
        title: Title,
        beneath stop: String
    ) -> Bool {
        if isNew(stop) {
            var added = false
            shape(stop) { added = $0.addContainer(id, type: type, typeLabel: typeLabel, title: title, beneath: stop) }
            return added
        }
        return draftContainer(id, type: type, typeLabel: typeLabel, title: title, beneath: stop)
    }

    /// A new container beneath a held stop, a new stop of the walk drafted holding nothing, and ticked
    /// there.
    private mutating func draftContainer(
        _ id: ContainerID,
        type: ContainerType,
        typeLabel: String? = nil,
        title: Title,
        beneath stop: String
    ) -> Bool {
        guard let comparison = stops[stop]?.comparison, drafts[id.value] == nil, stops[id.value] == nil else {
            return false
        }
        var child = Container(id: id, type: type, typeLabel: typeLabel, title: title)
        child.sequences = [Sequence(id: sequenceName(0, at: stop))]
        let tree = TMDbTree(
            library: library,
            record: TMDb.Record(.series, comparison.series ?? 0),
            creating: ContainerDraft.Creating(parent: stop),
            containers: [child],
            top: id
        )
        drafts[id.value] = tree
        stops[id.value] = Stop(newIn: tree, id.value, parent: stop, offering: offered(id.value, in: tree))
        unconfirm(stop)
        stops[stop]?.chosen.insert(Self.missing(tree))
        stops[stop]?.children.append(id.value)
        return true
    }

    /// The containers added beneath a held stop, in its children's order: each a new stop drafted from
    /// nothing at TMDb, neither a missing season nor a group of its missing episodes.
    public func addedContainers(at stop: String) -> [String] {
        let groups = Set((stops[stop]?.groups ?? []).map(\.id))
        return (stops[stop]?.children ?? []).filter { id in
            guard let tree = drafts[id], tree.creating.parent == stop else { return false }
            return Self.missing(tree) == "group:\(id)" && !groups.contains(id)
        }
    }
}

extension TMDbTree {
    public mutating func declareContainer(
        _ id: ContainerID,
        type: ContainerType,
        title: Title,
        beneath parentID: String
    ) -> Bool {
        guard documents[id.value] == nil, let parent = container(parentID) else { return false }
        var child = Container(id: id, type: type, title: title)
        child.sequences = [Sequence(id: parent.sequences.first?.id)]
        documents[id.value] = Self.text(child)
        edited = .now
        return true
    }

    public mutating func dropContainer(_ id: String) { drop(id) }

    /// The container whose drafted alternatives play a new container, when one does.
    func alternativeParent(of id: String) -> String? {
        draftedAlternatives.keys.sorted().first { key in
            draftedAlternatives[key]?.contains { $0.containers.contains(id) } ?? false
        }
    }

    /// The new containers a container's drafted alternatives play, in the order they first play them.
    func alternativeChildren(of id: String) -> [ContainerID] {
        var seen: Set<String> = []
        return (draftedAlternatives[id] ?? []).flatMap(\.containers).filter { seen.insert($0).inserted }
            .compactMap(ContainerID.init)
    }
}

extension TMDbWalk {
    public mutating func declareContainer(
        _ id: ContainerID,
        type: ContainerType,
        title: Title,
        beneath stop: String
    ) -> Bool {
        if isNew(stop) {
            var declared = false
            shape(stop) { declared = $0.declareContainer(id, type: type, title: title, beneath: stop) }
            return declared
        }
        return draftContainer(id, type: type, title: title, beneath: stop)
    }

    public mutating func dropContainer(_ id: String) {
        if let parent = drafts[id]?.creating.parent {
            remove(id)
            stops[parent]?.chosen.remove("group:\(id)")
            stops[parent]?.children.removeAll { $0 == id }
            unconfirm(parent)
        } else if draft(holding: id) != nil {
            shape(id) { $0.drop(id) }
        }
    }

    /// The new containers storing makes beneath a held stop taking what is given: each drafted for it and
    /// ticked there, its own stop confirmed, by id with its title.
    func containers(madeBeneath stop: String, taking taken: Set<String>) -> [ContainerID: Title] {
        let made = drafts.values.filter { tree in
            tree.creating.parent == stop && stops[tree.top]?.taken != nil && taken.contains(Self.missing(tree))
        }
        return Dictionary(
            made.compactMap { tree in tree.container(tree.top).map { ($0.id, $0.title) } },
            uniquingKeysWith: { first, _ in first }
        )
    }
}
