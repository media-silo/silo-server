// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

#if canImport(SwiftUI)
import SiloAdminKit
import SiloClient
import SmdKit
import SmdSidecar
import SwiftUI

/// TMDb's mark, beside whatever the console shows that it read there.
struct TMDbMark: View {
    var body: some View {
        Text("TMDB")
            .font(.caption2.weight(.heavy))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .foregroundStyle(.white)
            .background(Color(red: 0.01, green: 0.15, blue: 0.25), in: RoundedRectangle(cornerRadius: 3))
            .help("From TMDb")
    }
}

/// TMDb as this Mac reads it, named in its settings: the token, kept in the keychain, the language it
/// answers in, why it cannot be read when it cannot, and the notice TMDb's terms ask for. The console
/// reaches TMDb itself; the silo is never given the token.
struct TMDbBar: View {
    let model: ConsoleModel
    @State private var token = ""
    @State private var language = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TMDbMark()
                Spacer()
                Button("Check") { Task { await model.checkTMDb() } }.buttonStyle(.borderless).font(.caption)
            }
            SecureField(model.tmdbToken == nil ? "Read access token" : "Token kept in the keychain", text: $token)
                .font(.caption)
                .onSubmit {
                    Task {
                        await model.setTMDbToken(token)
                        token = ""
                    }
                }
            TextField("Language", text: $language)
                .font(.caption)
                .onSubmit { model.setTMDbLanguage(language) }
            if let problem = model.tmdbProblem {
                Text(problem).font(.caption2).foregroundStyle(.orange).textSelection(.enabled)
            }
            Text(TMDb.notice).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .task {
            language = model.tmdbLanguage
            await model.checkTMDb()
        }
    }
}

/// The attributions of a container's own fields, each with the way to say the text is the operator's
/// own, which removes the attribution and leaves the text.
struct AttributionsLine: View {
    let attributions: [Attribution]
    let onRemove: (Attribution.Subject) -> Void
    @State private var confirming: Attribution.Subject?

    var body: some View {
        if !attributions.isEmpty {
            HStack {
                ForEach(attributions, id: \.self) { attribution in
                    HStack(spacing: 4) {
                        if attribution.provider == .tmdb { TMDbMark() }
                        Text("\(attribution.subject) from \(attribution.provider.title) \(attribution.value)")
                            .font(.caption)
                        Button("My Own Words…") { confirming = attribution.subject }
                            .buttonStyle(.borderless).font(.caption)
                    }
                }
                Spacer()
            }
            .confirmationDialog(
                "Is this text your own?",
                isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                presenting: confirming
            ) { subject in
                Button("It Is My Own") { onRemove(subject) }
            } message: { _ in
                Text("Rewording a provider's text keeps it theirs. Remove the attribution only for text you wrote.")
            }
        }
    }
}

/// Finding a record at TMDb to draft from: a movie or a series for a library, read the way the operator
/// chooses; or one of a held series' seasons, drafted beneath it. A record smddb or the library holds is
/// not drafted, and the sheet says what holds it.
struct FindInTMDbSheet: View {
    let finding: ConsoleModel.FindingInTMDb
    let model: ConsoleModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [TMDb.SearchResult] = []
    @State private var picked: TMDb.SearchResult?
    @State private var series: TMDb.Series?
    @State private var allSeasons = true
    @State private var seasons: Set<Int> = []
    @State private var group = ""
    @State private var groupType: ContainerType = .serial
    @State private var message: String?
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(
                    finding.series.map { "A season of \($0.title) from TMDb" }
                        ?? "Draft into \(finding.library) from TMDb"
                )
                .font(.title3.bold())
                Spacer()
                TMDbMark()
            }
            if finding.series == nil {
                HStack {
                    TextField("Title", text: $query).onSubmit { Task { await search() } }
                    Button("Search") { Task { await search() } }
                }
                List(results, id: \.record, selection: Binding(get: { picked?.record }, set: { pick($0) })) { result in
                    HStack {
                        Text(result.title)
                        if let year = result.year { Text(String(year)).foregroundStyle(.secondary) }
                        Spacer()
                        Text(result.record.kind.rawValue).font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(result.record)
                }
                .frame(minHeight: 160)
            }
            if let series {
                shapeOptions(series)
            }
            if let message {
                Label(message, systemImage: "info.circle").font(.caption).textSelection(.enabled)
            }
            Text(TMDb.notice).font(.caption2).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Draft") { Task { await draft() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(working || (finding.series == nil ? picked == nil : seasons.count != 1))
            }
        }
        .padding()
        .frame(minWidth: 560, minHeight: 440)
        .task {
            guard let held = finding.series else { return }
            series = try? await model.tmdbSeries(held.tmdb)
            allSeasons = false
        }
    }

    @ViewBuilder
    private func shapeOptions(_ series: TMDb.Series) -> some View {
        GroupBox(finding.series == nil ? "Read \(series.name) as" : "The season to draft") {
            VStack(alignment: .leading) {
                if finding.series == nil {
                    Toggle("Every season", isOn: $allSeasons)
                }
                if !allSeasons {
                    ScrollView {
                        VStack(alignment: .leading) {
                            ForEach(series.seasons.filter { $0.number != 0 }, id: \.number) { season in
                                Toggle(
                                    season.name,
                                    isOn: Binding(
                                        get: { seasons.contains(season.number) },
                                        set: { on in
                                            if finding.series != nil { seasons = [] }
                                            if on {
                                                seasons.insert(season.number)
                                            } else {
                                                seasons.remove(season.number)
                                            }
                                        }
                                    )
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 140)
                }
                if finding.series == nil, !series.episodeGroups.isEmpty {
                    Picker("Shape", selection: $group) {
                        Text("TMDb's seasons").tag("")
                        ForEach(series.episodeGroups, id: \.id) { Text($0.name).tag($0.id) }
                    }
                    if !group.isEmpty {
                        Picker("Each group is a", selection: $groupType) {
                            ForEach(ContainerType.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                    }
                }
                if finding.series == nil, series.seasons.contains(where: { $0.number == 0 }) {
                    Text("Season 0 is read as the series' specials, unassigned until you place them.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func search() async {
        working = true
        defer { working = false }
        do {
            results = try await model.searchTMDb(query)
            message = results.isEmpty ? "TMDb finds nothing by that title." : nil
        } catch {
            message = model.describe(error)
        }
    }

    private func pick(_ record: TMDb.Record?) {
        picked = results.first { $0.record == record }
        series = nil
        message = nil
        guard let record, record.kind == .series else { return }
        Task { series = try? await model.tmdbSeries(record.id) }
    }

    private func draft() async {
        working = true
        defer { working = false }
        do {
            if finding.series != nil, let number = seasons.first {
                try await model.startSeasonDraft(number, for: finding)
            } else if let picked {
                let shape = AdminConsole.TMDbShape(
                    seasons: allSeasons ? nil : seasons,
                    group: group.isEmpty ? nil : group,
                    groupType: groupType
                )
                message = try await model.startTMDbDraft(of: picked.record, shape: shape, for: finding)
            }
        } catch {
            message = model.describe(error)
        }
    }
}

/// A draft from TMDb being shaped before it is made: its tree, each container shaped in the container
/// form; entries regrouped into containers of their own; a series' specials placed from the pool; what
/// making it would do; and the silo's dry run.
struct ShapeTreeSheet: View {
    let shaping: ConsoleModel.ShapingTree
    let model: ConsoleModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected: String?
    @State private var chosenEntries: Set<String> = []
    @State private var groupTitle = ""
    @State private var groupType: ContainerType = .serial
    @State private var groupLabel = ""
    @State private var breakoutTitle = ""

    private var current: ConsoleModel.ShapingTree { model.shapingTree ?? shaping }
    private var tree: TMDbTree { current.tree }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Shape \(tree.title)").font(.title3.bold())
                TMDbMark()
                Spacer()
                Text("Into \(tree.library)").foregroundStyle(.secondary)
            }
            HSplitView {
                treeList.frame(minWidth: 260)
                detail.frame(minWidth: 320)
            }
            .frame(minHeight: 260)
            if !tree.specials.isEmpty { specialsPool }
            makingSummary
            HStack {
                Button("Discard", role: .destructive) { model.discardTree() }
                Spacer()
                if case .created? = current.outcome {
                    Button("Done") {
                        model.shapingTree = nil
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Close") { dismiss() }
                    Button("Make It") { Task { await model.createTree() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(!isWouldWrite)
                }
            }
        }
        .padding()
        .frame(minWidth: 760, minHeight: 620)
    }

    private var isWouldWrite: Bool {
        if case .wouldWrite? = current.check { return true }
        return false
    }

    // MARK: The tree

    private var treeList: some View {
        List(selection: $selected) {
            ForEach(tree.containers, id: \.id.value) { container in
                Section {
                    ForEach(container.sequences.flatMap(\.items), id: \.self) { entry in
                        entryRow(entry, in: container)
                    }
                } header: {
                    HStack {
                        Text("\(container.typeLabel ?? container.type.title): \(container.displayTitle)")
                        Spacer()
                        if container.id.value != tree.top {
                            Button("Drop") { model.updateTree { $0.drop(container.id.value) } }
                                .buttonStyle(.borderless).font(.caption)
                        }
                    }
                }
                .tag(container.id.value)
            }
        }
    }

    @ViewBuilder
    private func entryRow(_ entry: Entry, in container: Container) -> some View {
        let key = "\(container.id.value)/\(entry.id?.value ?? "")"
        if let child = entry.childContainer {
            Text("↳ \(tree.container(child.value)?.displayTitle ?? child.value)").foregroundStyle(.secondary)
        } else {
            Toggle(
                isOn: Binding(
                    get: { chosenEntries.contains(key) },
                    set: { on in
                        if on { chosenEntries.insert(key) } else { chosenEntries.remove(key) }
                    }
                )
            ) {
                HStack(spacing: 4) {
                    Text(entry.id?.value ?? "a reference").font(.caption.monospaced())
                    if let tmdb = entry.externalRefs.first(where: { $0.provider == .tmdb }),
                        let title = tree.episodeTitles[tmdb.value]
                    {
                        Text(title)
                        TMDbMark()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        VStack(alignment: .leading) {
            if !chosenEntries.isEmpty, let parent = chosenParent {
                GroupBox("Group \(chosenEntries.count) chosen into a new container") {
                    HStack {
                        TextField("Title", text: $groupTitle)
                        Picker("Type", selection: $groupType) {
                            ForEach(ContainerType.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .fixedSize()
                        TextField("Label", text: $groupLabel).frame(maxWidth: 80)
                        Button("Group") { Task { await regroup(in: parent) } }
                            .disabled(Title(groupTitle) == nil)
                    }
                }
            }
            if let selected, let container = tree.container(selected) {
                AttributionsLine(attributions: tree.attributions[selected] ?? []) { subject in
                    model.updateTree { $0.removeAttribution(of: subject, from: selected) }
                }
                ContainerForm(container: container) { changed in model.updateTree { $0.set(changed) } }
            } else {
                ContentUnavailableView(
                    "Nothing Chosen",
                    systemImage: "square.stack.3d.up",
                    description: Text("Choose a container to shape it, or tick entries to group them.")
                )
            }
        }
    }

    /// The container the chosen entries are in, when they are all in one.
    private var chosenParent: String? {
        let parents = Set(chosenEntries.map { String($0.split(separator: "/").first ?? "") })
        return parents.count == 1 ? parents.first : nil
    }

    private func regroup(in parent: String) async {
        guard let title = Title(groupTitle), let id = try? await model.provisionalID() else { return }
        let items = chosenEntries.compactMap { $0.split(separator: "/").last.flatMap { ItemID(String($0)) } }
        let order = tree.container(parent)?.sequences.flatMap(\.items).compactMap(\.id) ?? []
        model.updateTree {
            $0.regroup(
                order.filter(items.contains),
                in: parent,
                into: id,
                type: groupType,
                typeLabel: groupLabel.isEmpty ? nil : groupLabel,
                title: title
            )
        }
        chosenEntries = []
        groupTitle = ""
    }

    // MARK: Specials

    private var specialsPool: some View {
        GroupBox("Specials: \(tree.unassigned.count) of \(tree.specials.count) unassigned") {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(tree.specials) { special in specialRow(special) }
                }
            }
            .frame(maxHeight: 180)
            if let suggesting = current.suggesting { ReadingProgress(progress: suggesting) }
            HStack {
                TextField("New breakout's title", text: $breakoutTitle).frame(maxWidth: 220)
                Text("then file specials in it from their menus").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Suggest Again") { Task { await model.suggestSpecials() } }
                    .disabled(current.suggesting != nil)
            }
        }
    }

    @ViewBuilder
    private func specialRow(_ special: Special) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading) {
                HStack(spacing: 4) {
                    Text(special.episode.title)
                    TMDbMark()
                    if let aired = special.episode.airDate { Text(aired).font(.caption).foregroundStyle(.secondary) }
                }
                if let placement = tree.placements[special.id] {
                    Text(describe(placement)).font(.caption).foregroundStyle(.green)
                } else if let suggestion = current.suggestions[special.id] {
                    Text("Suggested: \(suggestion.reason)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if tree.placements[special.id] == nil, let placement = current.suggestions[special.id]?.placement {
                Button("Take") { model.updateTree { $0.place(special.id, placement) } }
            }
            placementMenu(special)
        }
    }

    private func placementMenu(_ special: Special) -> some View {
        Menu("Place") {
            ForEach(tree.containers, id: \.id.value) { container in
                Menu(container.displayTitle) {
                    Button("As an entry, last") {
                        model.updateTree { $0.place(special.id, .entry(in: container.id.value)) }
                    }
                    Menu("As an extra") {
                        ForEach(EntryType.extraTypes, id: \.self) { type in
                            Button(type.rawValue) {
                                model.updateTree {
                                    $0.place(special.id, .extra(of: container.id.value, type: type.rawValue))
                                }
                            }
                        }
                    }
                    Button("As a container of its own beneath it") {
                        Task {
                            guard let id = try? await model.provisionalID() else { return }
                            model.updateTree {
                                $0.place(
                                    special.id,
                                    .child(of: container.id.value, id: id.value, type: ContainerType.serial.rawValue)
                                )
                            }
                        }
                    }
                    breakoutMenu(special, from: container)
                }
            }
            Divider()
            Button("Declined") { model.updateTree { $0.place(special.id, .declined) } }
            Button("Unassigned") { model.updateTree { $0.place(special.id, nil) } }
        }
        .fixedSize()
    }

    @ViewBuilder
    private func breakoutMenu(_ special: Special, from container: Container) -> some View {
        Menu("Into a breakout, referred to from its extras") {
            ForEach(tree.breakouts.keys.sorted(), id: \.self) { id in
                Button(tree.container(id)?.displayTitle ?? id) {
                    model.updateTree { $0.place(special.id, .breakout(id, from: container.id.value, asExtra: true)) }
                }
            }
            if let title = Title(breakoutTitle) {
                Button("A new one, \(title)") {
                    Task {
                        guard let id = try? await model.provisionalID() else { return }
                        var breakout = Container(id: id, type: .series, title: title, listed: false)
                        breakout.sequences = [Sequence(id: "episodes", items: [])]
                        model.updateTree {
                            $0.place(
                                special.id,
                                .breakout(id.value, from: container.id.value, asExtra: true),
                                breakout: breakout
                            )
                        }
                        breakoutTitle = ""
                    }
                }
            }
        }
    }

    private func describe(_ placement: SpecialPlacement) -> String {
        func title(_ id: String) -> String { tree.container(id)?.displayTitle ?? id }
        switch placement {
        case .entry(let id, _, _): return "an entry of \(title(id))"
        case .extra(let id, let type): return "a \(type) extra of \(title(id))"
        case .child(let id, _, let type): return "a \(type) of its own beneath \(title(id))"
        case .duplicate(let home, let item, let library, _, _): return "the same as \(home)#\(item) in \(library)"
        case .breakout(let id, let from, _): return "in \(title(id)), referred to from \(title(from))"
        case .declined: return "declined"
        }
    }

    // MARK: Making

    private var makingSummary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Making it will").font(.headline)
            ForEach(tree.making.described, id: \.self) { Text("• \($0)").font(.caption) }
            switch current.check {
            case .wouldWrite(let result)?:
                Label("The silo would make it", systemImage: "checkmark.circle").foregroundStyle(.green).font(.caption)
                FindingsList(findings: result.findings)
            case .refused(let result)?:
                Label("The silo refuses it", systemImage: "exclamationmark.octagon").foregroundStyle(.red).font(
                    .caption
                )
                FindingsList(findings: result.findings)
            case .behind(let reason)?, .unreadable(let reason)?:
                Label(reason, systemImage: "exclamationmark.octagon").foregroundStyle(.red).font(.caption)
            case nil:
                EmptyView()
            }
            switch current.outcome {
            case .created?:
                Label("Made", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
            case .parentRefused(let result)?:
                Label("The parent's edit was refused", systemImage: "exclamationmark.octagon").foregroundStyle(.red)
                FindingsList(findings: result.findings)
            case .refused(let result)?:
                Label("The silo refused it", systemImage: "exclamationmark.octagon").foregroundStyle(.red)
                FindingsList(findings: result.findings)
            case nil:
                EmptyView()
            }
            if let failure = current.failure {
                Label(failure, systemImage: "exclamationmark.octagon").foregroundStyle(.red).font(.caption)
                    .textSelection(.enabled)
            }
        }
    }
}
#endif

#if canImport(SwiftUI)
/// A reading against TMDb as it goes: the step it is on, and how many of the step's questions are
/// answered when it asks several.
struct ReadingProgress: View {
    let progress: AdminConsole.TMDbProgress

    var body: some View {
        if let total = progress.total, total > 0 {
            ProgressView(value: Double(progress.done), total: Double(total)) {
                Text(progress.step).font(.caption)
            } currentValueLabel: {
                Text("\(progress.done) of \(total)").font(.caption2).monospacedDigit()
            }
        } else {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(progress.step).font(.caption)
            }
        }
    }
}

/// A held container's differences from TMDb, each with a tick and none ticked to begin with: its fields,
/// the ids TMDb holds that it lacks, what TMDb has that nothing covers, an order that differs, artwork,
/// and a series' specials, the declined ones collapsed. What the library holds and TMDb lacks is shown,
/// and never offered for removal. Taking makes one edit draft of the container, opened in the editor;
/// what else it makes is listed and stored only when the operator says.
struct DifferencesSheet: View {
    let comparing: ConsoleModel.Comparing
    let model: ConsoleModel
    @Environment(\.dismiss) private var dismiss

    private var current: ConsoleModel.Comparing { model.comparing ?? comparing }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(current.comparison?.title ?? current.key.container) against TMDb").font(.title3.bold())
                TMDbMark()
                Spacer()
            }
            if let progress = current.progress { ReadingProgress(progress: progress) }
            if let comparison = current.comparison {
                if !comparison.reading.isEmpty {
                    Text("Read \(comparison.reading).").font(.caption).foregroundStyle(.secondary)
                }
                ScrollView { differences(comparison) }
                if let taking = current.taking { takingSummary(taking) }
            }
            if let failure = current.failure {
                Label(failure, systemImage: "exclamationmark.octagon").foregroundStyle(.red).font(.caption)
                    .textSelection(.enabled)
            }
            Text(TMDb.notice).font(.caption2).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Close") {
                    model.comparing = nil
                    dismiss()
                }
                if current.taking == nil {
                    Button("Take the Ticked") { Task { await model.takeDifferences() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(current.chosen.isEmpty || current.progress != nil)
                }
            }
        }
        .padding()
        .frame(minWidth: 620, minHeight: 520)
    }

    @ViewBuilder
    private func differences(_ comparison: AdminConsole.TMDbComparison) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            group("Fields", comparison.differences.filter(\.isField), comparison)
            group("References", comparison.differences.filter(\.isReference), comparison)
            group("Children", comparison.differences.filter(\.isChild), comparison)
            group("Order", comparison.differences.filter(\.isOrder), comparison)
            group("Artwork", comparison.differences.filter(\.isArtwork), comparison)
            let specials = comparison.differences.compactMap {
                if case .special(let special) = $0 { special } else { nil }
            }
            if !specials.isEmpty {
                GroupBox("Unassigned specials") {
                    ForEach(specials) { special in specialRow(special, comparison) }
                }
            }
            if !comparison.declined.isEmpty {
                DisclosureGroup("Declined: \(comparison.declined.count)") {
                    ForEach(comparison.declined) { special in specialRow(special, comparison) }
                }
            }
            if !comparison.heldOnly.isEmpty {
                GroupBox("Held here, and nothing at TMDb: nothing is offered for removal") {
                    ForEach(comparison.heldOnly, id: \.self) { Text($0).font(.caption) }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if comparison.differences.isEmpty, current.progress == nil {
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
                        Toggle(isOn: tick(difference.id)) { label(difference, comparison) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                // Ticks the group's every difference or none, and shows as mixed while some are ticked.
                Toggle(sources: differences.map { tick($0.id) }, isOn: \.self) { Text(title) }
            }
        }
    }

    private func tick(_ id: String) -> Binding<Bool> {
        Binding(
            get: { current.chosen.contains(id) },
            set: { on in
                if on { model.comparing?.chosen.insert(id) } else { model.comparing?.chosen.remove(id) }
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
        case .season(let season): Text("\(season.name), drafted from TMDb beneath this")
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

    @ViewBuilder
    private func specialRow(_ special: Special, _ comparison: AdminConsole.TMDbComparison) -> some View {
        HStack {
            VStack(alignment: .leading) {
                HStack(spacing: 4) {
                    Text(special.episode.title)
                    TMDbMark()
                }
                if let placement = current.placements[special.id] {
                    Text(describe(placement)).font(.caption).foregroundStyle(.green)
                } else if let suggestion = comparison.suggestions[special.id] {
                    Text("Suggested: \(suggestion.reason)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if current.placements[special.id] == nil, let placement = comparison.suggestions[special.id]?.placement {
                Button("Take") { place(special, placement) }
            }
            Menu("Place") {
                Button("As an entry of \(comparison.title)") { place(special, .entry(in: comparison.container)) }
                Menu("As an extra of \(comparison.title)") {
                    ForEach(EntryType.extraTypes, id: \.self) { type in
                        Button(type.rawValue) { place(special, .extra(of: comparison.container, type: type.rawValue)) }
                    }
                }
                Button("Declined") { place(special, .declined) }
                Button("Unassigned") {
                    model.comparing?.placements[special.id] = nil
                    model.comparing?.chosen.remove("special:\(special.id)")
                }
            }
            .fixedSize()
        }
    }

    private func place(_ special: Special, _ placement: SpecialPlacement) {
        model.comparing?.placements[special.id] = placement
        model.comparing?.chosen.insert("special:\(special.id)")
    }

    private func describe(_ placement: SpecialPlacement) -> String {
        switch placement {
        case .entry: "an entry"
        case .extra(_, let type): "a \(type) extra"
        case .child(_, _, let type): "a \(type) of its own"
        case .duplicate(let home, let item, let library, _, _): "the same as \(home)#\(item) in \(library)"
        case .breakout(let id, _, _): "in breakout \(id)"
        case .declined: "declined"
        }
    }

    @ViewBuilder
    private func takingSummary(_ taking: AdminConsole.TMDbTaking) -> some View {
        GroupBox("Taken") {
            VStack(alignment: .leading, spacing: 4) {
                if taking.draft != nil {
                    Text("The container's own changes are a draft, open in the editor to review and store.").font(
                        .caption
                    )
                }
                ForEach(taking.described, id: \.self) { Text("• \($0)").font(.caption) }
                ForEach(taking.seasons, id: \.self) { number in
                    Button("Draft Season \(number) from TMDb…") {
                        Task {
                            guard let tmdb = current.comparison?.series else { return }
                            let finding = ConsoleModel.FindingInTMDb(
                                silo: current.silo,
                                library: current.key.library,
                                series: (current.key.container, current.comparison?.title ?? "", tmdb)
                            )
                            try? await model.startSeasonDraft(number, for: finding)
                        }
                    }
                }
                if !taking.heldEdits.isEmpty || !taking.breakouts.isEmpty || !taking.artwork.isEmpty {
                    HStack {
                        if current.stored {
                            Label("Stored", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                        } else {
                            Button("Store These") { Task { await model.storeTaking() } }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension AdminConsole.TMDbDifference {
    var isField: Bool {
        switch self {
        case .title, .year, .outline: true
        default: false
        }
    }

    var isReference: Bool {
        if case .reference = self { return true }
        return false
    }

    var isChild: Bool {
        switch self {
        case .episode, .season: true
        default: false
        }
    }

    var isOrder: Bool {
        if case .order = self { return true }
        return false
    }

    var isArtwork: Bool {
        if case .artwork = self { return true }
        return false
    }
}
#endif
