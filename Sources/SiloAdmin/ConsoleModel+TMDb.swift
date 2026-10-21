// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

#if canImport(SwiftUI)
import Foundation
import SiloAdminKit
import SiloClient
import SmdKit
import SmdSidecar

// MARK: - TMDb

extension ConsoleModel {
    static let tmdbLanguageKey = "tmdbLanguage"

    /// This Mac's language and region, as TMDb names a language: `en-GB`.
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

    func searchTMDb(_ query: String) async throws -> [TMDb.SearchResult] {
        guard let tmdb, !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return try await tmdb.search(query)
    }

    /// A series as TMDb has it, for choosing its seasons or an episode group to draft it by.
    func tmdbSeries(_ id: Int) async throws -> TMDb.Series? {
        try await tmdb?.series(id)
    }

    /// Starts a draft of a record for the library being found for. A record smddb or the library holds
    /// is not drafted, and what holds it is said instead; a draft opens to be shaped.
    func startTMDbDraft(
        of record: TMDb.Record,
        shape: AdminConsole.TMDbShape,
        for finding: FindingInTMDb
    ) async throws -> String? {
        guard let database, let tmdb else { return "TMDb or smddb's clone cannot be read." }
        switch try await console.startDraft(
            of: record,
            shape: shape,
            into: finding.library,
            of: finding.silo,
            from: database,
            tmdb: tmdb
        ) {
        case .importFromSmddb(let container):
            return
                "smddb holds this as \(container.displayTitle), so it is imported from smddb rather than drafted: choose Import from smddb… and find it there."
        case .held(let summary):
            return "\(finding.library) holds this already, as \(summary.displayTitle)."
        case .draft(let tree):
            findingInTMDb = nil
            await openShaping(tree, on: finding.silo)
            return nil
        }
    }

    /// Starts a draft of one of a held series' seasons beneath it.
    func startSeasonDraft(_ number: Int, for finding: FindingInTMDb) async throws {
        guard let database, let tmdb, let series = finding.series else { return }
        let tree = try await console.startDraft(
            ofSeason: number,
            of: series.tmdb,
            beneath: series.container,
            into: finding.library,
            of: finding.silo,
            from: database,
            tmdb: tmdb
        )
        findingInTMDb = nil
        await openShaping(tree, on: finding.silo)
    }

    /// Opens a draft from TMDb to be shaped, with its specials' suggestions.
    func openShaping(_ tree: TMDbTree, on silo: AdminConsole.Silo) async {
        shapingTree = ShapingTree(silo: silo, tree: tree)
        await suggestSpecials()
        await checkTree()
    }

    /// The tree as the operator shaped it, kept on this Mac, and checked with the silo again.
    func updateTree(_ change: (inout TMDbTree) -> Void) {
        guard var shaping = shapingTree else { return }
        change(&shaping.tree)
        shaping.outcome = nil
        shaping.failure = nil
        try? console.tmdbDrafts.save(shaping.tree, for: shaping.silo.id)
        shapingTree = shaping
        Task { await checkTree() }
    }

    func suggestSpecials() async {
        guard let shaping = shapingTree, !shaping.tree.specials.isEmpty, let database, let tmdb else { return }
        do {
            let (tree, suggestions) = try await console.suggest(
                for: shaping.tree,
                of: shaping.silo,
                from: database,
                tmdb: tmdb
            )
            shapingTree?.tree = tree
            shapingTree?.suggestions = suggestions
        } catch {
            shapingTree?.failure = describe(error)
        }
    }

    func checkTree() async {
        guard let shaping = shapingTree else { return }
        do {
            shapingTree?.check = try await console.check(shaping.tree, of: shaping.silo)
        } catch {
            shapingTree?.failure = describe(error)
        }
    }

    /// Makes the tree. Made, the library's containers are read again.
    func createTree() async {
        guard let shaping = shapingTree else { return }
        do {
            let outcome = try await console.create(shaping.tree, of: shaping.silo)
            shapingTree?.outcome = outcome
            if case .created = outcome { await loadContainers(for: shaping.silo) }
        } catch {
            shapingTree?.failure = describe(error)
        }
    }

    /// Discards the draft from TMDb: off this Mac, and the sheet closed.
    func discardTree() {
        guard let shaping = shapingTree else { return }
        try? console.tmdbDrafts.remove(shaping.tree.id, of: shaping.silo.id)
        shapingTree = nil
    }

    /// An id for a container the tree gains, from smddb's client.
    func provisionalID() async throws -> ContainerID? {
        try await database?.provisionalID()
    }
}
#endif
