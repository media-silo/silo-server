// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The silo's API from a client's side: the ingestion tool registering a rip, a node claiming
/// work, the operator's command line. Hand-written over SiloKit's own types rather than generated,
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

    // MARK: - Jobs

    public struct NewJob: Hashable, Sendable, Codable {
        public var source: FileRef
        public var discName: String?
        public var probe: ProbedSource?
        public var makeMKV: MakeMKVFacts?

        public init(source: FileRef, discName: String? = nil, probe: ProbedSource? = nil, makeMKV: MakeMKVFacts? = nil) {
            self.source = source
            self.discName = discName
            self.probe = probe
            self.makeMKV = makeMKV
        }
    }

    public func createJob(_ job: NewJob) async throws -> Job {
        try await send("POST", "/v1/jobs", body: job)
    }

    public func jobs(state: JobState? = nil) async throws -> [Job] {
        try await send("GET", "/v1/jobs" + (state.map { "?state=\($0.rawValue)" } ?? ""))
    }

    public func job(_ id: String) async throws -> Job {
        try await send("GET", "/v1/jobs/\(id)")
    }

    public func assign(_ id: String, _ assignment: Assignment) async throws -> Job {
        try await send("PUT", "/v1/jobs/\(id)/assignment", body: assignment)
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

    struct ClaimReply: Codable { var job: Job? }

    public func claim(node: String, capabilities: Set<String>) async throws -> Job? {
        let reply: ClaimReply = try await send("POST", "/v1/jobs/claim", body: ClaimRequest(node: node, capabilities: capabilities.sorted()))
        return reply.job
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

    public struct RulesetDocument: Hashable, Sendable, Codable {
        public var name: String
        public var version: Int?
        public var document: String
    }

    public func rulesets() async throws -> [RulesetRef] {
        try await send("GET", "/v1/rulesets")
    }

    public func ruleset(named name: String, version: Int? = nil) async throws -> RulesetDocument {
        try await send("GET", "/v1/rulesets/\(name)" + (version.map { "?version=\($0)" } ?? ""))
    }

    public func store(ruleset document: String, as name: String) async throws -> RulesetDocument {
        try await send("PUT", "/v1/rulesets/\(name)", body: RulesetDocument(name: name, version: nil, document: document))
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

    public var description: String {
        switch self {
        case .badPath(let path): "not a path: \(path)"
        case .status(let status, let body): "the silo answered \(status)\(body.isEmpty ? "" : ": \(body)")"
        }
    }
}
