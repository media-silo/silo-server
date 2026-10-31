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
/// chooses and walked from the draft; or one of a held series' seasons, chosen in the series' walk. A
/// record smddb holds is not drafted, and the sheet says what holds it; one the library holds is walked
/// as it is held.
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
            if let series = finding.series {
                Text(
                    "\(series.title) is walked against TMDb with the season chosen among its missing children, drafted beneath it once its stop is confirmed."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Text(TMDb.notice).font(.caption2).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button(finding.series == nil ? "Draft" : "Walk the Series") { Task { await draft() } }
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
            if finding.series != nil, let number = seasons.first,
                let season = series?.seasons.first(where: { $0.number == number })
            {
                await model.startSeasonDraft(season, for: finding)
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
