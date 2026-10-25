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
                        Text("\(attribution.subject.rawValue) from \(attribution.provider.title) \(attribution.value)")
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
    /// What is being made for a special, asked as it is placed.
    @State private var naming: SpecialNaming?

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
        .sheet(item: $naming) { naming in
            SpecialNamingSheet(naming: naming) { title, listed in place(naming, titled: title, listed: listed) }
        }
    }

    /// A special placed as what was named for it: another version of a container, or of one of its
    /// items, titled as asked, or a new breakout of that title.
    private func place(_ naming: SpecialNaming, titled title: Title, listed: Bool) {
        switch naming {
        case .edition(let special, let container, _):
            model.updateTree { $0.place(special.id, .edition(of: container, title: title.rawValue)) }
        case .version(let special, let container, let item, _):
            model.updateTree { $0.place(special.id, .version(of: container, item: item, title: title.rawValue)) }
        case .companion(let special, let container):
            Task {
                guard let id = try? await model.provisionalID() else { return }
                var breakout = Container(id: id, type: .series, title: title, listed: listed)
                breakout.sequences = [Sequence(id: "episodes", items: [])]
                model.updateTree {
                    $0.place(special.id, .breakout(id.value, from: container, asExtra: true), breakout: breakout)
                }
            }
        }
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
                        if !tree.isMade(container.id.value) {
                            Text("left out").font(.caption).foregroundStyle(.secondary)
                        }
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
        if let child = entry.childContainer {
            Text("↳ \(tree.container(child.value)?.displayTitle ?? child.value)").foregroundStyle(.secondary)
        } else {
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

    @ViewBuilder
    private var detail: some View {
        ScrollView {
            // Lazy, to pin the children's heading and actions while their list scrolls beneath them.
            LazyVStack(alignment: .leading, spacing: 8, pinnedViews: [.sectionHeaders]) {
                detailContent
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if let selected, let container = tree.container(selected) {
            EntryGrouping(
                tree: tree,
                parent: selected,
                update: { model.updateTree($0) },
                provisionalID: { try? await model.provisionalID() }
            )
            AttributionsLine(attributions: tree.attributions[selected] ?? []) { subject in
                model.updateTree { $0.removeAttribution(of: subject, from: selected) }
            }
            ContainerForm(container: container) { changed in model.updateTree { $0.set(changed) } }
        } else {
            ContentUnavailableView(
                "Nothing Chosen",
                systemImage: "square.stack.3d.up",
                description: Text("Choose a container to shape it and group its entries.")
            )
        }
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
                    alternativesMenu(special, of: container)
                    breakoutMenu(special, from: container)
                }
            }
            Divider()
            Button("Declined") { model.updateTree { $0.place(special.id, .declined) } }
            Button("Unassigned") { model.updateTree { $0.place(special.id, nil) } }
        }
        .fixedSize()
    }

    /// Another way to play a container: a new edition of it, or a version of one of its items, each
    /// titled as it is placed.
    @ViewBuilder
    private func alternativesMenu(_ special: Special, of container: Container) -> some View {
        let id = container.id.value
        Button("As Another Version of \(container.displayTitle)…") {
            naming = .edition(special, of: id, container.displayTitle)
        }
        Menu("In Place of One of Its Items, as Another Version") {
            ForEach(container.sequences.flatMap(\.items).compactMap(\.id), id: \.self) { item in
                Button("\(entryTitle(item, in: container))…") {
                    naming = .version(special, of: id, item: item.value, entryTitle(item, in: container))
                }
            }
        }
    }

    private func entryTitle(_ item: ItemID, in container: Container) -> String {
        let entry = container.sequences.flatMap(\.items).first { $0.id == item }
        let ref = entry?.externalRefs.first { $0.provider == .tmdb }
        return entry?.title ?? ref.flatMap { tree.episodeTitles[$0.value] } ?? item.value
    }

    @ViewBuilder
    private func breakoutMenu(_ special: Special, from container: Container) -> some View {
        Menu("Into a breakout, referred to from its extras") {
            ForEach(tree.breakouts.keys.sorted(), id: \.self) { id in
                Button(tree.container(id)?.displayTitle ?? id) {
                    model.updateTree { $0.place(special.id, .breakout(id, from: container.id.value, asExtra: true)) }
                }
            }
            ForEach(current.companions) { companion in
                Button("\(companion.displayTitle)\(companion.listed ? "" : " (unlisted)"), held already") {
                    model.updateTree {
                        $0.place(special.id, .breakout(companion.id, from: container.id.value, asExtra: true))
                    }
                }
            }
            Divider()
            Button("A New One…") { naming = .companion(special, from: container.id.value) }
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
        case .edition(let id, let alternative): return "a new edition of \(title(id)), \(alternative)"
        case .version(let id, let item, let alternative): return "a version of \(item) of \(title(id)), \(alternative)"
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
        case .episode, .season, .heldSeason: true
        default: false
        }
    }

    /// A child the library holds, shown among the children and never chosen.
    var isHeld: Bool {
        if case .heldSeason = self { return true }
        return false
    }

    var isUnmatched: Bool {
        if case .unmatchedSeason = self { return true }
        return false
    }

    var isEpisode: Bool {
        if case .episode = self { return true }
        return false
    }

    var isOrder: Bool {
        if case .order = self { return true }
        return false
    }

    var isArtwork: Bool {
        if case .artwork = self { return true }
        return false
    }

    var isSpecial: Bool {
        if case .special = self { return true }
        return false
    }
}
#endif
