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

/// Finding an item at Wikidata to draft from: a film, a series or a collection for a library, the most
/// widely known first, told apart by Wikidata's description, and walked from a draft of all of it, a
/// series with every season, where what is not wanted is left out; or one of a held series' seasons,
/// chosen in the series' walk. An item smddb holds is
/// not drafted, and the sheet says what holds it; one the library holds is walked as it is held. Its
/// facts are Wikidata's; its outline and artwork are TMDb's, when this Mac has a token for TMDb.
struct FindInWikidataSheet: View {
    let finding: ConsoleModel.FindingInWikidata
    let model: ConsoleModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [Wikidata.SearchResult] = []
    @State private var picked: Wikidata.SearchResult?
    @State private var series: Wikidata.Series?
    @State private var seasons: Set<String> = []
    @State private var message: String?
    @State private var working = false
    @State private var searching = false
    @State private var readingSeries = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(
                finding.series.map { "A season of \($0.title) from Wikidata" }
                    ?? "Draft into \(finding.library) from Wikidata"
            )
            .font(.title3.bold())
            if finding.series == nil {
                HStack {
                    TextField("Title", text: $query).onSubmit { Task { await search() } }
                    Button("Search") { Task { await search() } }
                        .disabled(searching || query.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                List(results, id: \.id, selection: Binding(get: { picked?.id }, set: { pick($0) })) { result in
                    HStack {
                        VStack(alignment: .leading) {
                            HStack {
                                Text(result.title)
                                if let year = result.year { Text(String(year)).foregroundStyle(.secondary) }
                            }
                            if let description = result.description {
                                Text(description).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(result.kind.rawValue).font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(result.id)
                }
                .frame(minHeight: 160)
                .overlay {
                    if searching {
                        ProgressView("Searching Wikidata…")
                            .padding()
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            if let series {
                seasonChoice(series)
            } else if readingSeries {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Reading the series' seasons from Wikidata…").font(.caption)
                }
            }
            if let message {
                Label(message, systemImage: "info.circle").font(.caption).textSelection(.enabled)
            }
            if let series = finding.series {
                Text(
                    "\(series.title) is walked with the season chosen among its missing children, drafted beneath it once its stop is confirmed."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            if model.tmdb == nil {
                Text("With no TMDb token, the draft holds Wikidata's facts and no outline or artwork.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                if working {
                    ProgressView().controlSize(.small)
                }
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
            readingSeries = true
            defer { readingSeries = false }
            series = try? await model.wikidataSeries(held.wikidata)
        }
    }

    /// The held series' seasons, one of them to be drafted.
    private func seasonChoice(_ series: Wikidata.Series) -> some View {
        GroupBox("The season to draft") {
            ScrollView {
                VStack(alignment: .leading) {
                    ForEach(series.seasons, id: \.id) { season in
                        Toggle(
                            season.title,
                            isOn: Binding(
                                get: { seasons.contains(season.id) },
                                set: { seasons = $0 ? [season.id] : [] }
                            )
                        )
                    }
                }
            }
            .frame(maxHeight: 140)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func search() async {
        guard !searching else { return }
        searching = true
        defer { searching = false }
        do {
            results = try await model.searchWikidata(query)
            message = results.isEmpty ? "Wikidata finds no film, series or collection by that title." : nil
        } catch {
            message = model.describe(error)
        }
    }

    private func pick(_ id: String?) {
        picked = results.first { $0.id == id }
        message = nil
    }

    private func draft() async {
        working = true
        defer { working = false }
        do {
            if finding.series != nil, let id = seasons.first, let season = series?.seasons.first(where: { $0.id == id })
            {
                await model.startSeasonDraft(season, for: finding)
            } else if let picked {
                message = try await model.startDraft(of: Wikidata.Item(picked.kind, picked.id), for: finding)
            }
        } catch {
            message = model.describe(error)
        }
    }
}
#endif

#if canImport(SwiftUI)
/// A reading as it goes: the step it is on, and how many of the step's questions are
/// answered when it asks several.
struct ReadingProgress: View {
    let progress: AdminConsole.StepProgress

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

extension ReviewWalk.Difference {
    /// A container's own field: its title, year, outline, first date, cast, or directors and writers.
    var isField: Bool {
        switch self {
        case .title, .year, .outline, .staleOutline, .premiered, .cast, .crew: true
        default: false
        }
    }

    var isReference: Bool {
        if case .reference = self { return true }
        return false
    }

    var isChild: Bool {
        switch self {
        case .episode, .child, .heldChild: true
        default: false
        }
    }

    /// A child the library holds, shown among the children and never chosen.
    var isHeld: Bool {
        if case .heldChild = self { return true }
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
        switch self {
        case .artwork, .staleArtwork: true
        default: false
        }
    }

    var isSpecial: Bool {
        if case .special = self { return true }
        return false
    }
}
#endif
