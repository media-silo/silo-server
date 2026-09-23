// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SmdSidecar

/// One source file on its way to one presentation. `Silo.md`, *Jobs, nodes and moving files*.
public struct Job: Identifiable, Hashable, Sendable, Codable {
    public var id: String
    public var state: JobState
    public var createdAt: Date
    public var updatedAt: Date
    /// Where the ripped file is: on the node that ripped it, served by it.
    public var source: FileRef
    public var discName: String?
    /// What `ffprobe` saw of the source, sent by the tool that holds it, so the silo needs no
    /// `ffprobe` of its own to resolve a recipe.
    public var probe: ProbedSource?
    public var makeMKV: MakeMKVFacts?
    public var assignment: Assignment?
    public var facts: SourceFacts?
    public var recipe: Recipe?
    /// The encoders the recipe needs; a node claims only what its `ffmpeg` can do.
    public var requirements: [String]
    public var attempts: [Attempt]
    public var lease: Lease?
    public var progress: JobProgress?
    /// Where the encoded file is: on the node that made it, until the silo places it.
    public var output: FileRef?
    public var result: EncodeResult?
    public var placement: PlacementSummary?
    /// Why the job failed, when it did.
    public var failure: String?

    public init(id: String = UUID().uuidString.lowercased(), state: JobState = .unassigned, createdAt: Date = .now, source: FileRef, discName: String? = nil, probe: ProbedSource? = nil, makeMKV: MakeMKVFacts? = nil) {
        self.id = id
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.source = source
        self.discName = discName
        self.probe = probe
        self.makeMKV = makeMKV
        self.assignment = nil
        self.facts = nil
        self.recipe = nil
        self.requirements = []
        self.attempts = []
        self.lease = nil
        self.progress = nil
        self.output = nil
        self.result = nil
        self.placement = nil
        self.failure = nil
    }

    public var isActive: Bool {
        [.claimed, .encoding, .cancelling].contains(state)
    }
}

public enum JobState: String, Hashable, Sendable, Codable, CaseIterable {
    case unassigned, pending, claimed, encoding, encoded, placing, placed, failed, cancelling, cancelled
}

/// A file where it is, served by the node that holds it. `path` is for the holder's own use, so
/// that a node claiming a job whose source it holds opens the file rather than fetching it.
public struct FileRef: Hashable, Sendable, Codable {
    public var holder: String
    public var url: URL
    public var path: String?
    public var sizeBytes: Int64?
    /// Minted per file by its holder; the silo hands it only to the node that needs the file.
    public var secret: String

    public init(holder: String, url: URL, path: String? = nil, sizeBytes: Int64? = nil, secret: String) {
        self.holder = holder
        self.url = url
        self.path = path
        self.sizeBytes = sizeBytes
        self.secret = secret
    }

    public static func mintSecret() -> String {
        (0..<32).map { _ in String(UInt8.random(in: 0...255), radix: 16).leftPadded(to: 2) }.joined()
    }
}

/// What Assign says a file is. The containers are the item's and every one above it, root
/// first, as their repository documents: what placement needs, carried with the job.
public struct Assignment: Hashable, Sendable, Codable {
    public var library: String
    public var containers: [String]
    public var item: String
    public var alternative: String?
    public var profile: String?
    public var tracks: [TrackMapping]
    public var chapters: [Chapter]
    public var source: SourceRef?
    /// The ruleset to resolve against, by name; the silo's latest version of it, unless given.
    public var ruleset: String
    public var rulesetVersion: Int?

    public init(library: String, containers: [String], item: String, alternative: String? = nil, profile: String? = nil, tracks: [TrackMapping] = [], chapters: [Chapter] = [], source: SourceRef? = nil, ruleset: String, rulesetVersion: Int? = nil) {
        self.library = library
        self.containers = containers
        self.item = item
        self.alternative = alternative
        self.profile = profile
        self.tracks = tracks
        self.chapters = chapters
        self.source = source
        self.ruleset = ruleset
        self.rulesetVersion = rulesetVersion
    }
}

public struct Attempt: Hashable, Sendable, Codable {
    public var node: String
    public var startedAt: Date
    public var endedAt: Date?
    /// `lost`, `failed`, `cancelled` or `encoded`.
    public var outcome: String?

    public init(node: String, startedAt: Date = .now, endedAt: Date? = nil, outcome: String? = nil) {
        self.node = node
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.outcome = outcome
    }
}

public struct Lease: Hashable, Sendable, Codable {
    public var node: String
    public var expiresAt: Date

    public init(node: String, expiresAt: Date) {
        self.node = node
        self.expiresAt = expiresAt
    }
}

public struct JobProgress: Hashable, Sendable, Codable {
    public var fraction: Double?
    public var seconds: Double?
    public var fps: Double?
    public var speed: Double?
    public var updatedAt: Date

    public init(fraction: Double? = nil, seconds: Double? = nil, fps: Double? = nil, speed: Double? = nil, updatedAt: Date = .now) {
        self.fraction = fraction
        self.seconds = seconds
        self.fps = fps
        self.speed = speed
        self.updatedAt = updatedAt
    }
}

public struct EncodeResult: Hashable, Sendable, Codable {
    public var sizeBytes: Int64?
    /// The output's stream kinds and codecs in order, as probed, so a person can see what was made.
    public var streams: [String]
    public var layoutMatched: Bool

    public init(sizeBytes: Int64? = nil, streams: [String], layoutMatched: Bool) {
        self.sizeBytes = sizeBytes
        self.streams = streams
        self.layoutMatched = layoutMatched
    }
}

public struct PlacementSummary: Hashable, Sendable, Codable {
    public var destination: String
    public var presentation: String?
    public var writes: [String]
    public var placedAt: Date

    public init(destination: String, presentation: String?, writes: [String], placedAt: Date = .now) {
        self.destination = destination
        self.presentation = presentation
        self.writes = writes
        self.placedAt = placedAt
    }
}

/// What a node asks the silo, and what the silo answers. Two implementations: over HTTP, for a
/// node on another machine, and in-process, for the node the silo runs inside itself.
public protocol JobsAPI: Sendable {
    /// The next job this node can do, leased to it; nil when there is none.
    func claim(node: String, capabilities: Set<String>) async throws -> Job?
    /// Progress doubles as heartbeat; the state that comes back is how a node learns of a cancel.
    func report(_ job: String, progress: JobProgress) async throws -> JobState
    func complete(_ job: String, output: FileRef, result: EncodeResult) async throws -> Job
    func fail(_ job: String, reason: String) async throws -> Job
}

extension String {
    func leftPadded(to width: Int, with pad: Character = "0") -> String {
        count >= width ? self : String(repeating: pad, count: width - count) + self
    }
}
