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

    /// Applies a ruleset to a binding, making a draft recipe for each output the application names.
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
    /// and makes it the version in force. Apply the rules to the binding again for a draft that
    /// carries it.
    public func setRules(_ document: String, of binding: String) async throws -> BindingRulesRecord {
        try await send("PUT", "/v1/bindings/\(binding)/rules", body: NewBindingRules(document: document))
    }

    public func discard(_ recipe: String) async throws {
        let (data, status) = try await request("DELETE", "/v1/recipes/\(recipe)", body: Nothing?.none)
        guard (200..<300).contains(status) else { throw SiloClientError.status(status, String(decoding: data, as: UTF8.self)) }
    }

    // MARK: - Jobs

    struct NewJob: Codable { var recipe: String }

    /// A job from a draft recipe, which it commits.
    public func createJob(recipe: String) async throws -> Job {
        try await send("POST", "/v1/jobs", body: NewJob(recipe: recipe))
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

    /// A ruleset as the silo reads it, named by where it is stored: what a console shows beside the
    /// document, so that it never parses one itself.
    public struct RulesetReading: Hashable, Sendable, Codable {
        public var name: String
        public var extraction: ExtractionPolicy
        /// In document order.
        public var rules: [RuleReading]
        public var outputs: [OutputPolicy]
    }

    /// One rule, by the name a recipe calls it by: its id, or `#n` for its position.
    public struct RuleReading: Hashable, Sendable, Codable {
        public var name: String
        public var scope: Scope
        public var conditions: [ConditionReading]
        public var action: Action
    }

    /// A condition as the document writes it: the fact, the test's attribute and its value.
    public struct ConditionReading: Hashable, Sendable, Codable {
        public var fact: String
        public var test: String
        public var value: String
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

    /// A library's out-of-date presentations, from the background check's records.
    public func outOfDate(in library: String) async throws -> OutOfDateReport {
        try await send("GET", "/v1/libraries/\(library)/out-of-date")
    }

    public func ruleset(named name: String, version: Int? = nil) async throws -> RulesetDocument {
        try await send("GET", "/v1/rulesets/\(name)" + (version.map { "?version=\($0)" } ?? ""))
    }

    /// Stores a ruleset as its next version: on the standard, or on a branch, declaring the
    /// standard version the document takes in.
    public func store(ruleset document: String, as name: String, branch: String? = nil, upToDateWith: Int? = nil) async throws -> RulesetDocument {
        try await send("PUT", "/v1/rulesets/\(name)", body: RulesetDocument(name: name, version: nil, branch: branch, upToDateWith: upToDateWith, basedOn: nil, document: document))
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

            public init(name: String, embeddedNode: Bool, advertise: Bool) {
                self.name = name
                self.embeddedNode = embeddedNode
                self.advertise = advertise
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
            public var stateDirectory: String
            public var libraries: [Library]

            public init(serverID: String, host: String, port: Int, stateDirectory: String, libraries: [Library]) {
                self.serverID = serverID
                self.host = host
                self.port = port
                self.stateDirectory = stateDirectory
                self.libraries = libraries
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
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else { throw SiloClientError.badPath(path) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try Self.encoder.encode(body)
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
