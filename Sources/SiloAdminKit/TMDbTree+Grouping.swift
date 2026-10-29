// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import SmdKit

/// A run of a container's entries that TMDb titles as the parts of one story, as `Terror of the Zygons
/// (1)` to `(4)` are: suggested to be grouped, titled by the story.
public struct SuggestedGroup: Hashable, Sendable {
    public var title: String
    public var items: [ItemID]
    /// The part number TMDb gives each, in the items' order.
    public var parts: [Int]

    public init(title: String, items: [ItemID], parts: [Int]) {
        self.title = title
        self.items = items
        self.parts = parts
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

    /// The container of the tree a container is beneath: the one naming it, or the one whose drafted
    /// alternatives play it.
    public func parent(of id: String) -> String? {
        containers.first { $0.childContainerIDs.contains { $0.value == id } }?.id.value ?? alternativeParent(of: id)
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
        guard let parentID = parent(of: id), let parent = container(parentID) else { return false }
        guard
            let entry = (parent.sequences.flatMap(\.items) + parent.extras).first(where: {
                $0.childContainer?.value == id
            })
        else {
            // Played in its parent's drafted alternatives alone, it is made with them.
            return alternativeParent(of: id) == parentID && isMade(parentID)
        }
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
        storyRuns(in: parentID).filter { !isOwnParts($0, parentID) }
    }

    /// The run of a container's entries TMDb titles as the parts of the story the container is titled
    /// as, or that is every entry it holds, as a serial grouped from `Planet of Evil (1)` to `(4)` holds
    /// them: already grouped, they are suggested to be titled by their part numbers rather than grouped
    /// again.
    public func suggestedRenaming(in parentID: String) -> SuggestedGroup? {
        storyRuns(in: parentID).first { isOwnParts($0, parentID) }
    }

    /// Entries titled by the word given and each one's part number at TMDb, as `Part 1` and on: the
    /// operator's own titles, which TMDb's no longer stand for.
    public mutating func title(_ items: [ItemID], in parentID: String, as word: String) {
        guard var parent = container(parentID) else { return }
        for sequence in parent.sequences.indices {
            for index in parent.sequences[sequence].items.indices {
                guard case .leaf(var leaf) = parent.sequences[sequence].items[index], items.contains(leaf.id),
                    let tmdb = leaf.externalRefs.first(where: { $0.provider == .tmdb }),
                    let number = episodeTitles[tmdb.value].flatMap(Self.part(of:))
                else { continue }
                leaf.title = "\(word) \(number)"
                parent.sequences[sequence].items[index] = .leaf(leaf)
            }
        }
        documents[parentID] = Self.text(parent)
        edited = .now
    }

    private func isOwnParts(_ run: SuggestedGroup, _ parentID: String) -> Bool {
        guard let parent = container(parentID) else { return false }
        return parent.title.rawValue.caseInsensitiveCompare(run.title) == .orderedSame
            || run.items.count == parent.sequences.flatMap(\.items).count
    }

    /// The runs of a container's entries whose TMDb titles name the parts of one story; an entry titled
    /// by the operator ends a run.
    private func storyRuns(in parentID: String) -> [SuggestedGroup] {
        (container(parentID)?.sequences ?? []).flatMap { sequence in
            Self.runs(
                of: sequence.items.compactMap { entry -> (ItemID, String?)? in
                    guard let item = entry.id else { return nil }
                    let tmdb = entry.externalRefs.first { $0.provider == .tmdb }
                    guard entry.childContainer == nil, entry.title == nil else { return (item, nil) }
                    return (item, tmdb.flatMap { episodeTitles[$0.value] })
                }
            )
            .map { SuggestedGroup(title: $0.title, items: $0.ids, parts: $0.parts) }
        }
    }

    /// The runs of two or more titles together that name the parts of one story, each with what it was
    /// told of each and its part number; a nil title ends a run. A part numbered after the last continues
    /// the run though TMDb names its story otherwise, as `Invasion (1)` is followed by `Invasion of the
    /// Dinosaurs (2)`, and the run is titled by the story most of its parts name, the later on a tie.
    static func runs<ID>(of titled: [(ID, String?)]) -> [(title: String, ids: [ID], parts: [Int])] {
        var runs: [(title: String, ids: [ID], parts: [Int])] = []
        var run: (stories: [String], ids: [ID], parts: [Int])?
        func end() {
            if let ended = run, ended.ids.count > 1 {
                let named = ended.stories.enumerated().max { first, second in
                    let counts = (
                        ended.stories.count(where: { $0 == first.element }),
                        ended.stories.count(where: { $0 == second.element })
                    )
                    return counts.0 == counts.1 ? first.offset < second.offset : counts.0 < counts.1
                }
                runs.append((named?.element ?? "", ended.ids, ended.parts))
            }
            run = nil
        }
        for (id, title) in titled {
            guard let (story, number) = title.flatMap(parts(of:)) else {
                end()
                continue
            }
            if let current = run, current.stories.contains(story) || current.parts.last.map({ $0 + 1 }) == number {
                run?.stories.append(story)
                run?.ids.append(id)
                run?.parts.append(number)
            } else {
                end()
                run = ([story], [id], [number])
            }
        }
        end()
        return runs
    }

    /// The story an episode's title names it a part of, as `Terror of the Zygons (1)` names `Terror of the
    /// Zygons`.
    public static func story(of title: String) -> String? {
        parts(of: title)?.story
    }

    /// The part number an episode's title gives it, as `Terror of the Zygons (2)` gives 2.
    public static func part(of title: String) -> Int? {
        parts(of: title)?.number
    }

    private static func parts(of title: String) -> (story: String, number: Int)? {
        guard title.hasSuffix(")"), let open = title.lastIndex(of: "(") else { return nil }
        let number = title[title.index(after: open)..<title.index(before: title.endIndex)]
        let story = title[..<open].trimmingCharacters(in: .whitespaces)
        guard number.allSatisfy({ $0.isASCII && $0.isNumber }), let part = Int(number), !story.isEmpty else {
            return nil
        }
        return (story, part)
    }
}
