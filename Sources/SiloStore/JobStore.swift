// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloKit
import Synchronization

/// Jobs as the silo keeps them: one JSON file per job under `<state>/jobs`, read once at start and
/// held in memory, every change written whole and atomically. Tens of records, not thousands.
///
/// A `Sendable` class rather than a struct or an actor. Every change is a read-modify-write of one
/// job under one lock — a claim has to pick a job and lease it as one step — and a `Mutex` is
/// non-copyable, so the type that owns it is the one instance the service and the embedded node
/// share. An actor would give that atomicity only up to its first suspension, and none of these
/// sections suspend; a lock gives it outright and lets the callers stay synchronous, which is
/// what keeps the job service testable without an async context.
public final class JobStore: Sendable {
    public let folder: URL
    private let jobs: Mutex<[String: Job]>

    public init(folder: URL) throws {
        self.folder = folder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var loaded: [String: Job] = [:]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        for file in files where file.pathExtension == "json" {
            if let job = try? decoder.decode(Job.self, from: try Data(contentsOf: file)) {
                loaded[job.id] = job
            }
        }
        jobs = Mutex(loaded)
    }

    /// In memory only, for tests.
    public init() {
        folder = URL(fileURLWithPath: "/dev/null")
        jobs = Mutex([:])
    }

    public func all() -> [Job] {
        jobs.withLock { Array($0.values) }.sorted { $0.createdAt < $1.createdAt }
    }

    public func job(_ id: String) -> Job? {
        jobs.withLock { $0[id] }
    }

    /// Reads, changes and writes one job under the lock, so that two transitions cannot cross.
    /// The change may throw, in which case nothing is written.
    @discardableResult
    public func update<Failure: Error>(_ id: String, _ change: (inout Job) throws(Failure) -> Void) throws -> Job? {
        try jobs.withLock { jobs -> Job? in
            guard var job = jobs[id] else { return nil }
            try change(&job)
            job.updatedAt = .now
            jobs[id] = job
            try write(job)
            return job
        }
    }

    /// Finds and changes one job under the lock: the claim, which must pick and lease atomically.
    public func updateFirst(where predicate: (Job) -> Bool, sortedBy order: (Job, Job) -> Bool, _ change: (inout Job) throws -> Void) throws -> Job? {
        try jobs.withLock { jobs -> Job? in
            guard var job = jobs.values.filter(predicate).sorted(by: order).first else { return nil }
            try change(&job)
            job.updatedAt = .now
            jobs[job.id] = job
            try write(job)
            return job
        }
    }

    /// Applies a change to every job the predicate matches: lapsed leases, at the moment they matter.
    public func updateAll(where predicate: (Job) -> Bool, _ change: (inout Job) -> Void) throws {
        try jobs.withLock { jobs in
            for (id, var job) in jobs where predicate(job) {
                change(&job)
                job.updatedAt = .now
                jobs[id] = job
                try write(job)
            }
        }
    }

    public func insert(_ job: Job) throws {
        try jobs.withLock { jobs in
            jobs[job.id] = job
            try write(job)
        }
    }

    private func write(_ job: Job) throws {
        guard folder.path != "/dev/null" else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(job).write(to: folder.appendingPathComponent("\(job.id).json"), options: .atomic)
    }
}
