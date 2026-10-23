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

    var tmdbLanguage: String {
        get { tmdbState.language }
        set { tmdbState.language = newValue }
    }
    var tmdbProblem: String? {
        get { tmdbState.problem }
        set { tmdbState.problem = newValue }
    }
    var findingInTMDb: FindingInTMDb? {
        get { tmdbState.finding }
        set { tmdbState.finding = newValue }
    }
    var shapingTree: ShapingTree? {
        get { tmdbState.shaping }
        set { tmdbState.shaping = newValue }
    }
    var comparing: Comparing? {
        get { tmdbState.comparing }
        set { tmdbState.comparing = newValue }
    }

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
            findingInTMDb = nil
            await compareWithTMDb(
                ContainerKey(silo: finding.silo.id, library: finding.library, container: summary.id),
                on: finding.silo
            )
            return nil
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

    // MARK: Differences

    /// Opens a held container's differences from TMDb, read now.
    func compareWithTMDb(_ key: ContainerKey, on silo: AdminConsole.Silo) async {
        comparing = Comparing(silo: silo, key: key)
        guard let database, let tmdb else {
            comparing?.failure = tmdbProblem ?? smddbProblem ?? "TMDb or smddb's clone cannot be read."
            return
        }
        do {
            let comparison = try await console.compare(
                key.container,
                in: key.library,
                of: silo,
                from: database,
                tmdb: tmdb
            )
            comparing?.comparison = comparison
        } catch let unreadable as AdminConsole.NoTMDbReading {
            comparing?.failure = unreadable.reason
        } catch {
            comparing?.failure = describe(error)
        }
    }

    /// Takes the chosen differences: the container's own as an edit draft, opened in the editor to be
    /// reviewed and stored; the rest gathered and listed, to be stored when the operator confirms.
    func takeDifferences() async {
        guard let current = comparing, let comparison = current.comparison else { return }
        do {
            let taking = try await console.take(
                current.chosen,
                placements: current.placements,
                breakouts: [:],
                from: comparison,
                of: current.silo
            )
            comparing?.taking = taking
            if let draft = taking.draft { open(draft, for: current.silo) }
        } catch {
            comparing?.failure = describe(error)
        }
    }

    /// Stores what taking gathered beyond the container's draft, and reads the container again.
    func storeTaking() async {
        guard let current = comparing, let taking = current.taking, let tmdb else { return }
        do {
            try await console.store(
                taking,
                in: current.key.library,
                for: current.key.container,
                of: current.silo,
                tmdb: tmdb
            )
            comparing?.stored = true
            await open(current.key)
        } catch {
            comparing?.failure = describe(error)
        }
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
