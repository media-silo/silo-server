// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloKit
import SmdSidecar
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The silo's API from a client's side: a producer registering sources, binding them and making
/// jobs of their recipes, a node claiming work, the operator's command line. Hand-written over SiloKit's own types rather than generated,
/// so that a client needs nothing but Foundation.
public struct SiloClient: Sendable, JobsAPI {
    public let baseURL: URL
    public let token: String?
    private let session: URLSession

    public init(baseURL: URL, token: String? = nil, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    // MARK: - Sources

    /// A source as the silo renders it: each copy without the secret that guards its file.
    public struct SourceRecord: Hashable, Sendable, Codable {
        public var id: String
        public var input: InputSpec
        public var key: SiloKit.NaturalKey?
        public var copies: [Copy]
        public var createdAt: Date

        public struct Copy: Hashable, Sendable, Codable {
            public var holder: String
            public var url: URL
            public var path: String?
            public var sizeBytes: Int64?
        }
    }

    public struct NewSource: Hashable, Sendable, Codable {
        public var input: InputSpec
        public var key: SiloKit.NaturalKey?
        public var copy: FileRef?

        public init(input: InputSpec, key: SiloKit.NaturalKey? = nil, copy: FileRef? = nil) {
            self.input = input
            self.key = key
            self.copy = copy
        }
    }

    /// Registers a source, or answers the one its natural key already names, taking the copy given.
    public func registerSource(_ source: NewSource) async throws -> SourceRecord {
        try await send("POST", "/v1/sources", body: source)
    }

    public func sources() async throws -> [SourceRecord] {
        try await send("GET", "/v1/sources")
    }

    public func source(_ id: String) async throws -> SourceRecord {
        try await send("GET", "/v1/sources/\(id)")
    }

    public func addCopy(_ copy: FileRef, to source: String) async throws -> SourceRecord {
        try await send("POST", "/v1/sources/\(source)/copies", body: copy)
    }

    public func removeCopy(on node: String, from source: String) async throws -> SourceRecord {
        try await send("DELETE", "/v1/sources/\(source)/copies/\(node)")
    }

    // MARK: - Bindings and recipes

    /// A binding as a producer sends it, before the silo has given it an id.
    public struct NewBinding: Hashable, Sendable, Codable {
        public var library: String
        public var containers: [String]
        public var item: String
        public var alternative: String?
        public var tracks: [TrackMapping]
        public var chapters: [Chapter]
        public var segments: [Binding.Segment]

        public init(
            library: String, containers: [String], item: String, alternative: String? = nil, tracks: [TrackMapping] = [],
            chapters: [Chapter] = [], segments: [Binding.Segment]
        ) {
            self.library = library
            self.containers = containers
            self.item = item
            self.alternative = alternative
            self.tracks = tracks
            self.chapters = chapters
            self.segments = segments
        }
    }

    /// A binding as the silo renders it, with the ids of its recipes, oldest first.
    public struct BindingRecord: Hashable, Sendable, Decodable {
        public var binding: Binding
        public var recipes: [String]

        private enum CodingKeys: String, CodingKey { case recipes }

        public init(from decoder: any Decoder) throws {
            binding = try Binding(from: decoder)
            recipes = try decoder.container(keyedBy: CodingKeys.self).decode([String].self, forKey: .recipes)
        }
    }

    public func makeBinding(_ binding: NewBinding) async throws -> BindingRecord {
        try await send("POST", "/v1/bindings", body: binding)
    }

    public func binding(_ id: String) async throws -> BindingRecord {
        try await send("GET", "/v1/bindings/\(id)")
    }

    /// Applies a ruleset to a binding, making a resolved recipe for each output the application names.
    public func apply(_ application: Application, to binding: String) async throws -> [StoredRecipe] {
        try await send("POST", "/v1/bindings/\(binding)/recipes", body: application)
    }

    public func recipe(_ id: String) async throws -> StoredRecipe {
        try await send("GET", "/v1/recipes/\(id)")
    }


    /// A binding's own rules: the version in force, its document, and every version there is.
    public struct BindingRulesRecord: Hashable, Sendable, Codable {
        public var activeVersion: Int?
        public var document: String?
        public var versions: [Int]
    }

    private struct NewBindingRules: Codable { var document: String }

    public func rules(of binding: String) async throws -> BindingRulesRecord {
        try await send("GET", "/v1/bindings/\(binding)/rules")
    }

    /// Stores a binding's next version of its rules — a person's decision about that one entry —
    /// and makes it the version in force. Apply the rules to the binding again for a recipe that
    /// carries it.
    public func setRules(_ document: String, of binding: String) async throws -> BindingRulesRecord {
        try await send("PUT", "/v1/bindings/\(binding)/rules", body: NewBindingRules(document: document))
    }

    public func discard(_ recipe: String) async throws {
        let (data, status) = try await request("DELETE", "/v1/recipes/\(recipe)", body: Nothing?.none)
        guard (200..<300).contains(status) else { throw SiloClientError.status(status, String(decoding: data, as: UTF8.self)) }
    }

    // MARK: - Jobs

    struct NewJob: Codable { var recipe: String; var trial: Bool? }

    /// A job from a resolved recipe, which it commits; a trial is kept in the silo's trial area and
    /// never placed.
    public func createJob(recipe: String, trial: Bool = false) async throws -> Job {
        try await send("POST", "/v1/jobs", body: NewJob(recipe: recipe, trial: trial ? true : nil))
    }

    // MARK: - Trials

    /// A tried trial: its job, the ruleset version that made its recipe and the branch that version
    /// is on, its binding and output, and how the encode went.
    public struct Trial: Hashable, Sendable, Codable {
        public var job: String
        public var recipe: String
        public var ruleset: String
        public var version: Int?
        public var branch: String?
        public var binding: String
        public var profile: String?
        public var result: EncodeResult?
        public var createdAt: Date
    }

    public func trials(ruleset: String? = nil, branch: String? = nil) async throws -> [Trial] {
        let query = [ruleset.map { "ruleset=\($0)" }, branch.map { "branch=\($0)" }].compactMap { $0 }.joined(separator: "&")
        return try await send("GET", "/v1/trials" + (query.isEmpty ? "" : "?" + query))
    }

    public func deleteTrial(_ job: String) async throws {
        let (data, status) = try await request("DELETE", "/v1/trials/\(job)", body: Nothing?.none)
        guard (200..<300).contains(status) else { throw SiloClientError.status(status, String(decoding: data, as: UTF8.self)) }
    }

    /// Where a trial's output is served, by range, openly.
    public func trialFileURL(_ job: String) -> URL {
        baseURL.appending(path: "v1/trials/\(job)/file")
    }

    /// Where a placed presentation is served, by range, openly.
    public func mediaURL(_ presentation: String) -> URL {
        baseURL.appending(path: "v1/media/\(presentation)")
    }

    public func jobs(state: JobState? = nil) async throws -> [Job] {
        try await send("GET", "/v1/jobs" + (state.map { "?state=\($0.rawValue)" } ?? ""))
    }

    public func job(_ id: String) async throws -> Job {
        try await send("GET", "/v1/jobs/\(id)")
    }

    public func cancel(_ id: String) async throws -> Job {
        try await send("POST", "/v1/jobs/\(id)/cancel")
    }

    public func retry(_ id: String) async throws -> Job {
        try await send("POST", "/v1/jobs/\(id)/retry")
    }

    public func place(_ id: String) async throws -> Job {
        try await send("POST", "/v1/jobs/\(id)/place")
    }

    // MARK: JobsAPI

    struct ClaimRequest: Codable { var node: String; var capabilities: [String] }
    struct ProgressReply: Codable { var state: JobState }
    struct CompleteRequest: Codable { var output: FileRef; var result: EncodeResult }
    struct FailRequest: Codable { var reason: String }

    struct ClaimReply: Codable {
        var job: Job?
        var recipe: StoredRecipe?
        var segments: [ClaimedSegment]?
    }

    public func claim(node: String, capabilities: Set<String>) async throws -> Claim? {
        let reply: ClaimReply = try await send("POST", "/v1/jobs/claim", body: ClaimRequest(node: node, capabilities: capabilities.sorted()))
        return reply.job.map { Claim(job: $0, recipe: reply.recipe, segments: reply.segments ?? []) }
    }

    public func report(_ job: String, progress: JobProgress) async throws -> JobState {
        let reply: ProgressReply = try await send("POST", "/v1/jobs/\(job)/progress", body: progress)
        return reply.state
    }

    public func complete(_ job: String, output: FileRef, result: EncodeResult) async throws -> Job {
        try await send("POST", "/v1/jobs/\(job)/complete", body: CompleteRequest(output: output, result: result))
    }

    public func fail(_ job: String, reason: String) async throws -> Job {
        try await send("POST", "/v1/jobs/\(job)/fail", body: FailRequest(reason: reason))
    }

    // MARK: - Nodes

    public func registerNode(_ registration: NodeRegistration) async throws -> Node {
        try await send("POST", "/v1/nodes", body: registration)
    }

    public func nodeStatus(id: String, secret: String) async throws -> NodeStatus {
        try await send("GET", "/v1/nodes/\(id)", body: Nothing?.none, headers: ["x-silo-node-secret": secret])
    }

    public func nodes() async throws -> [Node] {
        try await send("GET", "/v1/nodes")
    }

    public func approveNode(_ id: String) async throws -> Node {
        try await send("POST", "/v1/nodes/\(id)/approve")
    }

    public func revokeNode(_ id: String) async throws -> Node {
        try await send("POST", "/v1/nodes/\(id)/revoke")
    }

    // MARK: - Rulesets

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

    private struct NewLibrary: Codable { var id: String; var path: String; var create: Bool? }

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
        guard (200..<300).contains(status) else { throw SiloClientError.status(status, String(decoding: data, as: UTF8.self)) }
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
    public func store(ruleset document: String, as name: String, branch: String? = nil, upToDateWith: Int? = nil, basedOn: Int? = nil) async throws -> RulesetDocument {
        try await send("PUT", "/v1/rulesets/\(name)", body: RulesetDocument(name: name, version: nil, branch: branch, upToDateWith: upToDateWith, basedOn: basedOn, document: document))
    }

    /// Reads a document as a store under the name would, storing nothing: the reading, or the
    /// store's refusal as `status(400, _)`.
    public func check(ruleset document: String, as name: String) async throws -> RulesetReading {
        try await send("POST", "/v1/rulesets/\(name)/check", body: RulesetDocument(name: name, version: nil, branch: nil, upToDateWith: nil, basedOn: nil, document: document))
    }

    private struct DraftImpact: Codable { var document: String; var basedOn: Int }

    /// What a draft based on a version would put out of date, were it stored on that version's
    /// branch. Records nothing.
    public func impact(ofDraft document: String, basedOn version: Int, of name: String) async throws -> [OutOfDatePresentation] {
        try await send("POST", "/v1/rulesets/\(name)/impact", body: DraftImpact(document: document, basedOn: version))
    }

    /// What promoting a branch would put out of date. Records nothing.
    public func impact(ofBranch branch: String, of name: String) async throws -> [OutOfDatePresentation] {
        try await send("GET", "/v1/rulesets/\(name)/branches/\(branch)/impact")
    }

    public func branches(of ruleset: String) async throws -> [Branch] {
        try await send("GET", "/v1/rulesets/\(ruleset)/branches")
    }

    private struct NewBranch: Codable { var name: String; var from: Int }

    public func startBranch(_ branch: String, of ruleset: String, from version: Int) async throws -> Branch {
        try await send("POST", "/v1/rulesets/\(ruleset)/branches", body: NewBranch(name: branch, from: version))
    }

    /// Makes a branch's head the standard's next version; refused while the standard has versions
    /// the branch has not taken in.
    public func promote(_ branch: String, of ruleset: String) async throws -> RulesetRef {
        try await send("POST", "/v1/rulesets/\(ruleset)/branches/\(branch)/promote")
    }

    // MARK: - Containers

    /// A container as a summary: what a library's list of its containers, and a container's children,
    /// say of each.
    public struct ContainerSummary: Hashable, Sendable, Codable, Identifiable {
        public var id: String
        public var library: String
        public var type: String
        public var title: String
        public var displayTitle: String
        public var year: Int?
        public var typeLabel: String?
        public var outline: String?
        public var listed: Bool
        public var parent: String?
    }

    /// A container as a library's sidecar says it, with that library's presentations of each item.
    public struct Container: Hashable, Sendable, Codable, Identifiable {
        public struct Alternative: Hashable, Sendable, Codable {
            public var id: String
            public var sequence: String
            public var title: String?
            public var outline: String?
        }

        public struct Participant: Hashable, Sendable, Codable {
            public var name: String
            public var role: String?
        }

        public struct Feature: Hashable, Sendable, Codable {
            public var id: String
            public var type: String
            public var title: String?
            public var participants: [Participant]
        }

        public struct ExternalRef: Hashable, Sendable, Codable {
            public var provider: String
            public var value: String
        }

        /// One presentation of an item in the library: the name it is shown under, its profile and
        /// alternative, and its file beside the sidecar.
        public struct Presentation: Hashable, Sendable, Codable, Identifiable {
            public var id: String
            public var alternative: String?
            public var profile: String?
            public var displayName: String?
            public var file: String
        }

        public struct Item: Hashable, Sendable, Codable {
            public var id: String?
            public var type: String?
            public var title: String?
            public var outline: String?
            public var optional: Bool
            /// The child container the item is, when it is one.
            public var container: String?
            public var externalRefs: [ExternalRef]
            public var presentations: [Presentation]
        }

        public struct Sequence: Hashable, Sendable, Codable {
            public var id: String?
            public var exploded: String
            public var items: [Item]
        }

        public var id: String
        public var library: String
        public var type: String
        public var title: String
        public var displayTitle: String
        public var year: Int?
        public var typeLabel: String?
        public var outline: String?
        public var listed: Bool
        public var parent: String?
        public var defaultAlternative: String?
        public var alternatives: [Alternative]
        public var features: [Feature]
        public var sequences: [Sequence]
        public var extrasAnchor: String?
        public var extras: [Item]
        public var children: [ContainerSummary]
        public var externalRefs: [ExternalRef]
    }

    /// A container in one library: the library, its sidecar's path in it, the digest an edit names as
    /// its base, the artwork kinds its folder holds, and the container as the sidecar says it.
    public struct LibraryContainer: Hashable, Sendable, Codable {
        public var library: String
        public var path: String
        public var digest: String
        public var artwork: [String]
        public var container: Container
    }

    /// What an edit wrote, or would write: the sidecar's bytes as text, their digest, and what the
    /// silo found in them.
    public struct ContainerEditResult: Hashable, Sendable, Codable {
        public var applied: Bool
        public var sidecar: String
        public var digest: String
        public var findings: [LastWalk.Finding]
    }

    /// The artwork kinds a container's folder may hold, in the order the silo lists them.
    public static let artworkKinds = ["poster", "fanart", "banner", "logo", "thumb"]

    /// The containers at the top of a library, listed or not.
    public func containers(in library: String) async throws -> [ContainerSummary] {
        try await send("GET", "/v1/libraries/\(library)/containers")
    }

    public func container(_ id: String, in library: String) async throws -> LibraryContainer {
        try await send("GET", "/v1/libraries/\(library)/containers/\(id)")
    }

    /// The library's sidecar for a container, as its bytes.
    public func sidecar(of id: String, in library: String) async throws -> Data {
        let (data, status) = try await request("GET", "/v1/libraries/\(library)/containers/\(id)/smd", data: nil, contentType: nil)
        guard (200..<300).contains(status) else { throw SiloClientError.status(status, String(decoding: data, as: UTF8.self)) }
        return data
    }

    private struct ContainerEdit: Codable { var document: String; var basedOn: String; var dryRun: Bool? }

    /// Sets a container's own fields in a library's sidecar from its repository document, onto the
    /// sidecar whose digest is `basedOn`. Refused with `status(409, _)`, naming the digest the library
    /// holds, when that is no longer it, and with `status(422, _)` carrying the result and its findings
    /// when they refuse it. Operator only.
    public func edit(container id: String, in library: String, document: String, basedOn: String, dryRun: Bool = false) async throws -> ContainerEditResult {
        try await send("PUT", "/v1/libraries/\(library)/containers/\(id)", body: ContainerEdit(document: document, basedOn: basedOn, dryRun: dryRun ? true : nil))
    }

    /// Where a kind of a container's artwork is served, openly.
    public func artworkURL(_ kind: String, of id: String, in library: String) -> URL {
        URL(string: "/v1/libraries/\(library)/containers/\(id)/artwork/\(kind)", relativeTo: baseURL)!.absoluteURL
    }

    /// What the silo answered a put of artwork with.
    public struct ArtworkPut: Hashable, Sendable, Codable {
        public var kind: String
        public var format: String
    }

    /// Puts an image as a kind of a container's artwork. Refused with `status(415, _)` for anything
    /// not a JPEG or a PNG by its bytes, and `status(413, _)` for an image over 25 MB. Operator only.
    public func putArtwork(_ image: Data, as kind: String, of id: String, in library: String) async throws -> ArtworkPut {
        let (data, status) = try await request("PUT", "/v1/libraries/\(library)/containers/\(id)/artwork/\(kind)", data: image, contentType: "application/octet-stream")
        guard (200..<300).contains(status) else { throw SiloClientError.status(status, String(decoding: data, as: UTF8.self)) }
        return try Self.decoder.decode(ArtworkPut.self, from: data)
    }

    /// Removes a kind of a container's artwork. Operator only.
    public func removeArtwork(_ kind: String, of id: String, in library: String) async throws {
        let (data, status) = try await request("DELETE", "/v1/libraries/\(library)/containers/\(id)/artwork/\(kind)", data: nil, contentType: nil)
        guard (200..<300).contains(status) else { throw SiloClientError.status(status, String(decoding: data, as: UTF8.self)) }
    }

    // MARK: - Server

    /// Who the silo says it is, openly: its id, its name, and whether it still waits on a setup.
    public struct ServerInfo: Hashable, Sendable, Codable {
        public var id: String
        public var name: String
        public var bootstrap: Bool

        public init(id: String, name: String, bootstrap: Bool) {
            self.id = id
            self.name = name
            self.bootstrap = bootstrap
        }
    }

    /// What the verify probe answers: whether the client's token is the operator's own
    /// (`active`) or a live staged passkey (`pending`, with the deadline it can still be
    /// confirmed by). Anything else is a 401, thrown as `status(401, _)`.
    public enum OperatorStatus: Hashable, Sendable {
        case active
        case pending(confirmBy: Date)

        private struct Wire: Decodable {
            var phase: String
            var confirmBy: Date?
        }

        init(decoding data: Data) throws {
            let wire = try SiloClient.decoder.decode(Wire.self, from: data)
            switch (wire.phase, wire.confirmBy) {
            case ("active", nil): self = .active
            case ("pending", let confirmBy?): self = .pending(confirmBy: confirmBy)
            default: throw SiloClientError.status(200, "an OperatorStatus the client does not know")
            }
        }
    }

    /// What staging tells its stager: the name the setup would take and its deadline.
    public struct SetupStage: Hashable, Sendable, Codable {
        public var id: String
        public var name: String
        public var confirmBy: Date

        public init(id: String, name: String, confirmBy: Date) {
            self.id = id
            self.name = name
            self.confirmBy = confirmBy
        }
    }

    struct SetupRequest: Codable { var name: String?; var passkey: String }
    struct SetupConflict: Codable { var confirmBy: Date }

    public func server() async throws -> ServerInfo {
        try await send("GET", "/v1/server")
    }

    /// The verify-access probe: what the client's token amounts to — `active` for the
    /// operator's own, `pending` with its deadline for a live staged passkey — so a 401 here
    /// names the credential and not the server or its node subsystem.
    public func verifyAccess() async throws -> OperatorStatus {
        let (data, status) = try await request("GET", "/v1/operator", body: Nothing?.none)
        guard (200..<300).contains(status) else { throw SiloClientError.status(status, String(decoding: data, as: UTF8.self)) }
        return try OperatorStatus(decoding: data)
    }

    /// Stages the server's only setup. While a stage stands this throws `conflict(confirmBy:)`
    /// carrying the standing stage's deadline; once the server is set up, `status(410, _)`.
    public func setup(name: String? = nil, passkey: String) async throws -> SetupStage {
        do {
            return try await send("POST", "/v1/setup", body: SetupRequest(name: name, passkey: passkey))
        } catch SiloClientError.status(409, let body) {
            if let conflict = try? Self.decoder.decode(SetupConflict.self, from: Data(body.utf8)) {
                throw SiloClientError.conflict(confirmBy: conflict.confirmBy)
            }
            throw SiloClientError.status(409, body)
        }
    }

    /// Spends the staged setup: the passkey travels as the bearer, not as the client's token.
    public func confirmSetup(bearer: String) async throws -> ServerInfo {
        try await send("POST", "/v1/setup/confirm", body: Nothing?.none, headers: ["Authorization": "Bearer \(bearer)"])
    }

    // MARK: - Settings

    /// What `GET /v1/settings` reports: what a route changes, under `editable`, and what none does —
    /// `silo.json`, the state directory, the libraries — under `readOnly`.
    public struct SettingsReport: Hashable, Sendable, Codable {
        public struct Editable: Hashable, Sendable, Codable {
            public var name: String
            public var embeddedNode: Bool
            public var advertise: Bool
            /// Changed through the library routes, not the settings patch.
            public var libraries: [Library]

            public init(name: String, embeddedNode: Bool, advertise: Bool, libraries: [Library] = []) {
                self.name = name
                self.embeddedNode = embeddedNode
                self.advertise = advertise
                self.libraries = libraries
            }
        }

        public struct Library: Hashable, Sendable, Codable {
            public var id: String
            public var path: String

            public init(id: String, path: String) {
                self.id = id
                self.path = path
            }
        }

        public struct Machine: Hashable, Sendable, Codable {
            public var serverID: String
            public var host: String
            public var port: Int
            /// Where a library added over the network must lie; empty, nothing can be.
            public var libraryRoots: [String]
            public var stateDirectory: String

            public init(serverID: String, host: String, port: Int, libraryRoots: [String], stateDirectory: String) {
                self.serverID = serverID
                self.host = host
                self.port = port
                self.libraryRoots = libraryRoots
                self.stateDirectory = stateDirectory
            }
        }

        public var editable: Editable
        public var readOnly: Machine

        public init(editable: Editable, readOnly: Machine) {
            self.editable = editable
            self.readOnly = readOnly
        }
    }

    /// Any of the editable settings; what is left `nil` is left out of the body, and unchanged.
    public struct SettingsPatch: Hashable, Sendable, Codable {
        public var name: String?
        public var embeddedNode: Bool?
        public var advertise: Bool?

        public init(name: String? = nil, embeddedNode: Bool? = nil, advertise: Bool? = nil) {
            self.name = name
            self.embeddedNode = embeddedNode
            self.advertise = advertise
        }
    }

    /// The silo's settings and the facts of its machine. Operator only.
    public func settings() async throws -> SettingsReport {
        try await send("GET", "/v1/settings")
    }

    /// Changes the editable settings, all of the patch or none of it; a refusal is `status(400, _)`
    /// carrying the silo's reason. Operator only.
    public func updateSettings(_ patch: SettingsPatch) async throws -> SettingsReport {
        try await send("PATCH", "/v1/settings", body: patch)
    }

    // MARK: - Plumbing

    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private struct Nothing: Encodable {}

    private func send<Response: Decodable>(_ method: String, _ path: String) async throws -> Response {
        try await send(method, path, body: Nothing?.none)
    }

    private func send<Body: Encodable, Response: Decodable>(_ method: String, _ path: String, body: Body?, headers: [String: String] = [:]) async throws -> Response {
        let (data, status) = try await request(method, path, body: body, headers: headers)
        guard (200..<300).contains(status) else { throw SiloClientError.status(status, String(decoding: data, as: UTF8.self)) }
        return try Self.decoder.decode(Response.self, from: data)
    }

    private func request<Body: Encodable>(_ method: String, _ path: String, body: Body?, headers: [String: String] = [:]) async throws -> (Data, Int) {
        try await request(method, path, data: try body.map { try Self.encoder.encode($0) }, contentType: body == nil ? nil : "application/json", headers: headers)
    }

    private func request(_ method: String, _ path: String, data body: Data?, contentType: String?, headers: [String: String] = [:]) async throws -> (Data, Int) {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else { throw SiloClientError.badPath(path) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if let body {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        return (data, status)
    }
}

public enum SiloClientError: Error, CustomStringConvertible {
    case badPath(String)
    case status(Int, String)
    /// A `POST /v1/setup` was refused because a stage already stands; the deadline is the
    /// standing stage's own, so a refused console knows how long to wait out.
    case conflict(confirmBy: Date)

    public var description: String {
        switch self {
        case .badPath(let path): "not a path: \(path)"
        case .status(let status, let body): "the silo answered \(status)\(body.isEmpty ? "" : ": \(body)")"
        case .conflict(let confirmBy): "a setup is staged already until \(confirmBy)"
        }
    }
}
