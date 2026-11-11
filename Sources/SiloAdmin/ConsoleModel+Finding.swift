// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

#if canImport(SwiftUI)
import Foundation
import SiloAdminKit
import SiloClient
import SmdKit
import SmdSidecar

// MARK: - Finding in Wikidata, and TMDb's content

extension ConsoleModel {
    static let tmdbLanguageKey = "tmdbLanguage"

    var tmdbLanguage: String {
        get { tmdbState.language }
        set { tmdbState.language = newValue }
    }
    var tmdbProblem: String? {
        get { tmdbState.problem }
        set { tmdbState.problem = newValue }
    }
    var findingInWikidata: FindingInWikidata? {
        get { tmdbState.finding }
        set { tmdbState.finding = newValue }
    }
    /// This Mac's language and region, as TMDb and Wikidata name a language: `en-GB`.
    static var macLanguage: String {
        guard let code = Locale.current.language.languageCode?.identifier else { return "en-US" }
        return Locale.current.region.map { "\(code)-\($0.identifier)" } ?? code
    }

    /// This Mac's keychain where it has one, memory otherwise.
    nonisolated static func keychain() -> any PasskeyStore {
        #if canImport(Security)
        KeychainPasskeyStore()
        #else
        InMemoryPasskeyStore()
        #endif
    }

    /// The read access token, as this Mac's keychain keeps it.
    var tmdbToken: String? { tokens.passkey(for: TMDb.tokenAccount) }

    /// TMDb as the console reads it, when a token is given and TMDb accepted it.
    var tmdb: (any TMDbSource)? {
        guard tmdbProblem == nil, let token = tmdbToken, !token.isEmpty else { return nil }
        return TMDbClient(token: token, language: tmdbLanguage)
    }

    /// Keeps the token in the keychain, or removes it for an empty one, and asks TMDb whether it holds.
    func setTMDbToken(_ token: String) async {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            tokens.remove(for: TMDb.tokenAccount)
        } else {
            tokens.store(trimmed, for: TMDb.tokenAccount)
        }
        await checkTMDb()
    }

    func setTMDbLanguage(_ language: String) {
        let trimmed = language.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        tmdbLanguage = trimmed
        UserDefaults.standard.set(trimmed, forKey: Self.tmdbLanguageKey)
    }

    /// Asks TMDb whether the token holds, and says why not when it does not.
    func checkTMDb() async {
        let language = tmdbLanguage
        tmdbProblem = await AdminConsole.tmdbStanding(token: tmdbToken) { TMDbClient(token: $0, language: language) }?
            .reason
    }

    /// Wikidata as the console reads it, in the language the settings name. It needs no key.
    var wikidata: any WikidataSource { WikidataClient(language: tmdbLanguage) }

    func searchWikidata(_ query: String) async throws -> [Wikidata.SearchResult] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return try await wikidata.search(query)
    }

    /// A series as Wikidata has it, for choosing its seasons to draft it by.
    func wikidataSeries(_ id: String) async throws -> Wikidata.Series {
        try await wikidata.series(id)
    }

    /// Starts a walk of an item for the library being found for, rooted at a draft of it. An item smddb
    /// holds is not drafted, and what holds it is said instead; one the library holds is walked as it is
    /// held; a walk this Mac kept of the item is offered to be resumed, or started again. With no TMDb,
    /// the draft holds Wikidata's facts and no content.
    func startDraft(
        of item: Wikidata.Item,
        for finding: FindingInWikidata,
        again: Bool = false
    ) async throws -> String? {
        guard let database else { return "smddb's clone cannot be read." }
        let redraft = Walking.Redraft(item: item, finding: finding)
        if !again, let kept = console.reviewWalks.walk(drafting: item, in: finding.library, of: finding.silo.id) {
            findingInWikidata = nil
            walking = Walking(
                silo: finding.silo,
                walk: kept,
                open: kept.next ?? kept.root,
                resuming: true,
                redraft: redraft
            )
            return nil
        }
        switch try await console.startWalk(
            drafting: item,
            into: finding.library,
            of: finding.silo,
            from: database,
            wikidata: wikidata,
            tmdb: tmdb
        ) {
        case .importFromSmddb(let container):
            return
                "smddb holds this as \(container.displayTitle), so it is imported from smddb rather than drafted: choose Import from smddb… and find it there."
        case .held(let summary):
            findingInWikidata = nil
            await review(
                ContainerKey(silo: finding.silo.id, library: finding.library, container: summary.id),
                on: finding.silo
            )
            return nil
        case .walk(let walk):
            findingInWikidata = nil
            await openDraftWalk(walk, on: finding.silo, redraft: redraft)
            return nil
        }
    }

    /// Walks the held series being found for, the season of Wikidata's chosen as a missing child to be
    /// drafted beneath it once the series' stop is confirmed.
    func startSeasonDraft(_ season: Wikidata.Summary, for finding: FindingInWikidata) async {
        guard let series = finding.series else { return }
        findingInWikidata = nil
        await review(
            ContainerKey(silo: finding.silo.id, library: finding.library, container: series.container),
            on: finding.silo,
            choosing: "child:\(season.id)"
        )
    }

    /// TMDb's images for a container's record, for its artwork kinds to be chosen from.
    func tmdbImages(of record: TMDb.Record) async -> TMDb.Images {
        (try? await tmdb?.images(of: record)) ?? TMDb.Images()
    }

    /// Puts one of TMDb's images as a kind of a container's artwork, credited to the record.
    func putTMDbArtwork(_ path: String, as kind: String, from record: TMDb.Record, of key: ContainerKey) async {
        guard let tmdb, let silo = silos.first(where: { $0.id == key.silo }) else { return }
        do {
            let image = try await tmdb.image(at: path)
            try await console.putArtwork(
                image,
                as: kind,
                of: key.container,
                in: key.library,
                on: silo,
                attributedTo: record.ref
            )
            await open(key)
        } catch let refused as AdminConsole.SettingsRefused {
            refusal = .settingsRefused(refused.reason)
        } catch {
            refusal = .settingsRefused(describe(error))
        }
    }

    /// An id for a container the tree gains, from smddb's client.
    func provisionalID() async throws -> ContainerID? {
        try await database?.provisionalID()
    }
}
#endif
