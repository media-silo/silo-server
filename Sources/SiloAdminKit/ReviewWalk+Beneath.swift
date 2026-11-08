// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import SmdKit

// MARK: - A stop's episodes a field at a time, and a stop confirmed with everything beneath it

/// A season of twenty-six parts is twenty-six stops: each of its episodes' fields ticked at once in its
/// Episodes group, and the season and everything beneath it confirmed in one action.
/// `Proposals/EpisodeDetails.md`.
extension ReviewWalk {
    /// The fields of an episode an Episodes group ticks: its title, outline, first date, cast, and
    /// directors and writers, by difference id.
    public static let episodeFields = ["title", "outline", "premiered", "cast", "crew"]

    /// A field of a stop's Episodes group: how many of the episodes beneath the stop it would change, and
    /// whether it is ticked at them, at all, none, or some, nil.
    public struct EpisodeField: Hashable, Sendable, Identifiable {
        public var id: String
        public var episodes: Int
        public var ticked: Bool?
    }

    /// The episodes beneath a stop: the episode containers its container holds, and the episode stops
    /// beneath it, in the order its children list them.
    public func episodes(beneath stop: String) -> [String] {
        let held = Set(stops[stop]?.comparison?.episodeContainers?.values.map { $0 } ?? [])
        var found: [String] = []
        for id in (stops[stop]?.children ?? []) + (container(stop)?.childContainerIDs.map(\.value) ?? [])
        where !found.contains(id) {
            let type = stops[id]?.type ?? draft(holding: id)?.container(id)?.type.rawValue
            if type == ContainerType.episode.rawValue || held.contains(id) { found.append(id) }
        }
        return found
    }

    /// A stop's Episodes group: each field offered at an episode beneath it, or that might be, with
    /// how many of them it would change, and how many of the episodes have not been read, so what they
    /// would change is not known yet.
    public func episodeFields(at stop: String) -> (fields: [EpisodeField], unread: Int) {
        let episodes = episodes(beneath: stop)
        let ticking = stops[stop]?.episodeFields ?? [:]
        var unread = 0
        var offered: [String: [Bool]] = [:]
        for episode in episodes {
            let fields = self.fields(of: episode)
            if fields == nil { unread += 1 }
            let chosen =
                stops[episode]?.chosen
                ?? Set((fields ?? []).filter { ticking[$0] != false } + ticking.filter(\.value).keys)
            for field in Self.episodeFields where fields?.contains(field) ?? true {
                offered[field, default: []].append(chosen.contains(field))
            }
        }
        // An episode not read yet counts at every field, and what it would change is not known.
        let fields = Self.episodeFields.compactMap { field -> EpisodeField? in
            guard let ticks = offered[field] else { return nil }
            let ticked: Bool? = ticks.allSatisfy { $0 } ? true : ticks.contains(true) ? nil : false
            return EpisodeField(id: field, episodes: ticks.count - unread, ticked: ticked)
        }
        return (fields, unread)
    }

    /// A field ticked or unticked at each episode beneath a stop that offers it or has not been read, and
    /// at each episode's stop that joins the walk beneath it later. Nothing is confirmed.
    public mutating func choose(episodes field: String, _ chosen: Bool, at stop: String) {
        guard stops[stop] != nil else { return }
        var ticking = stops[stop]?.episodeFields ?? [:]
        ticking[field] = chosen
        stops[stop]?.episodeFields = ticking
        for episode in episodes(beneath: stop) where stops[episode] != nil {
            if fields(of: episode)?.contains(field) ?? true { choose(field, chosen, at: episode) }
        }
    }

    /// Whether Confirm with everything beneath confirmed a stop that the operator has not opened since.
    public func confirmedFromAbove(_ id: String) -> Bool { stops[id]?.fromAbove == true }

    /// The operator has looked at a stop: it is no longer, and is never, one only confirmed from above.
    public mutating func opened(_ id: String) {
        stops[id]?.fromAbove = false
    }

    /// The fields an episode is offered, as its draft has it for a new one and as its reading found it
    /// for a held one; nil when it has not been read.
    private func fields(of episode: String) -> Set<String>? {
        if let tree = draft(holding: episode) { return Set(offered(episode, in: tree).map(\.id)) }
        guard stops[episode]?.comparison != nil else { return nil }
        return Set(differences(of: episode).map(\.id))
    }

    /// An episode's stop joining the walk beneath a stop, ticked with what the stop's Episodes group was.
    static func tick(_ fields: [String: Bool]?, at stop: inout Stop) {
        guard let fields, stop.type == ContainerType.episode.rawValue else { return }
        for (field, chosen) in fields {
            if chosen { stop.chosen.insert(field) } else { stop.chosen.remove(field) }
        }
    }
}

extension AdminConsole {
    /// What Confirm with everything beneath did: the walk, and each stop beneath that could not be read,
    /// left pending, with why.
    public struct ConfirmedBeneath: Sendable {
        public var walk: ReviewWalk
        public var unread: [String: any Error]
    }

    /// Confirms a stop with its ticks, unless it is confirmed already, then reads each stop beneath it the
    /// walk finds, depth first, and confirms each pending one with the ticks it holds: the operator's, at
    /// it or through a group above it, and otherwise the defaults, nothing at a held stop and everything
    /// at a new one. A missing child is drafted only when it is ticked, so the stops confirmed are those
    /// the ticks reach, and no special is placed. Each stop confirmed beneath that the operator has not
    /// opened is marked confirmed from above; one that cannot be read is left pending, with nothing beneath it found, and the rest are
    /// confirmed.
    public func confirm(
        _ id: String,
        withEverythingBeneath walk: ReviewWalk,
        of silo: Silo,
        from database: any ContainerDatabase,
        wikidata: any WikidataSource,
        tmdb: (any TMDbSource)?,
        progress: @escaping @Sendable (String, StepProgress) async -> Void = { _, _ in }
    ) async throws -> ConfirmedBeneath {
        // A stop confirmed with what is ticked there, as Confirm does: the drafts its ticks make, and the
        // stops beneath it, joining the walk.
        func confirm(_ id: String, in walk: inout ReviewWalk) async throws {
            let drafts = try await drafts(confirming: id, in: walk, from: database, wikidata: wikidata, tmdb: tmdb)
            walk.confirm(id, beneath: try await stops(beneath: id, in: walk, of: silo), drafts: drafts)
        }
        var walk = walk
        if walk.stops[id]?.taken == nil { try await confirm(id, in: &walk) }
        var unread: [String: any Error] = [:]
        var queue = walk.stops[id]?.children ?? []
        var seen: Set<String> = [id]
        while !queue.isEmpty {
            try Task.checkCancellation()
            let next = queue.removeFirst()
            guard seen.insert(next).inserted, let stop = walk.stops[next] else { continue }
            if stop.taken == nil {
                do {
                    if stop.comparison == nil, !walk.isNew(next) {
                        await progress(next, StepProgress("Opening the container"))
                        walk.read(
                            try await compare(
                                next,
                                in: walk.library,
                                of: silo,
                                from: database,
                                wikidata: wikidata,
                                tmdb: tmdb,
                                identified: walk.identified,
                                progress: { step, _ in await progress(next, step) }
                            )
                        )
                    }
                    try await confirm(next, in: &walk)
                    if walk.stops[next]?.fromAbove == nil { walk.stops[next]?.fromAbove = true }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    unread[next] = error
                    continue
                }
            }
            queue = (walk.stops[next]?.children ?? []) + queue
        }
        return ConfirmedBeneath(walk: walk, unread: unread)
    }
}
