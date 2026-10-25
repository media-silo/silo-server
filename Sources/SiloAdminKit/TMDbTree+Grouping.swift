// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import SmdKit

/// A run of a container's entries that TMDb titles as the parts of one story, as `Terror of the Zygons
/// (1)` to `(4)` are: suggested to be grouped, titled by the story.
public struct SuggestedGroup: Hashable, Sendable {
    public var title: String
    public var items: [ItemID]

    public init(title: String, items: [ItemID]) {
        self.title = title
        self.items = items
    }
}

// MARK: - Groups of a draft's entries

/// A draft's entries grouped by the operator into containers beneath the one that holds them, and the
/// groups TMDb's titles suggest. `Tmdb.md`, *A draft from TMDb*.
extension TMDbTree {
    /// The groups made of a container's entries: the containers beneath it the tree holds, in its order.
    public func groups(in parentID: String) -> [Container] {
        (container(parentID)?.childContainerIDs ?? []).compactMap {
            documents[$0.value] == nil ? nil : container($0.value)
        }
    }

    /// The container of the tree a container is beneath.
    public func parent(of id: String) -> String? {
        containers.first { $0.childContainerIDs.contains { $0.value == id } }?.id.value
    }

    /// Entries of a group's container added to the group, its entries then in the container's order and
    /// the group at the first one's place; what else the group was given is kept.
    public mutating func add(_ items: [ItemID], to group: String) {
        guard let held = container(group), let parentID = parent(of: group) else { return }
        let members = Set(held.sequences.flatMap(\.items).compactMap(\.id)).union(items)
        unfold(group, into: parentID)
        let order = container(parentID)?.sequences.flatMap(\.items).compactMap(\.id) ?? []
        regroup(
            order.filter(members.contains),
            in: parentID,
            into: held.id,
            type: held.type,
            typeLabel: held.typeLabel,
            title: held.title
        )
        guard let made = container(group) else { return }
        var kept = held
        kept.sequences = made.sequences
        documents[group] = Self.text(kept)
    }

    /// One entry out of a group, back in the group's container beside it: before it when it was the
    /// group's first, after it otherwise. A group left with nothing is ungrouped.
    public mutating func remove(_ item: ItemID, from group: String) {
        guard var held = container(group), let parentID = parent(of: group), var parent = container(parentID)
        else { return }
        let members = held.sequences.flatMap(\.items)
        guard let entry = members.first(where: { $0.id == item }) else { return }
        guard members.count > 1 else { return ungroup(group) }
        for index in held.sequences.indices { held.sequences[index].items.removeAll { $0.id == item } }
        for index in parent.sequences.indices {
            guard let at = parent.sequences[index].items.firstIndex(where: { $0.childContainer?.value == group })
            else { continue }
            parent.sequences[index].items.insert(entry, at: members.first == entry ? at : at + 1)
        }
        documents[group] = Self.text(held)
        documents[parentID] = Self.text(parent)
        edited = .now
    }

    /// A group's entries back in its container at its place, and the group gone; the specials placed in
    /// it are unassigned again.
    public mutating func ungroup(_ group: String) {
        guard let parentID = parent(of: group), group != top else { return }
        unfold(group, into: parentID)
        for (special, placement) in placements where placement.container == group { placements[special] = nil }
    }

    // MARK: Entries left out

    /// Whether an entry of a container is unticked, to be left out when the tree is made.
    public func isLeftOut(_ item: ItemID, in container: String) -> Bool {
        leftOutEntries?[container]?.contains(item.value) ?? false
    }

    /// An entry of a container ticked to be made with it, or unticked to be left out, a group with
    /// everything in it.
    public mutating func include(_ item: ItemID, in container: String, _ included: Bool) {
        var left = leftOutEntries ?? [:]
        var entries = left[container] ?? []
        entries.removeAll { $0 == item.value }
        if !included { entries.append(item.value) }
        left[container] = entries.isEmpty ? nil : entries
        leftOutEntries = left.isEmpty ? nil : left
        edited = .now
    }

    /// Whether a container of the tree is made with it: the top, and each container whose entry in the
    /// one holding it is ticked, all the way up.
    public func isMade(_ id: String) -> Bool {
        if id == top { return documents[id] != nil }
        guard let parentID = parent(of: id), let parent = container(parentID),
            let entry = (parent.sequences.flatMap(\.items) + parent.extras).first(where: {
                $0.childContainer?.value == id
            })
        else { return false }
        return !(entry.id.map { isLeftOut($0, in: parentID) } ?? false) && isMade(parentID)
    }

    /// A container as it is made, the entries left out of it gone.
    func leavingOut(_ container: Container) -> Container {
        guard let left = leftOutEntries?[container.id.value], !left.isEmpty else { return container }
        var kept = container
        for index in kept.sequences.indices {
            kept.sequences[index].items.removeAll { $0.id.map { left.contains($0.value) } ?? false }
        }
        kept.extras.removeAll { $0.id.map { left.contains($0.value) } ?? false }
        return kept
    }

    private mutating func unfold(_ group: String, into parentID: String) {
        guard let held = container(group), var parent = container(parentID) else { return }
        let members = held.sequences.flatMap(\.items) + held.extras
        for index in parent.sequences.indices {
            guard let at = parent.sequences[index].items.firstIndex(where: { $0.childContainer?.value == group })
            else { continue }
            parent.sequences[index].items.replaceSubrange(at...at, with: members)
        }
        parent.extras.removeAll { $0.childContainer?.value == group }
        documents[group] = nil
        attributions[group] = nil
        leftOutEntries?[group] = nil
        documents[parentID] = Self.text(parent)
        edited = .now
    }

    /// The runs of a container's entries TMDb titles as the parts of one story, `Title (1)`, `Title (2)`
    /// and on, two or more running together in one sequence.
    public func suggestedGroups(in parentID: String) -> [SuggestedGroup] {
        (container(parentID)?.sequences ?? []).flatMap { sequence in
            Self.runs(
                of: sequence.items.compactMap { entry -> (ItemID, String?)? in
                    guard let item = entry.id else { return nil }
                    let tmdb = entry.externalRefs.first { $0.provider == .tmdb }
                    return (item, entry.childContainer == nil ? tmdb.flatMap { episodeTitles[$0.value] } : nil)
                }
            )
            .map { SuggestedGroup(title: $0.title, items: $0.ids) }
        }
    }

    /// The runs of two or more titles together that name the parts of one story, each with what it was
    /// told of each; a nil title ends a run.
    static func runs<ID>(of titled: [(ID, String?)]) -> [(title: String, ids: [ID])] {
        var runs: [(title: String, ids: [ID])] = []
        var run: (title: String, ids: [ID])?
        func end() {
            if let ended = run, ended.ids.count > 1 { runs.append(ended) }
            run = nil
        }
        for (id, title) in titled {
            guard let story = title.flatMap(story(of:)) else {
                end()
                continue
            }
            if run?.title == story {
                run?.ids.append(id)
            } else {
                end()
                run = (story, [id])
            }
        }
        end()
        return runs
    }

    /// The story an episode's title names it a part of, as `Terror of the Zygons (1)` names `Terror of the
    /// Zygons`.
    public static func story(of title: String) -> String? {
        guard title.hasSuffix(")"), let open = title.lastIndex(of: "(") else { return nil }
        let number = title[title.index(after: open)..<title.index(before: title.endIndex)]
        let story = title[..<open].trimmingCharacters(in: .whitespaces)
        guard !number.isEmpty, number.allSatisfy(\.isNumber), !story.isEmpty else { return nil }
        return story
    }
}
