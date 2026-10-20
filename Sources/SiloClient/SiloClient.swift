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
            library: String,
            containers: [String],
            item: String,
            alternative: String? = nil,
            tracks: [TrackMapping] = [],
            chapters: [Chapter] = [],
            segments: [Binding.Segment]
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
        guard (200..<300).contains(status) else {
            throw SiloClientError.status(status, String(decoding: data, as: UTF8.self))
        }
    }

    // MARK: - Jobs

    struct NewJob: Codable {
        var recipe: String
        var trial: Bool?
    }

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
        let query = [ruleset.map { "ruleset=\($0)" }, branch.map { "branch=\($0)" }].compactMap { $0 }.joined(
            separator: "&"
        )
        return try await send("GET", "/v1/trials" + (query.isEmpty ? "" : "?" + query))
    }

    public func deleteTrial(_ job: String) async throws {
        let (data, status) = try await request("DELETE", "/v1/trials/\(job)", body: Nothing?.none)
        guard (200..<300).contains(status) else {
            throw SiloClientError.status(status, String(decoding: data, as: UTF8.self))
        }
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

    struct ClaimRequest: Codable {
        var node: String
        var capabilities: [String]
    }
    struct ProgressReply: Codable { var state: JobState }
    struct CompleteRequest: Codable {
        var output: FileRef
        var result: EncodeResult
    }
    struct FailRequest: Codable { var reason: String }

    struct ClaimReply: Codable {
        var job: Job?
        var recipe: StoredRecipe?
        var segments: [ClaimedSegment]?
    }

    public func claim(node: String, capabilities: Set<String>) async throws -> Claim? {
        let reply: ClaimReply = try await send(
            "POST",
            "/v1/jobs/claim",
            body: ClaimRequest(node: node, capabilities: capabilities.sorted())
        )
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

    struct Nothing: Encodable {}

    func send<Response: Decodable>(_ method: String, _ path: String) async throws -> Response {
        try await send(method, path, body: Nothing?.none)
    }

    func send<Body: Encodable, Response: Decodable>(
        _ method: String,
        _ path: String,
        body: Body?,
        headers: [String: String] = [:]
    ) async throws -> Response {
        let (data, status) = try await request(method, path, body: body, headers: headers)
        guard (200..<300).contains(status) else {
            throw SiloClientError.status(status, String(decoding: data, as: UTF8.self))
        }
        return try Self.decoder.decode(Response.self, from: data)
    }

    func request<Body: Encodable>(
        _ method: String,
        _ path: String,
        body: Body?,
        headers: [String: String] = [:]
    ) async throws -> (Data, Int) {
        try await request(
            method,
            path,
            data: try body.map { try Self.encoder.encode($0) },
            contentType: body == nil ? nil : "application/json",
            headers: headers
        )
    }

    func request(
        _ method: String,
        _ path: String,
        data body: Data?,
        contentType: String?,
        headers: [String: String] = [:]
    ) async throws -> (Data, Int) {
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
