// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloClient
import SiloKit

// MARK: - Trials

extension AdminConsole {
    /// A trial job, as the console follows it.
    public typealias TrialJob = SiloKit.Job

    /// What trying a branch's version on one binding made: a trial job for each recipe the
    /// application made, or the silo's refusal of the application or a job, in its words.
    public struct TrialStart: Hashable, Sendable {
        public var binding: String
        public var jobs: [SiloKit.Job]
        public var refusal: String?
    }

    /// A binding worth trying a branch on: one whose placed presentation the branch would make
    /// differently, as its impact on the standard says.
    public struct TrialCandidate: Hashable, Sendable, Identifiable {
        public var binding: String
        public var container: String?
        public var item: String?
        public var profile: String?
        public var id: String { "\(binding)/\(profile ?? "")" }
    }

    /// The bindings the branch's impact lists, each once, in the impact's order: what is offered first
    /// to try a branch on.
    public func trialCandidates(of ruleset: String, branch: String, on silo: Silo) async throws -> [TrialCandidate] {
        try await withOperator(silo) { client in
            var candidates: [TrialCandidate] = []
            for entry in try await client.impact(ofBranch: branch, of: ruleset) {
                guard let recipe = try? await client.recipe(entry.recipe),
                    !candidates.contains(where: { $0.binding == recipe.binding })
                else { continue }
                candidates.append(
                    TrialCandidate(
                        binding: recipe.binding,
                        container: entry.container,
                        item: entry.item,
                        profile: entry.profile
                    )
                )
            }
            return candidates
        }
    }

    /// Applies a branch at a version to each binding and makes a trial job of every recipe it makes.
    /// Places nothing: a trial never enters the library.
    public func startTrials(
        of ruleset: String,
        branch: String,
        version: Int,
        on bindings: [String],
        of silo: Silo
    ) async throws -> [TrialStart] {
        try await withOperator(silo) { client in
            var started: [TrialStart] = []
            for binding in bindings {
                do {
                    var jobs: [SiloKit.Job] = []
                    for recipe in try await client.apply(
                        Application(ruleset: ruleset, branch: branch, version: version),
                        to: binding
                    ) {
                        jobs.append(try await client.createJob(recipe: recipe.id, trial: true))
                    }
                    started.append(TrialStart(binding: binding, jobs: jobs))
                } catch SiloClientError.status(let status, let body) where status != 401 {
                    started.append(TrialStart(binding: binding, jobs: [], refusal: Self.detail(body)))
                }
            }
            return started
        }
    }

    /// One stream of a trial beside the same stream as placed: what each recipe decided for it.
    public struct StreamComparison: Hashable, Sendable {
        public var stream: String
        public var placed: Action?
        public var tried: Action?
    }

    /// A tried trial beside the presentation its binding placed for the same output, when the
    /// branch's impact lists one: each stream's decision in both recipes, and where both files are
    /// served to play.
    public struct TrialComparison: Hashable, Sendable {
        public var trial: SiloClient.Trial
        public var streams: [StreamComparison]
        public var trialFile: URL
        /// Where the placed presentation is served; nil when no placed one is known.
        public var placedFile: URL?
    }

    /// The tried trials of a ruleset's branch, each compared with what its binding placed.
    public func trials(of ruleset: String, branch: String, on silo: Silo) async throws -> [TrialComparison] {
        try await withOperator(silo) { client in
            let trials = try await client.trials(ruleset: ruleset, branch: branch)
            guard !trials.isEmpty else { return [] }
            // What the binding placed, as the branch's impact on the standard knows it.
            var placed: [String: (recipe: StoredRecipe, presentation: String?)] = [:]
            for entry in (try? await client.impact(ofBranch: branch, of: ruleset)) ?? [] {
                guard let recipe = try? await client.recipe(entry.recipe) else { continue }
                placed["\(recipe.binding)/\(recipe.recipe.output.profile ?? "")"] = (recipe, entry.presentation)
            }
            var compared: [TrialComparison] = []
            for trial in trials {
                let tried = try await client.recipe(trial.recipe)
                let beside = placed["\(trial.binding)/\(trial.profile ?? "")"]
                compared.append(
                    TrialComparison(
                        trial: trial,
                        streams: Self.streams(placed: beside?.recipe.recipe, tried: tried.recipe),
                        trialFile: client.trialFileURL(trial.job),
                        placedFile: beside?.presentation.map(client.mediaURL)
                    )
                )
            }
            return compared
        }
    }

    /// The trial jobs the console started, as the silo has them now: how far each has got.
    public func trialJobs(_ ids: [String], on silo: Silo) async throws -> [SiloKit.Job] {
        try await withOperator(silo) { client in
            var jobs: [SiloKit.Job] = []
            for id in ids {
                if let job = try? await client.job(id) { jobs.append(job) }
            }
            return jobs
        }
    }

    public func deleteTrial(_ job: String, on silo: Silo) async throws {
        try await withOperator(silo) { try await $0.deleteTrial(job) }
    }

    /// Each stream either recipe decides, in the source's order, with what each decided.
    static func streams(placed: Recipe?, tried: Recipe) -> [StreamComparison] {
        func key(_ decision: StreamDecision) -> String { "\(decision.kind.rawValue) \(decision.sourceIndex)" }
        var order: [String] = []
        var placedActions: [String: Action] = [:]
        var triedActions: [String: Action] = [:]
        for decision in placed?.decisions ?? [] {
            if placedActions[key(decision)] == nil { order.append(key(decision)) }
            placedActions[key(decision)] = decision.action
        }
        for decision in tried.decisions {
            if placedActions[key(decision)] == nil, triedActions[key(decision)] == nil { order.append(key(decision)) }
            triedActions[key(decision)] = decision.action
        }
        return order.map { StreamComparison(stream: $0, placed: placedActions[$0], tried: triedActions[$0]) }
    }
}
