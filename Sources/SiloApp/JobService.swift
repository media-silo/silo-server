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

/// The job's states and every transition between them, in one place, with the store as the only
/// thing it writes. The controllers translate; the embedded node calls this directly.
@Singleton
package final class JobService: Sendable, JobsAPI {
    package static let leaseLength: TimeInterval = 120
    package static let attemptsAllowed = 3

    private let config: SiloConfig
    private let jobs: JobStore
    private let rulesets: RulesetStore
    private let index: Index
    private let logger = Logger(label: "silo.jobs")

    @Inject
    package init(config: SiloConfig, jobs: JobStore, rulesets: RulesetStore, index: Index) {
        self.config = config
        self.jobs = jobs
        self.rulesets = rulesets
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

    // MARK: - The tool's side

    package func register(source: FileRef, discName: String?, probe: ProbedSource?, makeMKV: MakeMKVFacts?) throws -> Job {
        let job = Job(source: source, discName: discName, probe: probe, makeMKV: makeMKV)
        try jobs.insert(job)
        logger.info("registered \(job.id) from \(source.holder)")
        return job
    }

    /// The assignment lands: facts are merged, the recipe resolved, and the job is pending. A
    /// stream no rule decides is refused here, with the stream, while the disc is in the drive.
    package func assign(_ id: String, _ assignment: Assignment) throws -> Job {
        guard let current = jobs.job(id) else { throw NoSuchJob() }
        guard [.unassigned, .pending, .failed].contains(current.state) else { throw WrongState(current.state, "cannot be assigned") }
        guard let probe = current.probe else { throw BadAssignment(reason: "the job carries no probe of its source; the tool must send what ffprobe saw") }
        guard config.library(assignment.library) != nil else { throw BadAssignment(reason: "no library \(assignment.library)") }
        guard let ruleset = try rulesets.ruleset(named: assignment.ruleset, version: assignment.rulesetVersion) else {
            throw BadAssignment(reason: "no ruleset \(assignment.ruleset)\(assignment.rulesetVersion.map { "@\($0)" } ?? "")")
        }
        let lineage: [SmdKit.Container]
        do {
            lineage = try assignment.containers.map { try ContainerFile.container(from: Data($0.utf8)) }
        } catch {
            throw BadAssignment(reason: "a container document cannot be read: \(error.localizedDescription)")
        }
        guard let target = lineage.last else { throw BadAssignment(reason: "an assignment needs the item's container") }
        let entries = target.sequences.flatMap(\.items) + target.extras
        guard let entry = entries.first(where: { $0.id == assignment.item }) else {
            throw BadAssignment(reason: "\(target.displayTitle) has no item \(assignment.item)")
        }
        var roles: [Int: AudioRole] = [:]
        for track in assignment.tracks {
            guard let feature = target.features.first(where: { $0.id == track.feature }) else {
                throw BadAssignment(reason: "\(target.displayTitle) has no feature \(track.feature)")
            }
            if let audio = track.audio {
                roles[audio] = switch feature.type {
                case .commentary: .commentary
                case .isolatedMusic: .isolatedMusic
                default: .other
                }
            }
        }
        let facts = SourceFacts(probe: probe, makeMKV: current.makeMKV, roles: roles, kind: entry.type, profile: assignment.profile)
        let recipe: Recipe
        do {
            recipe = try RecipeResolver.resolve(facts, with: ruleset, mappings: assignment.tracks)
        } catch let error as ResolutionError {
            throw Unresolvable(reason: error.description)
        }
        var stored = assignment
        stored.rulesetVersion = ruleset.version
        let updated = try jobs.update(id) { job in
            job.assignment = stored
            job.facts = facts
            job.recipe = recipe
            job.requirements = recipe.encoders.sorted()
            job.state = .pending
            job.failure = nil
            job.lease = nil
            job.progress = nil
        }
        logger.info("assigned \(id): \(recipe.decisions.count) streams, needs \(recipe.encoders.sorted())")
        return updated!
    }

    package func cancel(_ id: String) throws -> Job {
        guard let current = jobs.job(id) else { throw NoSuchJob() }
        switch current.state {
        case .unassigned, .pending, .encoded, .failed:
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
            job.state = job.recipe == nil ? .unassigned : .pending
            job.attempts.removeAll()
            job.failure = nil
            job.lease = nil
            job.progress = nil
            job.output = nil
            job.result = nil
        }!
    }

    // MARK: - JobsAPI, the node's side

    /// The first pending job the node can do, preferring one whose source it already holds, leased
    /// to it. Lapsed leases are reclaimed first, so a job a vanished node held is offered again.
    package func claim(node: String, capabilities: Set<String>) async throws -> Job? {
        try reclaimLapsed()
        return try jobs.updateFirst(
            where: { $0.state == .pending && Set($0.requirements).isSubset(of: capabilities) },
            sortedBy: { a, b in
                let aLocal = a.source.holder == node
                let bLocal = b.source.holder == node
                return aLocal != bLocal ? aLocal : a.createdAt < b.createdAt
            }
        ) { job in
            job.state = .claimed
            job.lease = Lease(node: node, expiresAt: .now.addingTimeInterval(Self.leaseLength))
            job.attempts.append(Attempt(node: node))
            job.progress = nil
        }
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
    /// it as the assignment says, and re-scans so the index learns of it.
    package func place(_ id: String) async throws -> Job {
        guard let current = jobs.job(id) else { throw NoSuchJob() }
        guard current.state == .encoded, let output = current.output, let assignment = current.assignment else {
            throw WrongState(current.state, "cannot be placed")
        }
        guard let library = config.library(assignment.library) else { throw NoSuchLibrary() }
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
            let lineage = try assignment.containers.map { try ContainerFile.container(from: Data($0.utf8)) }
            var presentation = Presentation(alternative: assignment.alternative, profile: assignment.profile, file: "")
            presentation.tracks = current.recipe?.tracks(for: assignment.tracks) ?? assignment.tracks
            presentation.chapters = assignment.chapters
            presentation.source = assignment.source
            let placement: Placement
            do {
                placement = try Placer.compute(PlacementRequest(library: library.root, lineage: lineage, item: assignment.item, presentation: presentation, source: staged))
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
package struct BadAssignment: Error {
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
