// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import SiloClient
import SiloKit

// MARK: - Rulesets

extension AdminConsole {
    /// A ruleset opened: its summary and branches, and one version's document as the silo stored it,
    /// with the silo's reading of it.
    public struct OpenedRuleset: Hashable, Sendable {
        public var summary: SiloClient.RulesetSummary
        public var branches: [SiloClient.Branch]
        public var document: SiloClient.RulesetDocument
    }

    /// One library's out-of-date presentations, as the background check has found them so far.
    public struct LibraryOutOfDate: Hashable, Sendable {
        public var library: String
        public var report: SiloClient.OutOfDateReport
    }

    /// The rulesets a with-access silo holds, each with every version.
    public func rulesets(of silo: Silo) async throws -> [SiloClient.RulesetSummary] {
        try await withOperator(silo) { try await $0.rulesets() }
    }

    /// Opens a ruleset at a version, or at its standard's head when none is named: the version the
    /// library's applications take unless they name a branch.
    public func open(ruleset name: String, version: Int? = nil, of silo: Silo) async throws -> OpenedRuleset {
        try await withOperator(silo) { client in
            guard let summary = try await client.rulesets().first(where: { $0.name == name }) else {
                throw SiloClientError.status(404, "no ruleset \(name)")
            }
            let branches = try await client.branches(of: name)
            let document = try await client.ruleset(
                named: name,
                version: version ?? summary.standard ?? summary.version
            )
            return OpenedRuleset(summary: summary, branches: branches, document: document)
        }
    }

    /// Each library's out-of-date presentations, in the order the silo lists its libraries.
    public func outOfDate(of silo: Silo) async throws -> [LibraryOutOfDate] {
        try await withOperator(silo) { client in
            var reports: [LibraryOutOfDate] = []
            for library in try await client.settings().editable.libraries {
                reports.append(
                    LibraryOutOfDate(library: library.id, report: try await client.outOfDate(in: library.id))
                )
            }
            return reports
        }
    }

    // MARK: - Changing rulesets

    /// What the silo made of a draft's text: its reading, or its refusal in its own words.
    public enum DraftCheck: Hashable, Sendable {
        case reading(SiloClient.RulesetReading)
        case refused(String)
    }

    /// Checks a draft with the silo as a store would, storing nothing.
    public func check(_ draft: Draft, of silo: Silo) async throws -> DraftCheck {
        do {
            return .reading(try await withOperator(silo) { try await $0.check(ruleset: draft.text, as: draft.ruleset) })
        } catch SiloClientError.status(400, let body) {
            return .refused(Self.detail(body))
        }
    }

    /// What a draft would put out of date were it stored on its base's branch. A new ruleset made
    /// nothing, so it puts nothing out of date.
    public func impact(of draft: Draft, of silo: Silo) async throws -> [SiloClient.OutOfDatePresentation] {
        guard let base = draft.base else { return [] }
        return try await withOperator(silo) {
            try await $0.impact(ofDraft: draft.text, basedOn: base, of: draft.ruleset)
        }
    }

    /// Where a draft is stored.
    public enum StoreTarget: Hashable, Sendable {
        /// Its base's branch, or the standard for a new ruleset.
        case baseBranch
        /// Another branch of the ruleset, at that branch's head.
        case branch(String)
        /// A branch started from the base, which must be on the standard.
        case newBranch(String)
    }

    /// How a store ended: the version the silo gave the draft, which ends it; or another version
    /// that landed on the branch first, which keeps it, for the operator to re-base or discard.
    public enum StoreOutcome: Hashable, Sendable {
        case stored(SiloClient.RulesetDocument)
        case landedFirst(SiloClient.RulesetDocument)
    }

    /// The silo refused the store for something other than a version landing first, in its words.
    public struct StoreRefused: Error, Hashable {
        public var reason: String
    }

    /// Stores a draft, naming as `basedOn` the head of the branch it goes to as the draft knows it:
    /// its base, on its base's branch; another branch's head as the silo lists it; or the base, for a
    /// branch started from it. The console never merges: a version that landed first is fetched and
    /// handed back with the draft kept.
    public func store(_ draft: Draft, to target: StoreTarget, of silo: Silo) async throws -> StoreOutcome {
        try await withOperator(silo) { client in
            var branch: String?
            var basedOn: Int
            switch target {
            case .baseBranch:
                branch = draft.baseBranch
                basedOn = draft.base ?? 0
            case .branch(let name):
                guard let head = try await client.branches(of: draft.ruleset).first(where: { $0.name == name })?.head
                else {
                    throw StoreRefused(reason: "\(draft.ruleset) has no branch \(name)")
                }
                branch = name
                basedOn = head
            case .newBranch(let name):
                guard let base = draft.base, draft.baseBranch == nil || draft.baseBranch == "standard" else {
                    throw StoreRefused(reason: "a branch is started from a version of the standard")
                }
                do {
                    _ = try await client.startBranch(name, of: draft.ruleset, from: base)
                } catch SiloClientError.status(let status, let body) where status == 400 || status == 409 {
                    throw StoreRefused(reason: Self.detail(body))
                }
                branch = name
                basedOn = base
            }
            do {
                return .stored(
                    try await client.store(
                        ruleset: draft.text,
                        as: draft.ruleset,
                        branch: branch,
                        upToDateWith: draft.upToDateWith,
                        basedOn: basedOn
                    )
                )
            } catch SiloClientError.status(409, let body) {
                let line = branch ?? "standard"
                guard let head = try await client.branches(of: draft.ruleset).first(where: { $0.name == line })?.head,
                    head != basedOn
                else {
                    throw StoreRefused(reason: Self.detail(body))
                }
                return .landedFirst(try await client.ruleset(named: draft.ruleset, version: head))
            } catch SiloClientError.status(400, let body) {
                throw StoreRefused(reason: Self.detail(body))
            }
        }
    }

    /// What promoting a branch would put out of date, as the silo resolves it on request.
    public func impact(
        ofBranch branch: String,
        of ruleset: String,
        on silo: Silo
    ) async throws -> [SiloClient.OutOfDatePresentation] {
        try await withOperator(silo) { try await $0.impact(ofBranch: branch, of: ruleset) }
    }

    /// A promotion the silo refused: the standard versions the branch has not taken in, and the
    /// branch's base they are read against.
    public struct PromotionRefused: Error, Hashable {
        public var reason: String
        public var notTakenIn: [SiloClient.RulesetDocument]
        public var base: SiloClient.RulesetDocument?
    }

    /// Promotes a branch, answering the standard's new version. A refusal names the standard versions
    /// the branch has not taken in, with their documents and its base's, so that each can be read for
    /// how it differs before a draft taking them in is stored on the branch.
    public func promote(_ branch: String, of ruleset: String, on silo: Silo) async throws -> SiloClient.RulesetDocument
    {
        try await withOperator(silo) { client in
            do {
                let promoted = try await client.promote(branch, of: ruleset)
                return try await client.ruleset(named: ruleset, version: promoted.version)
            } catch SiloClientError.status(409, let body) {
                let branches = try await client.branches(of: ruleset)
                let line = branches.first { $0.name == branch }
                let summary = try await client.rulesets().first { $0.name == ruleset }
                let since = line?.upToDateWith ?? line?.base ?? 0
                let missed = (summary?.versions ?? []).filter { $0.branch == "standard" && $0.version > since }.map(
                    \.version
                )
                var documents: [SiloClient.RulesetDocument] = []
                for version in missed { documents.append(try await client.ruleset(named: ruleset, version: version)) }
                let base = try await line?.base.asyncMap { try await client.ruleset(named: ruleset, version: $0) }
                throw PromotionRefused(reason: Self.detail(body), notTakenIn: documents, base: base)
            }
        }
    }
}

extension Optional {
    /// `map`, for a transform that suspends.
    fileprivate func asyncMap<T>(_ transform: (Wrapped) async throws -> T) async rethrows -> T? {
        guard let self else { return nil }
        return try await transform(self)
    }
}
