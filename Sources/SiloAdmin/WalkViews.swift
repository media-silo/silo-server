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
            "Confirming takes stops out of the walk",
            isPresented: Binding(get: { current.leaving != nil }, set: { if !$0 { model.walking?.leaving = nil } })
        ) {
            Button("Confirm", role: .destructive) { Task { await model.confirmStop(leavingSaid: true) } }
            Button("Cancel", role: .cancel) { model.walking?.leaving = nil }
        } message: {
            Text(
                "No longer chosen, these new stops leave the walk with everything beneath them, and the specials placed in them are unassigned again: \((current.leaving ?? []).joined(separator: ", "))."
            )
        }
    }

    private var counts: String {
        let stops = walk.order
        let confirmed = stops.filter { walk.state(of: $0) != .pending }.count
        return "\(confirmed) of \(stops.count) stops confirmed"
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
                    .disabled(walk.order.allSatisfy { walk.state(of: $0) == .pending })
            }
            Button("Confirm") { Task { await model.confirmStop() } }
                .disabled(current.resuming || current.confirming)
                .disabled(current.stop == nil || current.progress[current.open] != nil)
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
                    StopState(state: walk.state(of: stop.id))
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
        VStack(alignment: .leading, spacing: 10) {
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
            group("Fields", comparison.differences.filter(\.isField), comparison)
            group("References", comparison.differences.filter(\.isReference), comparison)
            group("Children", comparison.differences.filter(\.isChild), comparison)
            group("Order", comparison.differences.filter(\.isOrder), comparison)
            group("Artwork", comparison.differences.filter(\.isArtwork), comparison)
            let placed = walk.placed(in: comparison.container)
            if !placed.isEmpty {
                GroupBox("Specials placed here") {
                    ForEach(placed) { special in
                        HStack {
                            Text(special.episode.title)
                            Text(walk.placements[special.id].map(describe) ?? "").font(.caption).foregroundStyle(.green)
                            Spacer()
                            Button("Unassign") { model.place(special.id, nil) }.buttonStyle(.borderless)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if !comparison.heldOnly.isEmpty {
                GroupBox("Held here, and nothing at TMDb: nothing is offered for removal") {
                    ForEach(comparison.heldOnly, id: \.self) { Text($0).font(.caption) }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if !comparison.differences.contains(where: { !$0.isSpecial && !$0.isHeld && !$0.isUnmatched }),
                current.progress[comparison.container] == nil
            {
                Label("Nothing differs from TMDb's record", systemImage: "checkmark.seal").foregroundStyle(.green)
            }
        }
    }

    @ViewBuilder
    private func group(
        _ title: String,
        _ differences: [AdminConsole.TMDbDifference],
        _ comparison: AdminConsole.TMDbComparison
    ) -> some View {
        if !differences.isEmpty {
            GroupBox {
                VStack(alignment: .leading) {
                    ForEach(differences) { difference in
                        if difference.isHeld {
                            // A child the library holds is a stop of the walk whatever is chosen here.
                            Toggle(isOn: .constant(true)) { label(difference, comparison) }.disabled(true)
                        } else {
                            Toggle(isOn: tick(difference.id)) { label(difference, comparison) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                // Ticks the group's every difference or none, and shows as mixed while some are ticked.
                let tickable = differences.filter { !$0.isHeld }
                if tickable.isEmpty {
                    Text(title)
                } else {
                    Toggle(sources: tickable.map { tick($0.id) }, isOn: \.self) { Text(title) }
                }
            }
        }
    }

    private func tick(_ id: String) -> Binding<Bool> {
        let open = current.open
        return Binding(
            get: { current.walk.stops[open]?.chosen.contains(id) ?? false },
            set: { on in
                if on {
                    model.walking?.walk.stops[open]?.chosen.insert(id)
                } else {
                    model.walking?.walk.stops[open]?.chosen.remove(id)
                }
                model.keepWalk()
            }
        )
    }

    @ViewBuilder
    private func label(
        _ difference: AdminConsole.TMDbDifference,
        _ comparison: AdminConsole.TMDbComparison
    ) -> some View {
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
        case .episode(let episode, _): Text("Episode \(episode.number): \(episode.title)")
        case .season(let season): Text("\(season.name), a new stop beneath this once confirmed")
        case .heldSeason(let season, let container, let suggested):
            let held = walk.stops[container]?.title ?? container
            if suggested {
                Text(
                    "\(season.name): perhaps \(held), held here with no TMDb id, so matched to nothing; say which it is at its stop"
                )
            } else {
                Text("\(season.name): held as \(held), a stop of the walk")
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

    private func describe(_ placement: SpecialPlacement) -> String {
        WalkSpecials.describe(placement, in: walk)
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
        List(walk.order, id: \.self, selection: Binding(get: { open }, set: { $0.map(opening) })) { id in
            if let stop = walk.stops[id] {
                HStack(spacing: 6) {
                    StopState(state: walk.state(of: id), compact: true)
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
        VStack(alignment: .leading, spacing: 10) {
            Text("New: drafted from TMDb, and made when the walk is stored.").font(.caption).foregroundStyle(.secondary)
            let offered = walk.offered(stop)
            group("Fields", offered.filter(\.isField))
            group("References", offered.filter(\.isReference))
            if let container = walk.container(stop), let tree = walk.draft(holding: stop) {
                EntryGrouping(
                    tree: tree,
                    parent: stop,
                    update: { model.shapeNewStop($0) },
                    provisionalID: { try? await model.provisionalID() }
                )
                DisclosureGroup("Its form") {
                    ContainerForm(container: container) { changed in model.shapeNewStop { $0.set(changed) } }
                }
            }
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ differences: [AdminConsole.TMDbDifference]) -> some View {
        if !differences.isEmpty {
            GroupBox {
                VStack(alignment: .leading) {
                    ForEach(differences) { difference in
                        Toggle(isOn: tick(difference.id)) { Text(describe(difference)) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Toggle(sources: differences.map { tick($0.id) }, isOn: \.self) { Text(title) }
            }
        }
    }

    private func describe(_ difference: AdminConsole.TMDbDifference) -> String {
        switch difference {
        case .year(let year): "Year: \(year)"
        case .outline(let text, _): "\(text) (attributed to TMDb)"
        case .reference(_, let ref): "\(ref.provider.title) \(ref.value)"
        default: difference.id
        }
    }
}

/// A stop's state in the walk: pending, changed, or looked at.
private struct StopState: View {
    let state: TMDbWalk.StopState
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
        case .pending: "pending"
        case .changed: "changed"
        case .lookedAt: "looked at"
        }
    }

    private var symbol: String {
        switch state {
        case .pending: "circle.dotted"
        case .changed: "pencil.circle.fill"
        case .lookedAt: "checkmark.circle"
        }
    }

    private var color: Color {
        switch state {
        case .pending: .secondary
        case .changed: .orange
        case .lookedAt: .green
        }
    }
}

/// The series' unassigned specials beside every stop, each with its suggestion, the ones suggested for
/// the open stop marked and first; placing one puts it in the open stop's pending change.
private struct WalkSpecials: View {
    let current: ConsoleModel.Walking
    let model: ConsoleModel
    @State private var alternativeTitle = ""
    @State private var companionTitle = ""
    @State private var companionListed = false

    private var walk: TMDbWalk { current.walk }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Specials: \(walk.unassigned.count) of \(walk.specials.count) unassigned").font(.headline)
            if let pooling = current.pooling { ReadingProgress(progress: pooling) }
            if walk.series == walk.root, walk.stops[walk.root]?.comparison == nil {
                Text("Read with the series.").font(.caption).foregroundStyle(.secondary)
            }
            namingFields
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
    }

    /// What a new alternative and a new companion series are called, for the menus to make them with.
    private var namingFields: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("A new alternative's title", text: $alternativeTitle)
            HStack {
                TextField("A new companion series' title", text: $companionTitle)
                Toggle("Listed", isOn: $companionListed)
                    .help(
                        "Unlisted, it is browsed to only through what refers to it; listed, the household finds it too."
                    )
            }
        }
        .font(.caption)
    }

    /// The unassigned, those suggested for the open stop first.
    private var ordered: [Special] {
        let unassigned = walk.unassigned
        return unassigned.filter(isSuggestedHere) + unassigned.filter { !isSuggestedHere($0) }
    }

    private func isSuggestedHere(_ special: Special) -> Bool {
        walk.suggestions[special.id]?.placement.flatMap(walk.home) == current.open
    }

    @ViewBuilder
    private func row(_ special: Special) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(special.episode.title).lineLimit(2)
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
        let named = alternativeTitle.trimmingCharacters(in: .whitespaces)
        Button("As a new edition of \(held.displayTitle), \(named.isEmpty ? "Omnibus" : named)") {
            model.place(special.id, .edition(of: open, title: named.isEmpty ? "Omnibus" : named))
        }
        Menu("As a version of one of its items") {
            ForEach(held.sequences.flatMap(\.items).filter { $0.id != nil }, id: \.self) { entry in
                Button("\(itemTitle(entry)), \(named.isEmpty ? "Special edition" : named)") {
                    guard let item = entry.id?.value else { return }
                    model.place(
                        special.id,
                        .version(of: open, item: item, title: named.isEmpty ? "Special edition" : named)
                    )
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
            if let named = Title(companionTitle.trimmingCharacters(in: .whitespaces)) {
                Divider()
                Button(
                    "A new one, \(named.rawValue), \(companionListed ? "listed" : "unlisted"), referred to from the extras"
                ) {
                    Task {
                        guard let id = try? await model.provisionalID() else { return }
                        var companion = Container(id: id, type: .series, title: named, listed: companionListed)
                        companion.sequences = [Sequence(id: "episodes", items: [])]
                        model.place(special.id, .breakout(id.value, from: open, asExtra: true), companion: companion)
                        companionTitle = ""
                    }
                }
            }
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
        case .edition(let id, let alternative): return "a new edition of \(title(id)), \(alternative)"
        case .version(let id, let item, let alternative): return "a version of \(item) of \(title(id)), \(alternative)"
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
