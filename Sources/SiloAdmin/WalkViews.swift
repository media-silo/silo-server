// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

#if canImport(SwiftUI)
import SiloAdminKit
import SmdKit
import SmdSidecar
import SwiftUI

/// A held container's tree walked against TMDb: the walk's tree beside the open stop, with each
/// stop's state; the open stop's differences, each with a tick and none ticked to begin with; and the
/// series' unassigned specials beside every stop, to be placed in the one they belong to. What the
/// library holds and TMDb lacks is shown, and never offered for removal. Nothing is stored until the
/// walk is, and the store lists everything it will do first.
struct WalkSheet: View {
    let walking: ConsoleModel.Walking
    let model: ConsoleModel
    @Environment(\.dismiss) private var dismiss

    private var current: ConsoleModel.Walking { model.walking ?? walking }
    private var walk: TMDbWalk { current.walk }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(walk.stops[walk.root]?.title ?? walk.root) against TMDb").font(.title3.bold())
                TMDbMark()
                Spacer()
                Text(counts).font(.caption).foregroundStyle(.secondary)
            }
            if current.resuming {
                HStack {
                    Label(
                        "This Mac kept a walk of this tree, last changed \(walk.edited.formatted(date: .abbreviated, time: .shortened)): \(counts).",
                        systemImage: "clock.arrow.circlepath"
                    )
                    Spacer()
                    Button("Start Again", role: .destructive) { Task { await model.startWalkAgain() } }
                    Button("Resume") { Task { await model.resumeWalk() } }.buttonStyle(.borderedProminent)
                }
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
            HSplitView {
                WalkTree(walk: walk, open: current.open) { stop in Task { await model.openStop(stop) } }
                    .frame(minWidth: 220, idealWidth: 260)
                stopDetail.frame(minWidth: 400, idealWidth: 480)
                if walk.series != nil {
                    WalkSpecials(current: current, model: model).frame(minWidth: 260, idealWidth: 320)
                }
            }
            .frame(minHeight: 380)
            .disabled(current.resuming)
            if let plan = current.plan { storeList(plan) }
            if let failure = current.failure {
                Label(failure, systemImage: "exclamationmark.octagon").foregroundStyle(.red).font(.caption)
                    .textSelection(.enabled)
            }
            Text(TMDb.notice).font(.caption2).foregroundStyle(.secondary)
            actions
        }
        .padding()
        .frame(minWidth: 1040, minHeight: 680)
        .alert(
            "Confirming takes containers out of the walk",
            isPresented: Binding(get: { current.leaving != nil }, set: { if !$0 { model.walking?.leaving = nil } })
        ) {
            Button("Confirm", role: .destructive) { Task { await model.confirmStop(leavingSaid: true) } }
            Button("Cancel", role: .cancel) { model.walking?.leaving = nil }
        } message: {
            Text(
                "No longer chosen, these new containers leave the walk with everything beneath them, and the specials placed in them are unassigned again: \((current.leaving ?? []).joined(separator: ", "))."
            )
        }
    }

    private var counts: String {
        let stops = walk.order
        let confirmed = stops.filter { walk.stops[$0]?.taken != nil }.count
        return "\(confirmed) of \(stops.count) containers confirmed"
    }

    private var actions: some View {
        HStack {
            Button("Close") {
                model.keepWalk()
                model.walking = nil
                dismiss()
            }
            Button("Discard the Walk", role: .destructive) {
                model.discardWalk()
                dismiss()
            }
            .help("Nothing of the walk has been stored unless the store said so; discarded, this Mac keeps none of it.")
            Spacer()
            if current.plan == nil {
                Button("Store the Walk…") { model.listStore() }
                    .disabled(walk.order.allSatisfy { walk.stops[$0]?.taken == nil })
            }
            Button("Next") { Task { await model.nextStop() } }
                .buttonStyle(.borderedProminent)
                .disabled(walk.next == nil || walk.next == current.open)
        }
    }

    // MARK: The open stop

    @ViewBuilder
    private var stopDetail: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let stop = current.stop {
                HStack {
                    Text(stop.title).font(.headline)
                    Text(stop.type).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    StopState(state: walk.state(of: stop.id), walk: walk)
                    if walk.stops[stop.id]?.taken == nil {
                        Button("Confirm") { Task { await model.confirmStop() } }
                            .help("Says this is as it should be, so the walk need not come back to it before storing.")
                            .disabled(current.resuming || current.confirming || current.progress[stop.id] != nil)
                    } else {
                        Button("Unconfirm") { model.unconfirmStop() }
                            .help("Pending again, with its choices as they are. Changing anything here does the same.")
                    }
                }
                if let progress = current.progress[stop.id] { ReadingProgress(progress: progress) }
                if let failure = current.failures[stop.id] {
                    HStack {
                        Label(failure, systemImage: "exclamationmark.octagon").foregroundStyle(.red).font(.caption)
                            .textSelection(.enabled)
                        Spacer()
                        Button("Read Again") { Task { await model.readStopAgain() } }
                    }
                    Text("Confirmed as it is, it takes nothing, and the walk goes on beneath it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if walk.isNew(stop.id) {
                    ScrollView { NewStop(current: current, model: model, stop: stop.id, tick: tick) }
                } else if let comparison = stop.comparison {
                    if !comparison.reading.isEmpty {
                        Text("Read \(comparison.reading).").font(.caption).foregroundStyle(.secondary)
                    }
                    ScrollView { differences(comparison) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
    }

    @ViewBuilder
    private func differences(_ comparison: AdminConsole.TMDbComparison) -> some View {
        // Lazy, to pin the children's heading and actions while their list scrolls beneath them.
        LazyVStack(alignment: .leading, spacing: 10, pinnedViews: [.sectionHeaders]) {
            ForEach(comparison.differences.filter(\.isUnmatched)) { unmatched in
                if case .unmatchedSeason(_, let seasons, let suggested) = unmatched {
                    UnmatchedSeason(title: comparison.title, seasons: seasons, suggested: suggested) { season in
                        Task { await model.identifySeason(season) }
                    }
                }
            }
            if let season = walk.identified[comparison.container] {
                HStack {
                    Text("Read as TMDb's season \(season), as you said it is.").font(.caption)
                    Button("Unmatched Again") { Task { await model.identifySeason(nil) } }
                        .buttonStyle(.borderless).font(.caption)
                }
            }
            DifferenceGroup("Fields", comparison.differences.filter(\.isField), walk: walk, tick: tick)
            DifferenceGroup("References", comparison.differences.filter(\.isReference), walk: walk, tick: tick)
            WalkChildren(current: current, model: model, comparison: comparison, tick: tick)
            DifferenceGroup("Order", comparison.differences.filter(\.isOrder), walk: walk, tick: tick)
            DifferenceGroup("Artwork", comparison.differences.filter(\.isArtwork), walk: walk, tick: tick)
            StopAlternatives(walk: walk, model: model, stop: comparison.container)
            PlacedSpecials(walk: walk, model: model, stop: comparison.container)
            if !comparison.heldOnly.isEmpty {
                GroupBox("Held here, and nothing at TMDb: nothing is offered for removal") {
                    ForEach(comparison.heldOnly, id: \.self) { Text($0).font(.caption) }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if !walk.differences(of: comparison.container).contains(where: {
                !$0.isSpecial && !$0.isHeld && !$0.isUnmatched
            }),
                current.progress[comparison.container] == nil
            {
                Label("Nothing differs from TMDb's record", systemImage: "checkmark.seal").foregroundStyle(.green)
            }
        }
    }

    private func tick(_ id: String) -> Binding<Bool> {
        let open = current.open
        return Binding(
            get: { current.walk.stops[open]?.chosen.contains(id) ?? false },
            set: { on in
                model.walking?.walk.choose(id, on, at: open)
                model.walking?.plan = nil
                model.keepWalk()
            }
        )
    }

    // MARK: The store

    @ViewBuilder
    private func storeList(_ plan: TMDbWalk.Plan) -> some View {
        GroupBox("Storing the walk will") {
            VStack(alignment: .leading, spacing: 4) {
                if let stored = current.stored {
                    ForEach(stored.stored) { step in
                        Label(step.described, systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(
                            .caption
                        )
                    }
                    if let refusal = stored.refusal {
                        Label("Refused: \(refusal)", systemImage: "exclamationmark.octagon").foregroundStyle(.red)
                            .font(.caption).textSelection(.enabled)
                    }
                }
                ForEach(plan.steps) { step in Text("• \(step.described)").font(.caption) }
                let pending = walk.order.filter { walk.stops[$0]?.taken == nil }.count
                if pending > 0 {
                    Text(
                        "\(pending) of \(walk.order.count) containers are pending: nothing of them is stored, nor of a new container beneath one."
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    if plan.steps.isEmpty {
                        Label(current.stored == nil ? "Nothing to store" : "Stored", systemImage: "checkmark.circle")
                            .foregroundStyle(.green).font(.caption)
                    }
                    Spacer()
                    Button("Not Yet") { model.walking?.plan = nil }
                    Button("Store") { Task { await model.storeWalk() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(plan.steps.isEmpty || current.storing)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The walk's tree as far as it has found it, each stop with its state; choosing one opens it.
private struct WalkTree: View {
    let walk: TMDbWalk
    let open: String
    let opening: (String) -> Void

    var body: some View {
        let states = walk.states()
        List(walk.order, id: \.self, selection: Binding(get: { open }, set: { $0.map(opening) })) { id in
            if let stop = walk.stops[id] {
                HStack(spacing: 6) {
                    StopState(state: states[id] ?? .pending, walk: walk, compact: true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(stop.title).lineLimit(1)
                        Text(walk.isNew(id) ? "\(stop.type), new" : stop.type).font(.caption2)
                            .foregroundStyle(walk.isNew(id) ? .blue : .secondary)
                    }
                }
                .padding(.leading, CGFloat(depth(of: id)) * 14)
            }
        }
    }

    private func depth(of id: String) -> Int {
        var depth = 0
        var parent = walk.stops[id]?.parent
        while let above = parent, above != walk.stops[walk.root]?.parent, walk.stops[above] != nil {
            depth += 1
            parent = walk.stops[above]?.parent
        }
        return depth
    }
}

/// A new stop: what it will be created with, each ticked to begin with, and its draft shaped as a
/// draft from TMDb is, its container's form and its entries regrouped into containers beneath it.
private struct NewStop: View {
    let current: ConsoleModel.Walking
    let model: ConsoleModel
    let stop: String
    let tick: (String) -> Binding<Bool>

    private var walk: TMDbWalk { current.walk }

    var body: some View {
        // Lazy, to pin the children's heading and actions while their list scrolls beneath them.
        LazyVStack(alignment: .leading, spacing: 10, pinnedViews: [.sectionHeaders]) {
            Text("New: drafted from TMDb, and made when the walk is stored.").font(.caption).foregroundStyle(.secondary)
            let offered = walk.offered(stop)
            DifferenceGroup("Fields", offered.filter(\.isField), walk: walk, tick: tick)
            DifferenceGroup("References", offered.filter(\.isReference), walk: walk, tick: tick)
            if let container = walk.container(stop), let tree = walk.draft(holding: stop) {
                Text(
                    "Ticked, each child is made with this one when the walk is stored, and unticked it is left out. Each group made here is a new container beneath this one, looked at in the walk once this is confirmed."
                )
                .font(.caption).foregroundStyle(.secondary)
                EntryGrouping(
                    tree: tree,
                    parent: stop,
                    update: { model.shapeNewStop($0) },
                    provisionalID: { try? await model.provisionalID() },
                    clone: { title in model.draftAlternatives { $0.cloneSequence(0, of: stop, titled: title) } },
                    rename: { name, beneath in
                        model.draftAlternatives { $0.renameSequence(0, at: stop, to: name, beneath: beneath) }
                    }
                )
                DisclosureGroup("Its form") {
                    ContainerForm(container: container) { changed in model.shapeNewStop { $0.set(changed) } }
                }
            }
            StopAlternatives(walk: walk, model: model, stop: stop)
            PlacedSpecials(walk: walk, model: model, stop: stop)
        }
    }
}

/// A stop's differences of one kind, each ticked to be taken, held or new alike; its heading ticks them
/// all or none.
private struct DifferenceGroup: View {
    let title: String
    let differences: [AdminConsole.TMDbDifference]
    let walk: TMDbWalk
    let tick: (String) -> Binding<Bool>

    init(
        _ title: String,
        _ differences: [AdminConsole.TMDbDifference],
        walk: TMDbWalk,
        tick: @escaping (String) -> Binding<Bool>
    ) {
        self.title = title
        self.differences = differences
        self.walk = walk
        self.tick = tick
    }

    var body: some View {
        if !differences.isEmpty {
            GroupBox {
                VStack(alignment: .leading) {
                    ForEach(differences) { difference in
                        Toggle(isOn: tick(difference.id)) { DifferenceLabel(difference: difference, walk: walk) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                // Ticks the group's every difference or none, and shows as mixed while some are ticked.
                Toggle(sources: differences.map { tick($0.id) }, isOn: \.self) { Text(title) }
            }
        }
    }
}

/// A stop's alternatives, edited by dragging specials onto them, and its extras, dropped onto by kind.
private struct StopAlternatives: View {
    let walk: TMDbWalk
    let model: ConsoleModel
    let stop: String

    var body: some View {
        if let container = walk.container(stop) {
            AlternativesEditor(drafting: walk, container: container, change: model.draftAlternatives)
            ExtrasDropZones(
                container: stop,
                placements: walk.placements,
                place: { model.place($0, $1) },
                declines: stop == walk.series
            )
        }
    }
}

/// The specials placed as part of a stop's pending change, held or new, each with where it went and a way
/// back among the unassigned.
private struct PlacedSpecials: View {
    let walk: TMDbWalk
    let model: ConsoleModel
    let stop: String

    var body: some View {
        let placed = walk.placed(in: stop)
        if !placed.isEmpty {
            GroupBox("Specials placed here") {
                ForEach(placed) { special in
                    HStack {
                        Text(special.episode.title)
                            .draggable(special: special.id, title: special.episode.title)
                        Text(walk.placements[special.id].map { WalkSpecials.describe($0, in: walk) } ?? "")
                            .font(.caption).foregroundStyle(.green)
                        Spacer()
                        Button("Unassign") { model.place(special.id, nil) }.buttonStyle(.borderless)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// A difference as the walk says it, the same for a held container and a new one: a field TMDb's text
/// is taken into with its attribution marked.
private struct DifferenceLabel: View {
    let difference: AdminConsole.TMDbDifference
    let walk: TMDbWalk

    var body: some View {
        switch difference {
        case .title(let title): Text("Title: \(title)")
        case .year(let year): Text("Year: \(year)")
        case .outline(let text, let record):
            VStack(alignment: .leading) {
                Text(text).font(.callout)
                HStack(spacing: 4) {
                    TMDbMark()
                    Text("taken with its attribution to TMDb \(record)").font(.caption).foregroundStyle(.secondary)
                }
            }
        case .reference(let item, let ref): Text("\(ref.provider.title) \(ref.value)\(item.map { " for \($0)" } ?? "")")
        case .episode(let episode, _): Text(walk.title(of: episode))
        case .season(let season): Text(season.name)
        case .heldSeason(let season, let container, let suggested):
            let held = walk.stops[container]?.title ?? container
            if suggested {
                Text(
                    "\(season.name): perhaps \(held), which the library holds with no TMDb id; say which season it is when the walk reaches it"
                )
            } else if walk.identified[container] != nil {
                Text("\(season.name): held as \(held), as you said it is")
            } else {
                Text("\(season.name): held as \(held)")
            }
        case .unmatchedSeason: EmptyView()
        case .order(let sequence, let items):
            Text("\(sequence ?? "The sequence") in TMDb's order: \(items.joined(separator: ", "))")
        case .artwork(let kind, let path, _):
            HStack {
                AsyncImage(url: URL(string: "https://image.tmdb.org/t/p/w185\(path)")) {
                    $0.resizable().scaledToFit()
                } placeholder: {
                    ProgressView()
                }
                .frame(width: 60, height: 60)
                Text("\(kind), credited to TMDb")
            }
        case .special(let special): Text(special.episode.title)
        }
    }
}

/// A held stop's children: the seasons TMDb has, those the library holds shown ticked and never chosen,
/// and the episodes it lacks, which may be grouped into new containers beneath it or added to one it
/// holds beneath it, each held one shown in its place among them. What ticking each does is said once,
/// above them.
private struct WalkChildren: View {
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
        if !seasons.isEmpty {
            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Text(
                        "Ticked, each season the library lacks is drafted from TMDb when this is confirmed, and looked at in the walk after it. Those it holds are looked at whatever is ticked."
                    )
                    .font(.caption).foregroundStyle(.secondary)
                    ForEach(seasons) { season in
                        if season.isHeld {
                            Toggle(isOn: .constant(true)) { DifferenceLabel(difference: season, walk: walk) }
                                .disabled(true)
                        } else {
                            Toggle(isOn: tick(season.id)) { DifferenceLabel(difference: season, walk: walk) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                heading(seasons.filter { !$0.isHeld }.map(\.id))
            }
        }
        if !episodes.isEmpty { missing }
    }

    /// The children that may be ticked: each episode the library lacks grouped in none, and each group as
    /// one, which is what the heading's tick ticks.
    private var tickable: [String] {
        episodes.filter { !grouped.contains($0.id) }.map { "episode:\($0.id)" } + groups.map(\.tick)
    }

    /// Ticks every child that may be ticked or none, and shows as mixed while some are; how many are is
    /// always said.
    @ViewBuilder
    private func heading(_ tickable: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if tickable.isEmpty {
                Text("Children, each held here")
            } else {
                Toggle(sources: tickable.map(tick), isOn: \.self) {
                    Text("Children, \(tickable.filter { tick($0).wrappedValue }.count) of \(tickable.count) ticked")
                }
            }
            if walk.container(stop)?.sequences.isEmpty == false {
                PrimarySequence(
                    name: walk.sequenceName(0, at: stop),
                    clone: { title in model.draftAlternatives { $0.cloneSequence(0, of: stop, titled: title) } },
                    rename: { name, beneath in
                        model.draftAlternatives { $0.renameSequence(0, at: stop, to: name, beneath: beneath) }
                    }
                )
            }
        }
    }

    /// What ticking does said above the list, and the list, as a new stop has them.
    @ViewBuilder
    private var missing: some View {
        Text(
            "Ticked, each child the library lacks is added to this one when the walk is stored, and unticked it is left out. Each group made here is a new container beneath this one, looked at in the walk once this is confirmed, and each child put into one held here is that one's own, ticked at its stop."
        )
        .font(.caption).foregroundStyle(.secondary)
        GroupingList(
            rows: rows,
            suggestions: walk.suggestedGroups(at: stop).map {
                GroupingSuggestion(title: $0.title, members: $0.episodes.map(String.init))
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
            ungroup: { group in model.groupEpisodes { $0.ungroup(group, at: $1) } },
            renaming: walk.suggestedRenaming(at: stop).map {
                GroupingSuggestion(title: $0.title, members: $0.episodes.map(String.init))
            },
            rename: { word in
                guard let episodes = walk.suggestedRenaming(at: stop)?.episodes else { return }
                model.groupEpisodes { $0.title(episodes, at: $1, as: word) }
            }
        ) {
            heading(tickable)
        }
    }

    /// The children as the walk lists them, each group with its episodes and each container held beneath
    /// with those put into it.
    private var rows: [GroupingRow] {
        walk.children(at: stop).map { child in
            switch child {
            case .episode(let episode):
                return .member(member(episode))
            case .group(let group):
                let members = group.episodes.compactMap { id in episodes.first { $0.id == id } }
                return .group(
                    GroupingGroup(
                        id: group.id,
                        title: group.title.rawValue,
                        kind: group.typeLabel ?? group.type.title,
                        members: members.map(member)
                    )
                )
            case .held(let held):
                return heldRow(held)
            }
        }
    }

    /// A container held beneath, with the missing episodes added to it.
    private func heldRow(_ child: AdminConsole.HeldChild) -> GroupingRow {
        let added = intoHeld[child.id] ?? []
        return .group(
            GroupingGroup(
                id: child.id,
                title: child.title,
                kind: child.typeLabel ?? child.type.title,
                members: episodes.filter { added.contains($0.id) }.map(member),
                held: true
            )
        )
    }

    private func member(_ episode: TMDb.Episode) -> GroupingMember {
        GroupingMember(id: String(episode.id), title: walk.title(of: episode))
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

/// A stop's state in the walk: pending, or confirmed and what storing does with its container.
private struct StopState: View {
    let state: TMDbWalk.StopState
    let walk: TMDbWalk
    var compact = false

    var body: some View {
        if compact {
            Image(systemName: symbol).foregroundStyle(color).help(word)
        } else {
            Label(word, systemImage: symbol).foregroundStyle(color).font(.caption)
        }
    }

    private var word: String {
        switch state {
        case .pending: "Pending"
        case .willCreate: "Confirmed (will create)"
        case .waiting(let above): "Confirmed (will create once \(walk.stops[above]?.title ?? above) is confirmed)"
        case .willEdit: "Confirmed (will edit)"
        case .unchanged: "Confirmed (unchanged)"
        }
    }

    private var symbol: String {
        switch state {
        case .pending: "circle.dotted"
        case .willCreate: "plus.circle.fill"
        case .waiting: "clock.badge.checkmark"
        case .willEdit: "pencil.circle.fill"
        case .unchanged: "checkmark.circle"
        }
    }

    private var color: Color {
        switch state {
        case .pending, .waiting: .secondary
        case .willCreate: .blue
        case .willEdit: .orange
        case .unchanged: .green
        }
    }
}

/// The series' unassigned specials beside every stop, each with its suggestion, the ones suggested for
/// the open stop marked and first; placing one puts it in the open stop's pending change.
private struct WalkSpecials: View {
    let current: ConsoleModel.Walking
    let model: ConsoleModel
    /// What is being made for a special, asked as it is placed.
    @State private var naming: SpecialNaming?

    private var walk: TMDbWalk { current.walk }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Specials: \(walk.unassigned.count) of \(walk.specials.count) unassigned").font(.headline)
            if let pooling = current.pooling { ReadingProgress(progress: pooling) }
            if walk.series == walk.root, walk.stops[walk.root]?.comparison == nil {
                Text("Read with the series.").font(.caption).foregroundStyle(.secondary)
            }
            List {
                ForEach(ordered) { special in row(special) }
                if !walk.declined.isEmpty, walk.stops[walk.series ?? ""] != nil {
                    Section("Declined: \(walk.declined.count)") {
                        ForEach(walk.declined.filter { walk.placements[$0.id] == nil }) { special in row(special) }
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        .sheet(item: $naming) { naming in
            SpecialNamingSheet(naming: naming) { title, listed in place(naming, titled: title, listed: listed) }
        }
    }

    /// A special placed as what was named for it: another version of the open stop, or of one of its
    /// episodes, titled as asked, or a new companion series of that title.
    private func place(_ naming: SpecialNaming, titled title: Title, listed: Bool) {
        switch naming {
        case .edition(let special, let stop, _):
            model.place(special.id, .edition(of: stop, title: title.rawValue))
        case .version(let special, let stop, let item, _):
            model.place(special.id, .version(of: stop, item: item, title: title.rawValue))
        case .companion(let special, let stop):
            Task {
                guard let id = try? await model.provisionalID() else { return }
                var companion = Container(id: id, type: .series, title: title, listed: listed)
                companion.sequences = [Sequence(id: "episodes", items: [])]
                model.place(special.id, .breakout(id.value, from: stop, asExtra: true), companion: companion)
            }
        }
    }

    /// The unassigned, those suggested for the open stop first.
    private var ordered: [Special] {
        let unassigned = walk.unassigned
        return unassigned.filter(isSuggestedHere) + unassigned.filter { !isSuggestedHere($0) }
    }

    private func isSuggestedHere(_ special: Special) -> Bool {
        walk.isSuggested(special, here: current.open)
    }

    @ViewBuilder
    private func row(_ special: Special) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(special.episode.title).lineLimit(2)
                    .draggable(special: special.id, title: special.episode.title)
                    .help("Drag onto the open stop's alternatives or extras.")
                TMDbMark()
                if isSuggestedHere(special) {
                    Text("suggested here").font(.caption2.bold()).foregroundStyle(.orange)
                }
            }
            if let aired = special.episode.airDate { Text(aired).font(.caption2).foregroundStyle(.secondary) }
            if let suggestion = walk.suggestions[special.id] {
                Text("Suggested: \(suggestion.reason)").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                if let placement = walk.suggestions[special.id]?.placement {
                    Button("Take") { model.place(special.id, placement) }
                }
                placementMenu(special)
            }
        }
    }

    @ViewBuilder
    private func placementMenu(_ special: Special) -> some View {
        let open = current.open
        let title = walk.stops[open]?.title ?? open
        let held = walk.container(open)
        Menu("Place") {
            if let held {
                Menu("As an entry of \(title)") {
                    ForEach(held.sequences.indices, id: \.self) { index in
                        let sequence = held.sequences[index]
                        Menu(sequenceTitle(sequence, in: held)) {
                            Button("First") {
                                model.place(special.id, .entry(in: open, sequence: sequence.id, position: 0))
                            }
                            ForEach(sequence.items.indices, id: \.self) { position in
                                Button("After \(itemTitle(sequence.items[position]))") {
                                    model.place(
                                        special.id,
                                        .entry(in: open, sequence: sequence.id, position: position + 1)
                                    )
                                }
                            }
                        }
                    }
                    if held.sequences.isEmpty {
                        Button("As its first") { model.place(special.id, .entry(in: open)) }
                    }
                }
                alternativesMenu(special, of: held)
            }
            Menu("As an extra of \(title)") {
                ForEach(EntryType.extraTypes, id: \.self) { type in
                    Button(type.rawValue) { model.place(special.id, .extra(of: open, type: type.rawValue)) }
                }
            }
            Button("As a container of its own beneath \(title)") {
                Task {
                    guard let id = try? await model.provisionalID() else { return }
                    model.place(special.id, .child(of: open, id: id.value, type: ContainerType.serial.rawValue))
                }
            }
            companionMenu(special)
            Divider()
            Button("Declined") { model.place(special.id, .declined) }
        }
        .fixedSize()
        .disabled(walk.container(current.open) == nil)
    }

    /// Another way to play the open stop: a new edition of it, or a version of one of its items.
    @ViewBuilder
    private func alternativesMenu(_ special: Special, of held: Container) -> some View {
        let open = current.open
        Button("As Another Version of \(held.displayTitle)…") {
            naming = .edition(special, of: open, held.displayTitle)
        }
        Menu("In Place of One of Its Items, as Another Version") {
            ForEach(held.sequences.flatMap(\.items).filter { $0.id != nil }, id: \.self) { entry in
                Button("\(itemTitle(entry))…") {
                    guard let item = entry.id?.value else { return }
                    naming = .version(special, of: open, item: item, itemTitle(entry))
                }
            }
        }
    }

    /// A companion series beside this one, held already or new, referred to from the open stop.
    @ViewBuilder
    private func companionMenu(_ special: Special) -> some View {
        let open = current.open
        let title = walk.stops[open]?.title ?? open
        Menu("Into a companion series") {
            ForEach(companionChoices, id: \.id) { id, name, listed in
                Menu("\(name)\(listed ? "" : " (unlisted)")") {
                    Button("Referred to from \(title)'s extras") {
                        model.place(special.id, .breakout(id, from: open, asExtra: true))
                    }
                    Button("Referred to from \(title)'s sequence") {
                        model.place(special.id, .breakout(id, from: open, asExtra: false))
                    }
                }
            }
            Divider()
            Button("A New One, Referred to from \(title)'s Extras…") { naming = .companion(special, from: open) }
        }
    }

    /// The series a special may go into as its companion: those the library holds, then those the walk
    /// makes.
    private var companionChoices: [(id: String, name: String, listed: Bool)] {
        let made = walk.companions.keys.sorted().compactMap(walk.companion)
        return current.companions.map { ($0.id, $0.displayTitle, $0.listed) }
            + made.map { ($0.id.value, $0.displayTitle, $0.listed) }
    }

    /// A sequence by the alternative that plays it, when one does.
    private func sequenceTitle(_ sequence: Sequence, in container: Container) -> String {
        guard let alternative = container.alternatives.first(where: { $0.sequence == sequence.id }) else {
            return sequence.id ?? "The sequence"
        }
        return "\(alternative.title ?? alternative.id), an alternative"
    }

    private func itemTitle(_ entry: Entry) -> String {
        if let title = entry.title { return title }
        let titles =
            current.stop?.comparison?.episodeTitles ?? walk.draft(holding: current.open)?.episodeTitles ?? [:]
        if let ref = entry.externalRefs.first(where: { $0.provider == .tmdb }), let title = titles[ref.value] {
            return title
        }
        return entry.id?.value ?? entry.reference.map { "\($0.container?.value ?? "")#\($0.item)" } ?? "an item"
    }

    static func describe(_ placement: SpecialPlacement, in walk: TMDbWalk) -> String {
        func title(_ id: String) -> String { walk.stops[id]?.title ?? walk.companion(id)?.displayTitle ?? id }
        switch placement {
        case .entry(let id, let sequence, let position):
            return
                "an entry of \(title(id))\(sequence.map { " in \($0)" } ?? "")\(position.map { " at \($0 + 1)" } ?? "")"
        case .extra(let id, let type): return "a \(type) extra of \(title(id))"
        case .child(let id, _, let type): return "a \(type) of its own beneath \(title(id))"
        case .duplicate(let home, let item, let library, _, _): return "the same as \(home)#\(item) in \(library)"
        case .breakout(let id, let from, _): return "in \(title(id)), referred to from \(title(from))"
        case .edition(let id, let alternative): return "\(alternative), another version of \(title(id))"
        case .version(let id, let item, let alternative):
            return "\(alternative), another version, in place of \(walk.title(ofItem: item, at: id)) of \(title(id))"
        case .alternative(let id, let draft):
            let alternative = walk.alternatives(draftedAt: id).first { $0.id == draft }?.title ?? "an alternative"
            return "in \(alternative), another version of \(title(id))"
        case .declined: return "declined"
        }
    }
}

/// A held season carrying no TMDb id, which matches nothing at TMDb: said plainly, with TMDb's seasons to
/// say which it is, the one its title or episodes suggest chosen to begin with.
private struct UnmatchedSeason: View {
    let title: String
    let seasons: [TMDb.SeasonSummary]
    let suggested: Int?
    let identify: (Int) -> Void
    @State private var chosen: Int?

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Text(
                    "\(title) carries no TMDb id, so nothing at TMDb is read against it. Say which of TMDb's seasons it is, and it is read as that season and offered its id."
                )
                .font(.callout)
                if let suggested, let season = seasons.first(where: { $0.id == suggested }) {
                    Text("Its title or an episode beneath it suggests \(season.name).").font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Nothing about it suggests which.").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Picker("TMDb's season", selection: $chosen) {
                        Text("Choose…").tag(Int?.none)
                        ForEach(seasons, id: \.id) { season in
                            Text(season.id == suggested ? "\(season.name), suggested" : season.name).tag(
                                Int?.some(season.id)
                            )
                        }
                    }
                    .fixedSize()
                    Button("Read as This Season") { chosen.map(identify) }.disabled(chosen == nil)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Matches nothing at TMDb", systemImage: "questionmark.circle").foregroundStyle(.orange)
        }
        .onAppear { chosen = chosen ?? suggested }
    }
}
#endif
