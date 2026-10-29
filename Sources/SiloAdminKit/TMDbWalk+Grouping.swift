// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import SmdKit

/// Episodes TMDb has and a held container lacks, grouped by the operator into a new container beneath
/// it: made with them when the walk is stored, if its tick is taken, in place of adding them one by one.
public struct EpisodeGroup: Hashable, Sendable, Codable, Identifiable {
    /// The new container's id, given out by the silo.
    public var id: String
    public var title: Title
    public var type: ContainerType
    public var typeLabel: String?
    /// TMDb's ids of its episodes, in TMDb's order.
    public var episodes: [Int]

    public init(id: String, title: Title, type: ContainerType, typeLabel: String? = nil, episodes: [Int]) {
        self.id = id
        self.title = title
        self.type = type
        self.typeLabel = typeLabel
        self.episodes = episodes
    }

    /// The tick that takes the group.
    public var tick: String { "group:\(id)" }
}

/// A run of episodes a held container lacks that TMDb titles as the parts of one story: suggested to be
/// grouped, titled by the story.
public struct SuggestedEpisodes: Hashable, Sendable {
    public var title: String
    public var episodes: [Int]
    /// The part number TMDb gives each, in the episodes' order.
    public var parts: [Int]

    public init(title: String, episodes: [Int], parts: [Int]) {
        self.title = title
        self.episodes = episodes
        self.parts = parts
    }
}

/// One of a held stop's children besides its seasons, as its children list them.
public enum HeldStopChild: Hashable, Sendable {
    /// A missing episode grouped in none, and put into no container held beneath.
    case episode(TMDb.Episode)
    case group(EpisodeGroup)
    /// A container held beneath, holding the missing episodes put into it.
    case held(AdminConsole.HeldChild)
    /// What the stop holds already, or a special placed there, in its place in the stop's sequence: only
    /// to be moved.
    case entry(StopEntry)
    /// A container the operator added beneath it, by its id: a new stop of the walk, shaped there.
    case added(String)
    /// One of a series' seasons, as its reading lists it: held beneath it, or missing, ticked to be
    /// drafted.
    case season(AdminConsole.TMDbDifference)
}

// MARK: - Grouping a held stop's missing episodes

/// The missing episodes of a held stop grouped into new containers beneath it, and the groups TMDb's
/// titles suggest. `TmdbWalk.md`, *A new stop*.
extension TMDbWalk.Stop {
    /// Absent from a walk kept before groups were asked.
    public var groups: [EpisodeGroup] {
        get { episodeGroups ?? [] }
        set { episodeGroups = newValue.isEmpty ? nil : newValue }
    }

    /// Absent from a walk kept before missing episodes could be added to a held container.
    public var intoHeld: [String: [Int]] {
        get { episodesIntoHeld ?? [:] }
        set { episodesIntoHeld = newValue.isEmpty ? nil : newValue }
    }
}

extension TMDbWalk {
    /// The episodes a held stop's reading offers, in TMDb's order, and those its parent handed to it.
    public func missingEpisodes(at stop: String) -> [TMDb.Episode] {
        episodeDifferences(at: stop).compactMap { difference in
            if case .episode(let episode, _) = difference { episode } else { nil }
        }
    }

    /// The missing episodes a held stop's parent handed to it, as the parent offers them: the stop's own
    /// to tick, group and take, as though its reading had offered them, and offered by the parent no
    /// longer.
    public func handed(to stop: String) -> [AdminConsole.TMDbDifference] {
        guard let parent = stops[stop]?.parent, let handed = stops[parent]?.intoHeld[stop] else { return [] }
        return episodeDifferences(at: parent).filter { difference in
            if case .episode(let episode, _) = difference { handed.contains(episode.id) } else { false }
        }
    }

    private func episodeDifferences(at stop: String) -> [AdminConsole.TMDbDifference] {
        (stops[stop]?.comparison?.differences ?? []).filter { difference in
            if case .episode = difference { true } else { false }
        } + handed(to: stop)
    }

    /// The runs of a held stop's missing episodes, grouped in none of its groups, that TMDb titles as the
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

    /// Missing episodes of a held stop titled by the word given and each one's part number at TMDb, as
    /// `Part 3`: the titles the entries the walk adds for them carry.
    public mutating func title(_ episodes: [Int], at stop: String, as word: String) {
        unconfirm(stop)
        for episode in missingEpisodes(at: stop) where episodes.contains(episode.id) {
            guard let number = TMDbTree.part(of: episode.title) else { continue }
            titles[episode.id] = "\(word) \(number)"
        }
    }

    /// An episode as the walk shows it and adds it: the operator's own title, or TMDb's.
    public func title(of episode: TMDb.Episode) -> String { titles[episode.id] ?? episode.title }

    /// The runs of a held stop's missing episodes, grouped in none and titled by none of the operator's
    /// own, that TMDb titles as the parts of one story.
    private func storyRuns(at stop: String) -> [SuggestedEpisodes] {
        let grouped = Set((stops[stop]?.groups ?? []).flatMap(\.episodes))
            .union((stops[stop]?.intoHeld ?? [:]).values.joined())
        let runs = TMDbTree.runs(
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
        _ episodes: [Int],
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

    /// Missing episodes of a held stop added to a group made there, in TMDb's order among its own.
    public mutating func add(_ episodes: [Int], toGroup id: String, at stop: String) {
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
    public mutating func remove(_ episode: Int, fromGroup id: String, at stop: String) {
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

    /// Each group a confirmed held stop takes, drafted as a new stop beneath it, as a draft's groups are
    /// new stops: its specials placed and its parts shaped there, made from the draft once its own stop
    /// is confirmed. A group whose episodes have changed since it was drafted is drafted again.
    mutating func draftGroups(of stop: Stop) {
        guard !isNew(stop.id), let taken = stop.taken, let comparison = stop.comparison else { return }
        let missing = missingEpisodes(at: stop.id)
        for group in stop.groups where taken.contains(group.tick) {
            let episodes = group.episodes.compactMap { id in missing.first { $0.id == id } }
            let titles = Dictionary(episodes.map { (String($0.id), $0.title) }, uniquingKeysWith: { first, _ in first })
            if let drafted = drafts[group.id] {
                guard Set(drafted.episodeTitles.keys) != Set(titles.keys) else { continue }
                remove(group.id)
            }
            guard let id = ContainerID(group.id), !episodes.isEmpty else { continue }
            var child = Container(id: id, type: group.type, title: group.title)
            child.typeLabel = group.typeLabel
            // Its primary sequence goes by the id of the stop's it was made out of.
            child.sequences = [Sequence(id: sequenceName(0, at: stop.id), items: [])]
            for episode in episodes {
                TMDbTree.insert(
                    AdminConsole.leaf(episode, in: child, title: self.titles[episode.id]),
                    into: &child,
                    sequence: nil,
                    at: nil
                )
            }
            let tree = TMDbTree(
                library: library,
                record: TMDb.Record(.series, comparison.series ?? 0),
                creating: ContainerDraft.Creating(parent: stop.id),
                containers: [child],
                top: id,
                episodeTitles: titles,
                runtimes: comparison.runtimes.filter { titles[$0.key] != nil }
            )
            drafts[group.id] = tree
            stops[group.id] = Stop(newIn: tree, group.id, parent: stop.id, offering: offered(group.id, in: tree))
        }
    }

    /// A held stop's missing episodes as its children list them, in TMDb's order: each group at its first
    /// episode's place, each container held beneath at the place of the first of TMDb's episodes it
    /// holds, or last when it holds none, and an episode put into one shown in it rather than here.
    public func children(at stop: String) -> [HeldStopChild] {
        let groups = stops[stop]?.groups ?? []
        let handed = Set((stops[stop]?.intoHeld ?? [:]).values.joined())
        var waiting = heldChildren(at: stop).enumerated().sorted {
            ($0.element.number ?? .max, $0.offset) < ($1.element.number ?? .max, $1.offset)
        }
        .map(\.element)
        var children: [HeldStopChild] = []
        for episode in missingEpisodes(at: stop) {
            while let next = waiting.first, (next.number ?? .max) < episode.number {
                children.append(.held(next))
                waiting.removeFirst()
            }
            if handed.contains(episode.id) { continue }
            if let group = groups.first(where: { $0.episodes.contains(episode.id) }) {
                if group.episodes.first == episode.id { children.append(.group(group)) }
                continue
            }
            children.append(.episode(episode))
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
                case .heldSeason(_, let container, _): container
                case .season(let season): drafted(season.id, at: stop)
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
        case .episode: nil
        case .season(.heldSeason(_, let container, _)): container
        case .season(.season(let season)): drafted(season.id, at: stop)
        case .season: nil
        }
    }

    /// The stop drafted beneath a series for one of TMDb's seasons, once it is.
    func drafted(_ season: Int, at stop: String) -> String? {
        drafts.values.first { $0.creating.parent == stop && Self.missing($0) == "season:\(season)" }?.top
    }

    /// The containers a held stop holds beneath it, as its reading found them, or, for a reading kept
    /// before they were read, the held stops the walk found beneath it, placed by none of TMDb's episodes.
    public func heldChildren(at stop: String) -> [AdminConsole.HeldChild] {
        guard let comparison = stops[stop]?.comparison else { return [] }
        if let held = comparison.heldChildren { return held }
        return (stops[stop]?.children ?? []).filter { !isNew($0) }.compactMap { id in
            stops[id].flatMap { child in
                ContainerType(rawValue: child.type).map { AdminConsole.HeldChild(id: id, title: child.title, type: $0) }
            }
        }
    }

    /// Missing episodes of a held stop handed to a container it holds beneath it, in TMDb's order after
    /// any handed already: that container's own missing episodes from then on, ticked at its stop, and
    /// none of the held stop's. Each leaves any group, or other container, it was in.
    public mutating func add(_ episodes: [Int], toHeld child: String, at stop: String) {
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
    public mutating func remove(_ episode: Int, fromHeld child: String, at stop: String) {
        guard stops[stop]?.intoHeld[child]?.contains(episode) == true else { return }
        unconfirm(stop)
        leave(episode, at: stop)
        stops[stop]?.chosen.insert("episode:\(episode)")
    }

    /// An episode out of whichever group of the stop, or held container, holds it, and a group left with
    /// none gone; out of a held container, it is no longer ticked or grouped there either.
    private mutating func leave(_ episode: Int, at stop: String) {
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

    private func inOrder(_ episodes: Set<Int>, at stop: String) -> [Int] {
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
    /// its entries and of the stories TMDb titles them parts of, and the titles of the containers beneath
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
            for ref in entry.externalRefs where ref.provider == .tmdb {
                guard let title = titles[ref.value] else { continue }
                names.insert(TMDbTree.story(of: title) ?? title)
            }
        }
        return names.filter { $0.count > 2 }
    }
}
