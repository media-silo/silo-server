// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

#if canImport(SwiftUI)
import SiloAdminKit
import SmdKit
import SwiftUI

/// A held stop's children, one list in the order storing leaves them, each moved by its grab handle: the
/// seasons TMDb has, those the library holds shown ticked and never chosen, what the stop holds already,
/// and the episodes it lacks, which may be grouped into new containers beneath it or added to one it
/// holds beneath it, each held one shown in its place among them. What ticking each does is said once,
/// above them.
struct WalkChildren: View {
    let current: ConsoleModel.Walking
    let model: ConsoleModel
    let comparison: AdminConsole.TMDbComparison
    let tick: (String) -> Binding<Bool>

    private var walk: TMDbWalk { current.walk }
    private var stop: String { comparison.container }
    private var groups: [EpisodeGroup] { walk.stops[stop]?.groups ?? [] }
    private var held: [AdminConsole.HeldChild] { walk.heldChildren(at: stop) }
    private var intoHeld: [String: [Int]] { walk.stops[stop]?.intoHeld ?? [:] }
    /// The missing episodes grouped, or added to a container held beneath.
    private var grouped: Set<Int> { Set(groups.flatMap(\.episodes)).union(intoHeld.values.joined()) }
    private var seasons: [AdminConsole.TMDbDifference] {
        walk.differences(of: stop).filter { $0.isChild && !$0.isEpisode }
    }
    private var episodes: [TMDb.Episode] { walk.missingEpisodes(at: stop) }

    var body: some View {
        if rows.isEmpty {
            // Its heading still, for what its primary sequence's menu does.
            heading([])
        } else {
            missing
        }
    }

    /// The containers the operator added beneath it.
    private var added: [String] { walk.addedContainers(at: stop) }

    /// The children that may be ticked: each season and each episode the library lacks, the episodes
    /// grouped in none, and each group as one, which is what the heading's tick ticks.
    private var tickable: [String] {
        seasons.filter { !$0.isHeld }.map(\.id)
            + episodes.filter { !grouped.contains($0.id) }.map { "episode:\($0.id)" }
            + groups.map(\.tick)
    }

    /// Ticks every child that may be ticked or none, and shows as mixed while some are; how many are is
    /// always said.
    @ViewBuilder
    private func heading(_ tickable: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if tickable.isEmpty {
                HStack {
                    Text("Children, each held here")
                    undo
                }
            } else {
                HStack {
                    Toggle(sources: tickable.map(tick), isOn: \.self) {
                        Text("Children, \(tickable.filter { tick($0).wrappedValue }.count) of \(tickable.count) ticked")
                    }
                    undo
                }
            }
            if walk.container(stop)?.sequences.isEmpty == false {
                PrimarySequence(
                    name: walk.sequenceName(0, at: stop),
                    clone: { title in model.draftAlternatives { $0.cloneSequence(0, of: stop, titled: title) } },
                    rename: { name, beneath in
                        model.draftAlternatives { $0.renameSequence(0, at: stop, to: name, beneath: beneath) }
                    },
                    add: { type, title in await model.addContainer(type, title: title) }
                )
            }
        }
    }

    /// Puts the children back in the order storing would give them had none been moved.
    @ViewBuilder
    private var undo: some View {
        if walk.arrangedEntries[stop] != nil {
            Button("Undo Moves") { model.arrangeHeldStop(nil, before: nil) }
                .buttonStyle(.borderless).font(.caption)
                .help("The order storing would give them had nothing been moved.")
        }
    }

    /// What ticking does said above the list, and the list, as a new stop has them.
    @ViewBuilder
    private var missing: some View {
        if !seasons.isEmpty {
            Text(
                "Ticked, each season the library lacks is drafted from TMDb when this is confirmed, and looked at in the walk after it. Those it holds are looked at whatever is ticked."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
        Text(
            "In the order storing leaves them: drag a child by its handle to move it, or a special onto a child to place it before it. Ticked, each child the library lacks is added to this one when the walk is stored, and unticked it is left out. Each group made here is a new container beneath this one, looked at in the walk once this is confirmed, and each child put into one held here is that one's own, ticked at its stop."
        )
        .font(.caption).foregroundStyle(.secondary)
        GroupingList(
            rows: rows,
            suggestions: walk.suggestedGroups(at: stop).map {
                GroupingSuggestion(title: $0.title, members: $0.episodes.map(String.init), parts: $0.parts)
            },
            defaultKind: defaultKind,
            chosen: ticked,
            groupTick: { tick("group:\($0.id)") },
            form: { members, title, type, label in
                guard let id = try? await model.provisionalID() else { return }
                model.groupEpisodes { walk, stop in
                    walk.group(
                        members.compactMap(Int.init),
                        at: stop,
                        into: id.value,
                        type: type,
                        typeLabel: label,
                        title: title
                    )
                }
            },
            add: { members, group in
                let episodes = members.compactMap(Int.init)
                if held.contains(where: { $0.id == group }) {
                    model.groupEpisodes { $0.add(episodes, toHeld: group, at: $1) }
                } else {
                    model.groupEpisodes { $0.add(episodes, toGroup: group, at: $1) }
                }
            },
            remove: { member, group in
                guard let episode = Int(member) else { return }
                if held.contains(where: { $0.id == group }) {
                    model.groupEpisodes { $0.remove(episode, fromHeld: group, at: $1) }
                } else {
                    model.groupEpisodes { $0.remove(episode, fromGroup: group, at: $1) }
                }
            },
            ungroup: { group in
                if added.contains(group) {
                    model.groupEpisodes { walk, _ in walk.dropContainer(group) }
                } else {
                    model.groupEpisodes { $0.ungroup(group, at: $1) }
                }
            },
            renaming: walk.suggestedRenaming(at: stop).map {
                GroupingSuggestion(title: $0.title, members: $0.episodes.map(String.init), parts: $0.parts)
            },
            rename: { word in
                guard let episodes = walk.suggestedRenaming(at: stop)?.episodes else { return }
                model.groupEpisodes { $0.title(episodes, at: $1, as: word) }
            },
            move: { model.arrangeHeldStop($0, before: $1) },
            place: { model.placeAmongChildren($0, before: $1) }
        ) {
            heading(tickable)
        }
    }

    /// The children in the order storing leaves them, each group with its episodes, each container held
    /// beneath with those put into it, and what the stop holds already between them.
    private var rows: [GroupingRow] {
        walk.sequence(at: stop).map { child in
            switch child {
            case .episode(let episode):
                return .member(member(episode, key: child.key))
            case .entry(let entry):
                return .fixed(id: entry.id, entry.isAdded ? "\(entry.title), added" : entry.title)
            case .added(let id):
                let added = walk.stops[id]
                return .group(
                    GroupingGroup(
                        id: id,
                        entry: child.key,
                        title: added?.title ?? id,
                        kind: added.map { ContainerType(rawValue: $0.type)?.title ?? $0.type } ?? "",
                        members: [],
                        accepts: false
                    )
                )
            case .group(let group):
                let members = group.episodes.compactMap { id in episodes.first { $0.id == id } }
                return .group(
                    GroupingGroup(
                        id: group.id,
                        entry: child.key,
                        title: group.title.rawValue,
                        kind: group.typeLabel ?? group.type.title,
                        members: members.map { member($0) }
                    )
                )
            case .held(let held):
                return heldRow(held)
            case .season(let season):
                return .toggled(
                    id: child.key,
                    title: Self.name(of: season),
                    tick: season.isHeld ? nil : tick(season.id),
                    label: AnyView(DifferenceLabel(difference: season, walk: walk))
                )
            }
        }
    }

    /// A season's name, as its drag shows it.
    private static func name(of season: AdminConsole.TMDbDifference) -> String {
        switch season {
        case .season(let season), .heldSeason(let season, _, _): season.name
        default: season.id
        }
    }

    /// A container held beneath, with the missing episodes added to it.
    private func heldRow(_ child: AdminConsole.HeldChild) -> GroupingRow {
        let added = intoHeld[child.id] ?? []
        return .group(
            GroupingGroup(
                id: child.id,
                entry: HeldStopChild.held(child).key,
                title: child.title,
                kind: child.typeLabel ?? child.type.title,
                members: episodes.filter { added.contains($0.id) }.map { member($0) },
                held: true
            )
        )
    }

    private func member(_ episode: TMDb.Episode, key: String? = nil) -> GroupingMember {
        GroupingMember(id: String(episode.id), title: walk.title(of: episode), key: key)
    }

    /// The episodes not grouped, ticked as the stop has them.
    private var ticked: Binding<Set<String>> {
        let loose = episodes.filter { !grouped.contains($0.id) }.map(\.id)
        return Binding(
            get: {
                let chosen = walk.stops[stop]?.chosen ?? []
                return Set(loose.filter { chosen.contains("episode:\($0)") }.map(String.init))
            },
            set: { members in
                for episode in loose { tick("episode:\(episode)").wrappedValue = members.contains(String(episode)) }
            }
        )
    }

    /// The kind the containers held beneath it and the groups made already are, mostly.
    private var defaultKind: ContainerType? {
        let kinds = held.map(\.type) + groups.map(\.type)
        let counts = Dictionary(kinds.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.max { $0.value < $1.value }?.key
    }
}
#endif
