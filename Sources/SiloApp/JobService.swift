// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import Logging
import SiloKit
import SiloLibrary
import SiloStore
import SmdKit
import SmdSidecar
import Wire
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The job's states and every transition between them, in one place, with the job store as the
/// only thing it writes but for the one recipe a job commits. The controllers translate; the
/// embedded node calls this directly.
@Singleton
package struct JobService: Sendable, JobsAPI {
    package static let leaseLength: TimeInterval = 120
    package static let attemptsAllowed = 3

    private let config: SiloConfig
    private let jobs: JobStore
    private let sources: SourceStore
    private let bindings: BindingStore
    private let recipes: RecipeStore
    private let index: Index
    private let logger = Logger(label: "silo.jobs")

    @Inject
    package init(config: SiloConfig, jobs: JobStore, sources: SourceStore, bindings: BindingStore, recipes: RecipeStore, index: Index) {
        self.config = config
        self.jobs = jobs
        self.sources = sources
        self.bindings = bindings
        self.recipes = recipes
        self.index = index
    }

    // MARK: - Reading

    package func all(state: JobState? = nil) throws -> [Job] {
        try reclaimLapsed()
        return jobs.all().filter { state == nil || $0.state == state }
    }

    package func job(_ id: String) throws -> Job {
        try reclaimLapsed()
        guard let job = jobs.job(id) else { throw NoSuchJob() }
        return job
    }

    // MARK: - The operator's side

    /// A job from a draft recipe: the recipe is committed, so one recipe is run by one job, and the
    /// job is pending. Refused while any source of the recipe's binding has no copy, since no node
    /// could fetch it; the recipe then stays a draft.
    package func make(from id: String) throws -> Job {
        guard let recipe = recipes.recipe(id) else { throw NoSuchRecipe() }
        guard recipe.state == .draft else { throw CommittedRecipe(reason: "recipe \(id) is committed; a job has been made from it") }
        guard let binding = bindings.binding(recipe.binding) else { throw Unrunnable(reason: "recipe \(id)'s binding \(recipe.binding) is gone") }
        for segment in binding.segments where sources.source(segment.source)?.copies.isEmpty ?? true {
            throw Unrunnable(reason: "source \(segment.source) has no copy; no node could fetch it")
        }
        do {
            _ = try recipes.commit(id)
        } catch let error as RecipeStoreError {
            throw CommittedRecipe(reason: error.description)
        }
        let job = Job(recipe: id, requirements: recipe.recipe.encoders.sorted())
        try jobs.insert(job)
        logger.info("made \(job.id) from recipe \(id), needs \(job.requirements)")
        return job
    }

    package func cancel(_ id: String) throws -> Job {
        guard let current = jobs.job(id) else { throw NoSuchJob() }
        switch current.state {
        case .pending, .encoded, .failed:
            return try jobs.update(id) { $0.state = .cancelled; $0.lease = nil }!
        case .claimed, .encoding:
            // The node learns at its next progress report and stops; its fail report finalises.
            return try jobs.update(id) { $0.state = .cancelling }!
        case .cancelling, .cancelled, .placing, .placed:
            throw WrongState(current.state, "cannot be cancelled")
        }
    }

    package func retry(_ id: String) throws -> Job {
        guard let current = jobs.job(id) else { throw NoSuchJob() }
        guard [.failed, .cancelled].contains(current.state) else { throw WrongState(current.state, "cannot be retried") }
        return try jobs.update(id) { job in
            job.state = .pending
            job.attempts.removeAll()
            job.failure = nil
            job.lease = nil
            job.progress = nil
            job.output = nil
            job.result = nil
        }!
    }

    // MARK: - JobsAPI, the node's side

    /// The first pending job the node can do, preferring one of whose every source it holds a copy,
    /// leased to it, with what the node needs to run it. Lapsed leases are reclaimed first, so a job a
    /// vanished node held is offered again.
    package func claim(node: String, capabilities: Set<String>) async throws -> Claim? {
        try reclaimLapsed()
        // Which jobs the node holds every source of, worked out before the job store's lock is taken.
        let held = Set(jobs.all().filter { $0.state == .pending }.filter { job in
            guard let sources = self.sources(of: job), !sources.isEmpty else { return false }
            return sources.allSatisfy { source in source.copies.contains { $0.holder == node } }
        }.map(\.id))
        let leased = try jobs.updateFirst(
            where: { $0.state == .pending && Set($0.requirements).isSubset(of: capabilities) },
            sortedBy: { a, b in
                let aHeld = held.contains(a.id)
                let bHeld = held.contains(b.id)
                return aHeld != bHeld ? aHeld : a.createdAt < b.createdAt
            }
        ) { job in
            job.state = .claimed
            job.lease = Lease(node: node, expiresAt: .now.addingTimeInterval(Self.leaseLength))
            job.attempts.append(Attempt(node: node))
            job.progress = nil
        }
        return leased.map { claim(of: $0, by: node) }
    }

    /// A leased job with its committed recipe and each of its binding's segments: one copy of the
    /// segment's source, the claimant's own first, and the segment's span in seconds. A job whose
    /// recipe, binding or copies have gone is handed over without its recipe, which the node fails.
    private func claim(of job: Job, by node: String) -> Claim {
        let unrunnable = Claim(job: job, recipe: nil, segments: [])
        guard let recipe = recipes.recipe(job.recipe), let binding = bindings.binding(recipe.binding) else { return unrunnable }
        var held: [String: Source] = [:]
        for segment in binding.segments {
            if let source = sources.source(segment.source) { held[source.id] = source }
        }
        guard let joined = try? JoinedMedia(binding.segments, specs: held.mapValues(\.input)) else { return unrunnable }
        var segments: [ClaimedSegment] = []
        for timed in joined.segments {
            let copies = held[timed.source]?.copies ?? []
            guard let copy = copies.first(where: { $0.holder == node }) ?? copies.first else { return unrunnable }
            segments.append(timed.isWhole
                ? ClaimedSegment(source: timed.source, copy: copy)
                : ClaimedSegment(source: timed.source, copy: copy, start: timed.start, end: timed.end))
        }
        return Claim(job: job, recipe: recipe, segments: segments)
    }

    /// The sources a job's recipe's binding is made from, or nil when the recipe or binding has gone.
    private func sources(of job: Job) -> [Source]? {
        guard let recipe = recipes.recipe(job.recipe), let binding = bindings.binding(recipe.binding) else { return nil }
        return binding.segments.compactMap { sources.source($0.source) }
    }

    package func report(_ id: String, progress: JobProgress) async throws -> JobState {
        guard let current = jobs.job(id) else { throw NoSuchJob() }
        switch current.state {
        case .claimed, .encoding:
            return try jobs.update(id) { job in
                job.state = .encoding
                job.progress = progress
                job.lease = job.lease.map { Lease(node: $0.node, expiresAt: .now.addingTimeInterval(Self.leaseLength)) }
            }!.state
        default:
            return current.state
        }
    }

    package func complete(_ id: String, output: FileRef, result: EncodeResult) async throws -> Job {
        guard let current = jobs.job(id) else { throw NoSuchJob() }
        guard [.claimed, .encoding].contains(current.state) else { throw WrongState(current.state, "cannot be completed") }
        return try jobs.update(id) { job in
            job.output = output
            job.result = result
            job.lease = nil
            job.progress = JobProgress(fraction: 1)
            if var last = job.attempts.popLast() {
                last.endedAt = .now
                last.outcome = result.layoutMatched ? "encoded" : "failed"
                job.attempts.append(last)
            }
            if result.layoutMatched {
                job.state = .encoded
            } else {
                job.state = .failed
                job.failure = "the output's layout is not the recipe's"
            }
        }!
    }

    package func fail(_ id: String, reason: String) async throws -> Job {
        guard let current = jobs.job(id) else { throw NoSuchJob() }
        guard current.isActive else { throw WrongState(current.state, "cannot be failed") }
        return try jobs.update(id) { job in
            job.lease = nil
            if var last = job.attempts.popLast() {
                last.endedAt = .now
                last.outcome = job.state == .cancelling ? "cancelled" : "failed"
                job.attempts.append(last)
            }
            if job.state == .cancelling {
                job.state = .cancelled
            } else {
                job.state = .failed
                job.failure = reason
            }
        }!
    }

    /// A lease that lapsed is a node that vanished: the attempt is lost, and the job is offered
    /// again, or failed when it has been lost enough times.
    private func reclaimLapsed() throws {
        let now = Date.now
        try jobs.updateAll(where: { [.claimed, .encoding].contains($0.state) && ($0.lease?.expiresAt ?? now) < now }) { job in
            if var last = job.attempts.popLast() {
                last.endedAt = now
                last.outcome = "lost"
                job.attempts.append(last)
            }
            job.lease = nil
            job.progress = nil
            let lost = job.attempts.filter { $0.outcome == "lost" }.count
            if lost >= Self.attemptsAllowed {
                job.state = .failed
                job.failure = "lost by \(lost) nodes"
            } else {
                job.state = .pending
            }
        }
    }

    // MARK: - Placement

    /// Fetches the output from the node that holds it into the library's own filesystem, places
    /// it as the recipe's binding says, in the profile of the recipe's output, and re-scans so the
    /// index learns of it.
    package func place(_ id: String) async throws -> Job {
        guard let current = jobs.job(id) else { throw NoSuchJob() }
        guard current.state == .encoded, let output = current.output, let stored = recipes.recipe(current.recipe),
            let binding = bindings.binding(stored.binding)
        else {
            throw WrongState(current.state, "cannot be placed")
        }
        guard let library = config.library(binding.library) else { throw NoSuchLibrary() }
        _ = try jobs.update(id) { $0.state = .placing }

        do {
            let incoming = library.root.appendingPathComponent(".silo/incoming", isDirectory: true)
            try FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)
            let staged = incoming.appendingPathComponent("\(id).\(output.url.pathExtension.isEmpty ? "mkv" : output.url.pathExtension)")
            if output.url.isFileURL {
                // The embedded node's output is on this filesystem already.
                try? FileManager.default.removeItem(at: staged)
                try FileManager.default.moveItem(at: output.url, to: staged)
            } else {
                try await Self.fetch(output, to: staged)
            }
            let lineage = try binding.containers.map { try ContainerFile.container(from: Data($0.utf8)) }
            var presentation = Presentation(alternative: binding.alternative, profile: stored.recipe.output.profile, file: "")
            presentation.tracks = stored.recipe.tracks(for: binding.tracks)
            presentation.chapters = binding.chapters
            presentation.source = binding.source
            let placement: Placement
            do {
                placement = try Placer.compute(PlacementRequest(library: library.root, lineage: lineage, item: binding.item, presentation: presentation, source: staged))
            } catch let error as PlacementError {
                throw PlacementRefusedError(reason: error.localizedDescription)
            }
            guard placement.isApplicable else {
                throw PlacementRefusedError(reason: placement.errors.map(\.description).joined(separator: "; "))
            }
            try Placer.apply(placement)
            _ = try Indexer.scan(library, into: index)
            let destination = LibraryWalker.relativePath(of: placement.destination, in: library.root)
            return try jobs.update(id) { job in
                job.state = .placed
                job.placement = PlacementSummary(destination: destination, presentation: IndexedPresentation.id(library: library.id, path: destination), writes: placement.describe(relativeTo: library.root))
            }!
        } catch {
            _ = try jobs.update(id) { job in
                job.state = .encoded
                job.failure = "placement: \(error.localizedDescription)"
            }
            throw error
        }
    }

    private static func fetch(_ file: FileRef, to destination: URL) async throws {
        var request = URLRequest(url: file.url)
        request.setValue(file.secret, forHTTPHeaderField: "x-silo-secret")
        let (temporary, response) = try await URLSession.shared.download(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw PlacementFetchError(status: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
    }
}

package struct NoSuchJob: Error {}
package struct WrongState: Error, CustomStringConvertible {
    package var state: JobState
    package var what: String
    package init(_ state: JobState, _ what: String) {
        self.state = state
        self.what = what
    }
    package var description: String { "a \(state.rawValue) job \(what)" }
}
/// A recipe no job can be made from: a source of its binding that no node holds, or its binding gone.
package struct Unrunnable: Error {
    package var reason: String
}
package struct PlacementRefusedError: Error, LocalizedError {
    package var reason: String
    package var errorDescription: String? { reason }
}
package struct PlacementFetchError: Error, LocalizedError {
    package var status: Int
    package var errorDescription: String? { "the node answered \(status) for the output" }
}
