// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import SmdKit

/// Episodes Wikidata has and a held container lacks, grouped by the operator into a new container beneath
/// it: made with them when the walk is stored, if its tick is taken, in place of adding them one by one.
public struct EpisodeGroup: Hashable, Sendable, Codable, Identifiable {
    /// The new container's id, given out by the silo.
    public var id: String
    public var title: Title
    public var type: ContainerType
    public var typeLabel: String?
    /// Wikidata's ids of its episodes, in Wikidata's order.
    public var episodes: [String]

    public init(id: String, title: Title, type: ContainerType, typeLabel: String? = nil, episodes: [String]) {
        self.id = id
        self.title = title
        self.type = type
        self.typeLabel = typeLabel
        self.episodes = episodes
    }

    /// The tick that takes the group.
    public var tick: String { "group:\(id)" }
}

/// A run of episodes a held container lacks that Wikidata titles as the parts of one story: suggested to be
/// grouped, titled by the story.
public struct SuggestedEpisodes: Hashable, Sendable {
    public var title: String
    public var episodes: [String]
    /// The part number its title gives each, in the episodes' order.
    public var parts: [Int]

    public init(title: String, episodes: [String], parts: [Int]) {
        self.title = title
        self.episodes = episodes
        self.parts = parts
    }
}

/// One of a held stop's children besides its seasons, as its children list them.
public enum HeldStopChild: Hashable, Sendable {
    /// A missing episode grouped in none, and put into no container held beneath, with the new stop
    /// drafted for it once it is.
    case episode(Wikidata.Work, drafted: String?)
    case group(EpisodeGroup)
    /// A container held beneath, holding the missing episodes put into it.
    case held(ReviewWalk.HeldChild)
    /// What the stop holds already, or a special placed there, in its place in the stop's sequence: only
    /// to be moved.
    case entry(StopEntry)
    /// A container the operator added beneath it, by its id: a new stop of the walk, shaped there.
    case added(String)
    /// One of the children its reading lists, a series' season or a season's serial: held beneath it,
    /// or missing, ticked to be drafted.
    case child(ReviewWalk.Difference)
}

// MARK: - Grouping a held stop's missing episodes

/// The missing episodes of a held stop grouped into new containers beneath it, and the groups their
/// titles suggest. `TmdbWalk.md`, *A new stop*.
extension ReviewWalk.Stop {
    /// Absent from a walk kept before groups were asked.
    public var groups: [EpisodeGroup] {
        get { episodeGroups ?? [] }
        set { episodeGroups = newValue.isEmpty ? nil : newValue }
    }

    /// Absent from a walk kept before missing episodes could be added to a held container.
    public var intoHeld: [String: [String]] {
        get { episodesIntoHeld ?? [:] }
        set { episodesIntoHeld = newValue.isEmpty ? nil : newValue }
    }
}

extension ReviewWalk {
    /// The episodes a held stop's reading offers, in Wikidata's order, and those its parent handed to it.
    public func missingEpisodes(at stop: String) -> [Wikidata.Work] {
        episodeDifferences(at: stop).compactMap { difference in
            if case .episode(let episode, _) = difference { episode } else { nil }
        }
    }

    /// The missing episodes a held stop's parent handed to it, as the parent offers them: the stop's own
    /// to tick, group and take, as though its reading had offered them, and offered by the parent no
    /// longer.
    public func handed(to stop: String) -> [Difference] {
        guard let parent = stops[stop]?.parent, let handed = stops[parent]?.intoHeld[stop] else { return [] }
        return episodeDifferences(at: parent).filter { difference in
            if case .episode(let episode, _) = difference { handed.contains(episode.id) } else { false }
        }
    }

    private func episodeDifferences(at stop: String) -> [Difference] {
        (stops[stop]?.comparison?.differences ?? []).filter { difference in
            if case .episode = difference { true } else { false }
        } + handed(to: stop)
    }

    /// The runs of a held stop's missing episodes, grouped in none of its groups, that their titles say are the
    /// parts of one story.
    public func suggestedGroups(at stop: String) -> [SuggestedEpisodes] {
        // A run of the story the stop is titled as is its own parts, not a group to make of them.
        storyRuns(at: stop).filter { !isOwn($0, at: stop) }
    }

    /// The run of a held stop's missing episodes that are its own story's parts, to be titled by their
    /// part numbers rather than grouped, as a draft's own parts are.
    public func suggestedRenaming(at stop: String) -> SuggestedEpisodes? {
        storyRuns(at: stop).first { isOwn($0, at: stop) }
    }

    /// Missing episodes of a held stop titled by the word given and the part number each one's title
    /// gives, as `Part 3`: the titles the containers the walk drafts for them carry, those drafted already
    /// retitled.
    public mutating func title(_ episodes: [String], at stop: String, as word: String) {
        unconfirm(stop)
        for episode in missingEpisodes(at: stop) where episodes.contains(episode.id) {
            guard let number = DraftTree.part(of: episode.title) else { continue }
            titles[episode.id] = "\(word) \(number)"
            // Drafted already, alone or in a group made here, its container is titled so.
            for tree in drafts.values where tree.creating.parent == stop {
                for var container in tree.containers
                where container.type == .episode && container.externalRefs.contains(episode.item) {
                    guard let title = Title(titles[episode.id] ?? episode.title), container.title != title else {
                        continue
                    }
                    container.title = title
                    shape(container.id.value) { $0.set(container) }
                }
            }
        }
    }

    /// An episode as the walk shows it and adds it: the operator's own title, or Wikidata's.
    public func title(of episode: Wikidata.Work) -> String { titles[episode.id] ?? episode.title }

    /// The runs of a held stop's missing episodes, grouped in none and titled by none of the operator's
    /// own, that their titles say are the parts of one story.
    private func storyRuns(at stop: String) -> [SuggestedEpisodes] {
        let grouped = Set((stops[stop]?.groups ?? []).flatMap(\.episodes))
            .union((stops[stop]?.intoHeld ?? [:]).values.joined())
        let runs = DraftTree.runs(
            of: missingEpisodes(at: stop).map {
                ($0.id, grouped.contains($0.id) || titles[$0.id] != nil ? nil : $0.title)
            }
        )
        return runs.map { SuggestedEpisodes(title: $0.title, episodes: $0.ids, parts: $0.parts) }
    }

    private func isOwn(_ run: SuggestedEpisodes, at stop: String) -> Bool {
        run.title.caseInsensitiveCompare(stops[stop]?.title ?? "") == .orderedSame
    }

    /// Missing episodes of a held stop made a new group beneath it, taken in place of its episodes, and
    /// ticked, since it was selected to be made: each leaves any group it was in.
    public mutating func group(
        _ episodes: [String],
        at stop: String,
        into id: String,
        type: ContainerType,
        typeLabel: String? = nil,
        title: Title
    ) {
        guard stops[stop] != nil, !episodes.isEmpty else { return }
        unconfirm(stop)
        for episode in episodes { leave(episode, at: stop) }
        let group = EpisodeGroup(
            id: id,
            title: title,
            type: type,
            typeLabel: typeLabel,
            episodes: inOrder(Set(episodes), at: stop)
        )
        stops[stop]?.groups.append(group)
        stops[stop]?.chosen.subtract(episodes.map { "episode:\($0)" })
        stops[stop]?.chosen.insert(group.tick)
    }

    /// Missing episodes of a held stop added to a group made there, in Wikidata's order among its own.
    public mutating func add(_ episodes: [String], toGroup id: String, at stop: String) {
        guard let index = stops[stop]?.groups.firstIndex(where: { $0.id == id }) else { return }
        unconfirm(stop)
        let members = stops[stop]?.groups[index].episodes ?? []
        for episode in episodes where !members.contains(episode) { leave(episode, at: stop) }
        guard let index = stops[stop]?.groups.firstIndex(where: { $0.id == id }) else { return }
        let ordered = inOrder(Set(members).union(episodes), at: stop)
        stops[stop]?.groups[index].episodes = ordered
        stops[stop]?.chosen.subtract(episodes.map { "episode:\($0)" })
    }

    /// One episode out of a group, ticked again as the group was; a group left with none is ungrouped.
    public mutating func remove(_ episode: String, fromGroup id: String, at stop: String) {
        guard let group = stops[stop]?.groups.first(where: { $0.id == id }), group.episodes.contains(episode) else {
            return
        }
        let ticked = stops[stop]?.chosen.contains(group.tick) ?? false
        unconfirm(stop)
        leave(episode, at: stop)
        if ticked { stops[stop]?.chosen.insert("episode:\(episode)") }
    }

    /// A group's episodes back among the held stop's missing ones, each ticked as the group was.
    public mutating func ungroup(_ id: String, at stop: String) {
        guard let group = stops[stop]?.groups.first(where: { $0.id == id }) else { return }
        let ticked = stops[stop]?.chosen.contains(group.tick) ?? false
        unconfirm(stop)
        stops[stop]?.groups.removeAll { $0.id == id }
        stops[stop]?.chosen.remove(group.tick)
        if ticked { stops[stop]?.chosen.formUnion(group.episodes.map { "episode:\($0)" }) }
    }

    /// A held stop's missing episodes as its children list them, in Wikidata's order: each group at its
    /// first episode's place, each container held beneath at the place of the first of the episodes read
    /// it holds, or last when it holds none, and an episode put into one shown in it rather than here.
    public func children(at stop: String) -> [HeldStopChild] {
        let groups = stops[stop]?.groups ?? []
        let handed = Set((stops[stop]?.intoHeld ?? [:]).values.joined())
        var waiting = heldChildren(at: stop).enumerated().sorted {
            ($0.element.position ?? .max, $0.offset) < ($1.element.position ?? .max, $1.offset)
        }
        .map(\.element)
        let order = stops[stop]?.comparison?.episodeOrder ?? []
        var children: [HeldStopChild] = []
        for episode in missingEpisodes(at: stop) {
            let position = order.firstIndex(of: episode.id).map { $0 + 1 } ?? .max
            while let next = waiting.first, (next.position ?? .max) < position {
                children.append(.held(next))
                waiting.removeFirst()
            }
            if handed.contains(episode.id) { continue }
            if let group = groups.first(where: { $0.episodes.contains(episode.id) }) {
                if group.episodes.first == episode.id { children.append(.group(group)) }
                continue
            }
            children.append(.episode(episode, drafted: drafted(episode: episode.id, at: stop)))
        }
        return children + waiting.map(HeldStopChild.held)
    }

    /// The stops beneath a held stop in the order its children list them, once the operator has moved
    /// them; until then its seasons as its reading lists them, held or drafted, then the containers held
    /// beneath it and the groups of its missing episodes, each at its place.
    public func listed(beneath stop: String) -> [String] {
        let seasons =
            arrangedEntries[stop] != nil
            ? []
            : differences(of: stop).compactMap { difference -> String? in
                switch difference {
                case .heldChild(_, let container, _): container
                case .child(let child): drafted(child.id, at: stop)
                default: nil
                }
            }
        let others = sequence(at: stop).compactMap { container(of: $0, at: stop) }
        var seen: Set<String> = []
        return (seasons + others).filter { seen.insert($0).inserted }
    }

    /// The stop beneath a held stop one of its children is, when it is one: a season held or drafted,
    /// a container held beneath, a group or a container added, or a child container it holds.
    private func container(of child: HeldStopChild, at stop: String) -> String? {
        switch child {
        case .group(let group): group.id
        case .held(let held): held.id
        case .added(let id): id
        case .entry(let entry): entry.id.hasPrefix("child:") ? String(entry.id.dropFirst("child:".count)) : nil
        case .episode(_, let drafted): drafted
        case .child(.heldChild(_, let container, _)): container
        case .child(.child(let child)): drafted(child.id, at: stop)
        case .child: nil
        }
    }

    /// The stop drafted beneath a held stop for one of the children Wikidata lists, once it is.
    func drafted(_ child: String, at stop: String) -> String? {
        drafts.values.first { $0.creating.parent == stop && Self.missing($0) == "child:\(child)" }?.top
    }

    /// The stop drafted beneath a held stop for one of its missing episodes, once it is.
    public func drafted(episode: String, at stop: String) -> String? {
        drafts.values.first { $0.creating.parent == stop && Self.missing($0) == "episode:\(episode)" }?.top
    }

    /// The containers a held stop holds beneath it, as its reading found them, or, for a reading kept
    /// before they were read, the held stops the walk found beneath it, placed by none of the episodes.
    public func heldChildren(at stop: String) -> [HeldChild] {
        guard let comparison = stops[stop]?.comparison else { return [] }
        if let held = comparison.heldChildren { return held }
        return (stops[stop]?.children ?? []).filter { !isNew($0) }.compactMap { id in
            stops[id].flatMap { child in
                ContainerType(rawValue: child.type).map { HeldChild(id: id, title: child.title, type: $0) }
            }
        }
    }

    /// Missing episodes of a held stop handed to a container it holds beneath it, in Wikidata's order after
    /// any handed already: that container's own missing episodes from then on, ticked at its stop, and
    /// none of the held stop's. Each leaves any group, or other container, it was in.
    public mutating func add(_ episodes: [String], toHeld child: String, at stop: String) {
        guard heldChildren(at: stop).contains(where: { $0.id == child }), !episodes.isEmpty else { return }
        unconfirm(stop)
        unconfirm(child)
        let members = stops[stop]?.intoHeld[child] ?? []
        for episode in episodes where !members.contains(episode) { leave(episode, at: stop) }
        let ordered = inOrder(Set(members).union(episodes), at: stop)
        stops[stop]?.intoHeld[child] = ordered
        stops[stop]?.chosen.subtract(episodes.map { "episode:\($0)" })
        stops[child]?.chosen.formUnion(episodes.map { "episode:\($0)" })
    }

    /// One episode out of the held container it was handed to, back among the stop's missing ones and
    /// ticked, as it was there to begin with.
    public mutating func remove(_ episode: String, fromHeld child: String, at stop: String) {
        guard stops[stop]?.intoHeld[child]?.contains(episode) == true else { return }
        unconfirm(stop)
        leave(episode, at: stop)
        stops[stop]?.chosen.insert("episode:\(episode)")
    }

    /// An episode out of whichever group of the stop, or held container, holds it, and a group left with
    /// none gone; out of a held container, it is no longer ticked or grouped there either.
    private mutating func leave(_ episode: String, at stop: String) {
        if let intoHeld = stops[stop]?.intoHeld {
            for (child, handed) in intoHeld where handed.contains(episode) {
                leave(episode, at: child)
                stops[child]?.chosen.remove("episode:\(episode)")
                unconfirm(child)
            }
            stops[stop]?.intoHeld = intoHeld.mapValues { $0.filter { $0 != episode } }.filter { !$0.value.isEmpty }
        }
        guard var groups = stops[stop]?.groups else { return }
        for index in groups.indices { groups[index].episodes.removeAll { $0 == episode } }
        for emptied in groups where emptied.episodes.isEmpty { stops[stop]?.chosen.remove(emptied.tick) }
        stops[stop]?.groups = groups.filter { !$0.episodes.isEmpty }
    }

    private func inOrder(_ episodes: Set<String>, at stop: String) -> [String] {
        let order = missingEpisodes(at: stop).map(\.id)
        return order.filter(episodes.contains) + episodes.subtracting(order).sorted()
    }

    // MARK: Specials suggested here

    /// Whether an unassigned special is suggested for a stop on something that ties it there: smddb
    /// filing it there, or its title naming the stop, or an entry or a container beneath it, as `The
    /// Making of Pyramids of Mars` names the serial. A series' own title, which every special of it may
    /// carry, ties nothing.
    public func isSuggested(_ special: Special, here stop: String) -> Bool {
        guard let suggestion = suggestions[special.id], suggestion.placement.flatMap(home) == stop else {
            return false
        }
        if suggestion.basis == .smddb { return true }
        let title = special.episode.title
        return names(of: stop).contains {
            title.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// What a special's title may name a stop by: its own title, unless it is the series, the titles of
    /// its entries and of the stories their titles say they are parts of, and the titles of the containers beneath
    /// it.
    private func names(of stop: String) -> Set<String> {
        var names: Set<String> = []
        if stop != series, let title = stops[stop]?.title { names.insert(title) }
        let titles = stops[stop]?.comparison?.episodeTitles ?? draft(holding: stop)?.episodeTitles ?? [:]
        for entry in container(stop)?.sequences.flatMap(\.items) ?? [] {
            if let child = entry.childContainer {
                if let title = stops[child.value]?.title ?? container(child.value)?.displayTitle { names.insert(title) }
                continue
            }
            if let title = entry.title { names.insert(title) }
            for ref in entry.externalRefs where ref.provider == .wikidata {
                guard let title = titles[ref.value] else { continue }
                names.insert(DraftTree.story(of: title) ?? title)
            }
        }
        return names.filter { $0.count > 2 }
    }
}
