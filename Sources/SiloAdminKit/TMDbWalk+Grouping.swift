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

    public init(title: String, episodes: [Int]) {
        self.title = title
        self.episodes = episodes
    }
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
}

extension TMDbWalk {
    /// The episodes a held stop's reading offers, in TMDb's order.
    public func missingEpisodes(at stop: String) -> [TMDb.Episode] {
        (stops[stop]?.comparison?.differences ?? []).compactMap { difference in
            if case .episode(let episode, _) = difference { episode } else { nil }
        }
    }

    /// The runs of a held stop's missing episodes, grouped in none of its groups, that TMDb titles as the
    /// parts of one story.
    public func suggestedGroups(at stop: String) -> [SuggestedEpisodes] {
        let grouped = Set((stops[stop]?.groups ?? []).flatMap(\.episodes))
        // A run of the story the stop is titled as is its own parts, not a group to make of them.
        let own = stops[stop]?.title ?? ""
        return TMDbTree.runs(of: missingEpisodes(at: stop).map { ($0.id, grouped.contains($0.id) ? nil : $0.title) })
            .filter { $0.title.caseInsensitiveCompare(own) != .orderedSame }
            .map { SuggestedEpisodes(title: $0.title, episodes: $0.ids) }
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
        leave(episode, at: stop)
        if ticked { stops[stop]?.chosen.insert("episode:\(episode)") }
    }

    /// A group's episodes back among the held stop's missing ones, each ticked as the group was.
    public mutating func ungroup(_ id: String, at stop: String) {
        guard let group = stops[stop]?.groups.first(where: { $0.id == id }) else { return }
        let ticked = stops[stop]?.chosen.contains(group.tick) ?? false
        stops[stop]?.groups.removeAll { $0.id == id }
        stops[stop]?.chosen.remove(group.tick)
        if ticked { stops[stop]?.chosen.formUnion(group.episodes.map { "episode:\($0)" }) }
    }

    /// An episode out of whichever group of the stop holds it, and a group left with none gone.
    private mutating func leave(_ episode: Int, at stop: String) {
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
