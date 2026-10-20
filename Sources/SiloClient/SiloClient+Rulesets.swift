// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloKit

// MARK: - Rulesets

extension SiloClient {
    /// A ruleset as the list gives it: its latest version, the standard's head, and every version.
    public struct RulesetSummary: Hashable, Sendable, Codable {
        public var name: String
        public var version: Int
        public var standard: Int?
        public var versions: [RulesetVersion]?
    }

    /// One version of a ruleset: its branch, its parent, and how many placed presentations a
    /// committed recipe naming it made.
    public struct RulesetVersion: Hashable, Sendable, Codable {
        public var version: Int
        public var branch: String
        public var parent: Int?
        public var presentations: Int
    }

    public struct RulesetDocument: Hashable, Sendable, Codable {
        public var name: String
        public var version: Int?
        public var branch: String?
        public var upToDateWith: Int?
        public var basedOn: Int?
        public var document: String
        /// The silo's reading of the document, on a read.
        public var reading: RulesetReading?
    }

    /// A ruleset as the silo reads it, named by where it is stored: what a console shows beside a
    /// version's document, and what it makes itself of a draft with the reader the silo runs.
    public struct RulesetReading: Hashable, Sendable, Codable {
        public var name: String
        /// In document order.
        public var rules: [RuleReading]
        public var outputs: [OutputPolicy]

        public init(name: String, rules: [RuleReading], outputs: [OutputPolicy]) {
            self.name = name
            self.rules = rules
            self.outputs = outputs
        }
    }

    /// One rule, by the name a recipe calls it by: its id, or `#n` for its position.
    public struct RuleReading: Hashable, Sendable, Codable {
        public var name: String
        public var scope: Scope
        public var conditions: [ConditionReading]
        public var action: Action

        public init(name: String, scope: Scope, conditions: [ConditionReading], action: Action) {
            self.name = name
            self.scope = scope
            self.conditions = conditions
            self.action = action
        }
    }

    /// A condition as the document writes it: the fact, the test's attribute and its value.
    public struct ConditionReading: Hashable, Sendable, Codable {
        public var fact: String
        public var test: String
        public var value: String

        public init(fact: String, test: String, value: String) {
            self.fact = fact
            self.test = test
            self.value = value
        }
    }

    /// A library's out-of-date presentations, as the background check has found them so far.
    public struct OutOfDateReport: Hashable, Sendable, Codable {
        public var presentations: [OutOfDatePresentation]
        /// Placed presentations not yet checked against the rules in force.
        public var pending: Int
        /// Presentations placed without a job, which have no recipe and are never checked.
        public var placedWithoutJob: Int
    }

    /// One presentation the rules in force would make differently, or not at all.
    public struct OutOfDatePresentation: Hashable, Sendable, Codable {
        public enum Outcome: String, Hashable, Sendable, Codable {
            case outOfDate, unresolvable
        }

        /// One source of the presentation's binding, with the copies nodes hold of it.
        public struct Source: Hashable, Sendable, Codable {
            public var id: String
            public var copies: [SourceRecord.Copy]
        }

        public var presentation: String?
        public var container: String?
        public var item: String?
        public var file: String?
        public var profile: String?
        public var recipe: String
        public var outcome: Outcome
        public var madeBy: CheckedStack
        public var checkedAgainst: CheckedStack
        public var changes: [StreamChange]
        public var reason: String?
        public var sources: [Source]
    }

    /// One of a ruleset's branches: where it started, its head, the standard version it takes in,
    /// and whether it has been promoted.
    public struct Branch: Hashable, Sendable, Codable {
        public var name: String
        public var base: Int?
        public var head: Int?
        public var upToDateWith: Int?
        public var closed: Bool
    }

    public func rulesets() async throws -> [RulesetSummary] {
        try await send("GET", "/v1/rulesets")
    }

    /// A library as the silo lists it: its standard, and how much it holds.
    public struct Library: Hashable, Sendable, Codable {
        public var id: String
        /// The library's standard, which an application naming no ruleset takes.
        public var ruleset: String?
        public var containers: Int
        public var presentations: Int
        /// False while the library's folder is missing, or its last walk found nothing where the
        /// index holds something: its containers stay browsable, and its media answer 503.
        public var available: Bool
    }

    /// What a library's last walk found: when it ran, whether the library was available, and what
    /// the walk did and found — or, when it was not applied, why. The silo walks each library by
    /// itself; nothing asks it to.
    public struct LastWalk: Hashable, Sendable, Codable {
        public struct Report: Hashable, Sendable, Codable {
            public var read: Int
            public var unchanged: Int
            public var removed: Int
            public var findings: [Finding]
        }

        public struct Finding: Hashable, Sendable, Codable {
            public enum Severity: String, Hashable, Sendable, Codable {
                case error, warning
            }

            public var severity: Severity
            /// Inside the library, when the finding is about one file.
            public var path: String?
            public var text: String
        }

        public var walkedAt: Date
        public var available: Bool
        public var report: Report
    }

    /// A library's last walk. Operator only, since its findings name paths inside the library.
    public func lastWalk(of library: String) async throws -> LastWalk {
        try await send("GET", "/v1/libraries/\(library)/scan")
    }

    private struct NewLibrary: Codable {
        var id: String
        var path: String
        var create: Bool?
    }

    /// Adds a library at a path on the silo's machine, within one of its library roots; the library
    /// as the silo answers, walked. With `create`, the folders missing from the path are made first,
    /// within a root that exists. A refusal is `status(403, _)` outside the roots, `status(409, _)`
    /// for a taken id and `status(422, _)` for a path that is not a folder, carrying the silo's reason.
    /// Operator only.
    public func addLibrary(id: String, path: String, create: Bool = false) async throws -> Library {
        try await send("POST", "/v1/libraries", body: NewLibrary(id: id, path: path, create: create ? true : nil))
    }

    /// What adding a library would find — each folder along the path and whether it is there, the
    /// root it lies within, the folders `create` would make — and the refusal the addition would meet,
    /// adding and making nothing.
    public struct LibraryCheck: Hashable, Sendable, Codable {
        public struct Component: Hashable, Sendable, Codable {
            public enum State: String, Hashable, Sendable, Codable {
                case folder, notAFolder, missing
            }

            public var path: String
            public var state: State
        }

        public struct Refusal: Hashable, Sendable, Codable {
            public var status: Int
            public var detail: String
        }

        public var path: String
        public var components: [Component]
        public var root: String?
        public var creates: [String]
        public var refusal: Refusal?
    }

    /// Asks what adding a library would find, and adds nothing. Operator only.
    public func checkLibrary(id: String, path: String, create: Bool = false) async throws -> LibraryCheck {
        try await send("POST", "/v1/libraries/check", body: NewLibrary(id: id, path: path, create: create ? true : nil))
    }

    /// Removes a library, leaving its files where they are. Refused with `status(409, _)`, naming the
    /// job, while a job not yet in a final state files into it. Operator only.
    public func removeLibrary(_ library: String) async throws {
        let (data, status) = try await request("DELETE", "/v1/libraries/\(library)", body: Nothing?.none)
        guard (200..<300).contains(status) else {
            throw SiloClientError.status(status, String(decoding: data, as: UTF8.self))
        }
    }

    public func libraries() async throws -> [Library] {
        try await send("GET", "/v1/libraries")
    }

    private struct LibraryRuleset: Codable { var ruleset: String? }

    /// Names a library's standard, or clears it with nil.
    public func setStandard(_ ruleset: String?, of library: String) async throws -> Library {
        try await send("PUT", "/v1/libraries/\(library)/ruleset", body: LibraryRuleset(ruleset: ruleset))
    }

    /// A library's out-of-date presentations, from the background check's records.
    public func outOfDate(in library: String) async throws -> OutOfDateReport {
        try await send("GET", "/v1/libraries/\(library)/out-of-date")
    }

    public func ruleset(named name: String, version: Int? = nil) async throws -> RulesetDocument {
        try await send("GET", "/v1/rulesets/\(name)" + (version.map { "?version=\($0)" } ?? ""))
    }

    /// Stores a ruleset as its next version: on the standard, or on a branch, declaring the
    /// standard version the document takes in. `basedOn`, the head of that branch the document was
    /// made from, or zero for a name that must be new, has the silo refuse with 409 when it no longer
    /// is the head.
    public func store(
        ruleset document: String,
        as name: String,
        branch: String? = nil,
        upToDateWith: Int? = nil,
        basedOn: Int? = nil
    ) async throws -> RulesetDocument {
        try await send(
            "PUT",
            "/v1/rulesets/\(name)",
            body: RulesetDocument(
                name: name,
                version: nil,
                branch: branch,
                upToDateWith: upToDateWith,
                basedOn: basedOn,
                document: document
            )
        )
    }

    /// Reads a document as a store under the name would, storing nothing: the reading, or the
    /// store's refusal as `status(400, _)`.
    public func check(ruleset document: String, as name: String) async throws -> RulesetReading {
        try await send(
            "POST",
            "/v1/rulesets/\(name)/check",
            body: RulesetDocument(
                name: name,
                version: nil,
                branch: nil,
                upToDateWith: nil,
                basedOn: nil,
                document: document
            )
        )
    }

    private struct DraftImpact: Codable {
        var document: String
        var basedOn: Int
    }

    /// What a draft based on a version would put out of date, were it stored on that version's
    /// branch. Records nothing.
    public func impact(
        ofDraft document: String,
        basedOn version: Int,
        of name: String
    ) async throws -> [OutOfDatePresentation] {
        try await send("POST", "/v1/rulesets/\(name)/impact", body: DraftImpact(document: document, basedOn: version))
    }

    /// What promoting a branch would put out of date. Records nothing.
    public func impact(ofBranch branch: String, of name: String) async throws -> [OutOfDatePresentation] {
        try await send("GET", "/v1/rulesets/\(name)/branches/\(branch)/impact")
    }

    public func branches(of ruleset: String) async throws -> [Branch] {
        try await send("GET", "/v1/rulesets/\(ruleset)/branches")
    }

    private struct NewBranch: Codable {
        var name: String
        var from: Int
    }

    public func startBranch(_ branch: String, of ruleset: String, from version: Int) async throws -> Branch {
        try await send("POST", "/v1/rulesets/\(ruleset)/branches", body: NewBranch(name: branch, from: version))
    }

    /// Makes a branch's head the standard's next version; refused while the standard has versions
    /// the branch has not taken in.
    public func promote(_ branch: String, of ruleset: String) async throws -> RulesetRef {
        try await send("POST", "/v1/rulesets/\(ruleset)/branches/\(branch)/promote")
    }
}
