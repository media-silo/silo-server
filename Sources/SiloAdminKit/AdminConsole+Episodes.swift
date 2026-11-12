// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import SmdKit

// MARK: - Episodes as containers

extension ReviewWalk {
    /// Someone credited for a work as a difference offers them: who, the character they play or the job
    /// they did, and the ids providers know them by.
    public struct Person: Hashable, Sendable, Codable {
        public var name: String
        public var role: String?
        public var refs: [ExternalRef]

        public init(name: String, role: String? = nil, refs: [ExternalRef] = []) {
            self.name = name
            self.role = role
            self.refs = refs
        }

        public init(_ participant: Participant) {
            self.init(name: participant.name, role: participant.role, refs: participant.externalRefs)
        }

        public var participant: Participant { Participant(name: name, role: role, externalRefs: refs) }
    }
}

/// An episode held as a container of its own, its title, first date, cast and crew Wikidata's, and its
/// outline TMDb's, read through its season, since TMDb lists an episode's overview only there.
/// `Proposals/EpisodeDetails.md`.
extension AdminConsole {
    /// The crew jobs read from Wikidata: what a player shows. Wikidata lists others, which are not read.
    nonisolated static let readJobs = ["Director", "Writer"]

    /// Whether a crew member's job is one read from Wikidata, and so one Wikidata's crew replaces.
    nonisolated static func isRead(_ member: Participant) -> Bool {
        member.role.map(readJobs.contains) ?? false
    }

    /// Who is in a work, as Wikidata lists them, each with the character they play.
    public nonisolated static func cast(of work: Wikidata.Work) -> [Participant] {
        work.cast.map { participant($0, role: $0.character) }
    }

    /// Who directed and wrote a work, as Wikidata lists them: its directors, then its screenwriters.
    public nonisolated static func crew(of work: Wikidata.Work) -> [Participant] {
        work.directors.map { participant($0, role: readJobs[0]) }
            + work.screenwriters.map { participant($0, role: readJobs[1]) }
    }

    /// A credit as a participant: named as Wikidata names them, known by Wikidata's id for them and each
    /// other id Wikidata holds.
    private nonisolated static func participant(_ credit: Wikidata.Credit, role: String?) -> Participant {
        let item = ExternalRef(provider: .wikidata, value: credit.person)
        return Participant(name: credit.name, role: role, externalRefs: [item] + credit.refs.filter { $0 != item })
    }

    /// An episode read from Wikidata as a container of its own: its title, or the operator's own for it,
    /// its first date, cast and crew, and its references, Wikidata's first, holding its one feature.
    nonisolated static func episode(
        _ work: Wikidata.Work,
        id: ContainerID,
        title: String? = nil,
        outline: String? = nil
    ) -> Container {
        var container = Container(
            id: id,
            type: .episode,
            title: Title(title ?? work.title) ?? Title(work.title) ?? Title("Untitled")!,
            outline: outline,
            externalRefs: Special(episode: work).refs
        )
        container.premiered = work.premiered
        container.cast = cast(of: work)
        container.crew = crew(of: work)
        container.sequences = [
            Sequence(id: "main", items: [.leaf(Entry.Leaf(id: ItemID("episode")!, type: .episode))])
        ]
        return container
    }

    /// The fields of an episode's container Wikidata's item says otherwise: its first date, its cast,
    /// and its directors and writers, each when Wikidata has one. Crew of another job is the operator's.
    nonisolated static func credits(of container: Container, from work: Wikidata.Work) -> [ReviewWalk.Difference] {
        var differences: [ReviewWalk.Difference] = []
        if let premiered = work.premiered, premiered != container.premiered {
            differences.append(.premiered(premiered))
        }
        let cast = cast(of: work)
        if !cast.isEmpty, cast != container.cast { differences.append(.cast(cast.map(ReviewWalk.Person.init))) }
        let crew = crew(of: work)
        if !crew.isEmpty, crew != container.crew.filter(isRead) {
            differences.append(.crew(crew.map(ReviewWalk.Person.init)))
        }
        return differences
    }

    /// A container's crew with Wikidata's directors and writers in place of those it held, and the rest
    /// after them as they were.
    nonisolated static func crew(_ crew: [ReviewWalk.Person], replacing held: [Participant]) -> [Participant] {
        crew.map(\.participant) + held.filter { !isRead($0) }
    }

    /// The overviews TMDb gives the episodes of the season a container is, or is beneath, by TMDb's id for
    /// each episode, and where it holds their stills: read through the TMDb ids the season and the series
    /// above it carry. Nil when either carries none, or TMDb does not list the season.
    func tmdbEpisodes(
        of opened: OpenedContainer,
        _ container: Container,
        from tmdb: any TMDbSource,
        of silo: Silo
    ) async throws -> TMDbEpisodes? {
        let season =
            container.type == .season ? container : try await above(opened, ofType: .season, of: silo)?.container
        guard let id = (season?.externalRefs.first { $0.provider == .tmdb }).flatMap({ Int($0.value) }),
            let series = try await above(opened, ofType: .series, of: silo)?.tmdb,
            let seasons = try await Self.tmdbSeasons(of: series, from: tmdb),
            let number = seasons.numbers[id]
        else { return nil }
        let read = try await tmdb.season(number, of: seasons.series)
        return TMDbEpisodes(
            outlines: Dictionary(uniqueKeysWithValues: read.episodes.map { (String($0.key), $0.value) }),
            stills: Dictionary(uniqueKeysWithValues: read.stills.map { (String($0.key), $0.value) })
        )
    }

    /// The overviews TMDb gives a season's episodes, and where it holds their stills, by TMDb's id for
    /// each.
    struct TMDbEpisodes {
        var outlines: [String: String]
        var stills: [String: TMDb.EpisodeStills]

        /// An episode's content, by TMDb's id for it: its overview, and its stills, offered for its `thumb`.
        func content(of record: Int, from tmdb: any TMDbSource) async -> Content {
            let id = String(record)
            let stills =
                if let place = stills[id] { await AdminConsole.stills(of: place, from: tmdb) } else { [String]() }
            return Content(
                record: TMDb.Record(.episode, record),
                overview: outlines[id],
                images: TMDb.Images(stills: stills)
            )
        }
    }

    /// A draft of each missing episode chosen at a stop that the walk has not drafted yet, as a container
    /// of its own, and of each group of its missing episodes taken, holding them as containers beneath
    /// it, drafted again when its episodes have changed: what confirming the stop adds as new stops. Each
    /// episode's outline is TMDb's that the stop's reading read, and its title the operator's own when
    /// they gave one.
    func episodeDrafts(
        confirming id: String,
        in walk: ReviewWalk,
        from database: any ContainerDatabase,
        wikidata: any WikidataSource,
        tmdb: (any TMDbSource)?
    ) async throws -> [DraftTree] {
        guard let stop = walk.stops[id], stop.comparison != nil else { return [] }
        let drafted = Set(walk.drafts.values.map(ReviewWalk.missing))
        var trees: [DraftTree] = []
        var reader = Reader(wikidata: wikidata, tmdb: tmdb, database: database)
        reader.episodeOutlines = stop.comparison?.episodeOutlines ?? [:]
        reader.episodeStills = stop.comparison?.episodeStills ?? [:]
        let missing = walk.missingEpisodes(at: id)
        for episode in missing
        where stop.chosen.contains("episode:\(episode.id)") && !drafted.contains("episode:\(episode.id)") {
            var single = reader
            single.containers = []
            single.attributions = [:]
            let top = try await single.episode(episode, titled: walk.title(of: episode))
            trees.append(
                single.tree(
                    top: top,
                    item: Wikidata.Item(.episode, episode.id),
                    library: walk.library,
                    creating: ContainerDraft.Creating(parent: id)
                )
            )
        }
        for group in stop.groups where stop.chosen.contains(group.tick) {
            let episodes = group.episodes.compactMap { id in missing.first { $0.id == id } }
            guard let groupID = ContainerID(group.id), !episodes.isEmpty,
                walk.drafts[group.id].map({ Set($0.episodeTitles.keys) != Set(episodes.map(\.id)) }) ?? true
            else { continue }
            var grouping = reader
            grouping.containers = []
            grouping.attributions = [:]
            var child = Container(id: groupID, type: group.type, title: group.title)
            child.typeLabel = group.typeLabel
            // Its primary sequence goes by the id of the stop's it was made out of.
            child.sequences = [Sequence(id: walk.sequenceName(0, at: id), items: [])]
            grouping.containers.append(child)
            for episode in episodes {
                let made = try await grouping.episode(episode, titled: walk.title(of: episode))
                DraftTree.insert(
                    .child(Entry.Child(id: DraftTree.itemID(for: made.title.rawValue, in: child), container: made.id)),
                    into: &child,
                    sequence: nil,
                    at: nil
                )
            }
            grouping.containers[0] = child
            trees.append(grouping.tree(top: child, item: nil, library: walk.library, creating: .init(parent: id)))
        }
        return trees
    }
}
