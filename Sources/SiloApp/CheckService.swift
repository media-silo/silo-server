// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Logging
import ServiceLifecycle
import SiloKit
import SiloStore
import SmdKit
import SmdSidecar
import Wire
import WireMVC

/// Whether the rules in force would make each placed presentation differently. A presentation is
/// checked by resolving its binding's facts again through the stack that applies to it now, with
/// its item read from its container as the library holds it now, and the outcome recorded. The work
/// left is every placed presentation whose latest check was against another stack or another
/// reading of its item, so a pass stopped half way resumes with what is left, and a change of rules
/// or of an item's container reaches exactly the presentations it changes.
///
/// It runs while the silo runs: a pass at start, and another whenever a change of rules asks for
/// one through the `CheckSignal`. A pass records each check as it finishes, so stopping the silo
/// part way loses only the one in flight, and the next pass picks up what is left.
/// `LayeredRulesets.md`, *The background check*.
@Singleton
@BackgroundService
package struct CheckService: Service, Sendable {
    private let jobs: JobStore
    private let recipes: RecipeStore
    private let bindings: BindingStore
    private let sources: SourceStore
    private let rulesets: RulesetStore
    private let stack: RulesStack
    private let checks: CheckStore
    private let index: Index
    private let libraries: Libraries
    private let bindingService: BindingService
    private let signal: CheckSignal
    private let logger = Logger(label: "silo.checks")

    @Inject
    package init(
        jobs: JobStore,
        recipes: RecipeStore,
        bindings: BindingStore,
        sources: SourceStore,
        rulesets: RulesetStore,
        stack: RulesStack,
        checks: CheckStore,
        index: Index,
        libraries: Libraries,
        bindingService: BindingService,
        signal: CheckSignal
    ) {
        self.jobs = jobs
        self.recipes = recipes
        self.bindings = bindings
        self.sources = sources
        self.rulesets = rulesets
        self.stack = stack
        self.checks = checks
        self.index = index
        self.libraries = libraries
        self.bindingService = bindingService
        self.signal = signal
    }

    // MARK: - Running

    /// A pass at start, then one for each request the signal coalesces, until cancelled or the silo
    /// shuts down. A pass that fails is logged, and the next request tries again.
    package func run() async {
        await cancelWhenGracefulShutdown {
            signal.request()
            for await _ in signal.requests {
                if Task.isCancelled { return }
                do {
                    try pass()
                } catch {
                    logger.error("the check stopped: \(error)")
                }
            }
        }
    }

    // MARK: - Checking

    /// What a placed job's recipe was resolved from, and what applies to it now.
    private struct Placed {
        var job: Job
        var recipe: StoredRecipe
        var binding: Binding
    }

    private func placed() -> [Placed] {
        jobs.all().compactMap { job in
            guard job.state == .placed, let recipe = recipes.recipe(job.recipe),
                let binding = bindings.binding(recipe.binding)
            else { return nil }
            return Placed(job: job, recipe: recipe, binding: binding)
        }
    }

    /// The ruleset in force for a recipe: the head of the branch its version is on, or of the
    /// standard once that branch is promoted. `branch` checks a branch's head instead, for impact.
    private func ruleset(for recipe: Recipe, onBranch branch: String? = nil) throws -> Ruleset? {
        let name = recipe.ruleset.name
        var line =
            branch ?? recipe.ruleset.version.flatMap { try? rulesets.branch(of: name, version: $0) }
            ?? RulesetStore.standard
        if branch == nil, line != RulesetStore.standard,
            try rulesets.branches(of: name).first(where: { $0.name == line })?.closed != false
        {
            line = RulesetStore.standard
        }
        guard let head = try rulesets.head(of: name, branch: line) else { return nil }
        return try rulesets.ruleset(named: name, version: head)
    }

    /// Resolves a placed recipe's facts again through the rules in force — or through a branch's head,
    /// or a draft, in place of its ruleset's — and says what that decides otherwise.
    private func resolveAgain(
        _ placed: Placed,
        onBranch branch: String? = nil,
        replacing draft: Ruleset? = nil
    ) throws -> CheckRecord {
        let recorded = placed.recipe.recipe
        guard let ruleset = try draft ?? ruleset(for: recorded, onBranch: branch) else {
            return CheckRecord(
                job: placed.job.id,
                recipe: placed.recipe.id,
                checkedAgainst: recorded.stack,
                outcome: .unresolvable,
                reason: "the ruleset \(recorded.ruleset.name) is not there"
            )
        }
        let now: (facts: SourceFacts, lineage: [SmdKit.Container])
        let layers: [RulesLayer]
        do {
            now = try factsNow(placed)
            layers = try stack.layers(of: placed.binding, lineage: now.lineage)
        } catch let error as Unresolvable {
            return CheckRecord(
                job: placed.job.id,
                recipe: placed.recipe.id,
                checkedAgainst: CheckedStack(ruleset: RulesetRef(ruleset), layers: []),
                outcome: .unresolvable,
                reason: error.reason
            )
        }
        let against = CheckedStack(ruleset: RulesetRef(ruleset), layers: layers.map(\.reference))
        let profile = recorded.output.profile
        guard profile == nil || ruleset.outputs.contains(where: { $0.profile == profile }) else {
            return CheckRecord(
                job: placed.job.id,
                recipe: placed.recipe.id,
                checkedAgainst: against,
                outcome: .unresolvable,
                reason: "the rules make no \(profile!) output",
                item: now.facts.item
            )
        }
        let again: Recipe
        do throws(ResolutionError) {
            again = try RecipeResolver.resolve(
                now.facts,
                with: ruleset,
                layers: layers,
                mappings: placed.binding.tracks
            )
        } catch {
            return CheckRecord(
                job: placed.job.id,
                recipe: placed.recipe.id,
                checkedAgainst: against,
                outcome: .unresolvable,
                reason: error.description,
                item: now.facts.item
            )
        }
        let changes = recorded.changes(to: again)
        let output = again.output == recorded.output ? nil : "the output becomes \(again.output.container)"
        let outOfDate = !changes.isEmpty || output != nil
        // What moved in the item's container is said only when it changed a decision.
        let moves = outOfDate ? placed.recipe.facts.item.moves(to: now.facts.item) : []
        let reasons = [output].compactMap { $0 } + moves
        return CheckRecord(
            job: placed.job.id,
            recipe: placed.recipe.id,
            checkedAgainst: against,
            outcome: outOfDate ? .outOfDate : .current,
            changes: changes,
            reason: reasons.isEmpty ? nil : reasons.joined(separator: "; "),
            item: now.facts.item
        )
    }

    /// The stack that applies to a placed recipe now, or nil when it cannot be read.
    private func stackInForce(_ placed: Placed) -> CheckedStack? {
        guard let ruleset = try? ruleset(for: placed.recipe.recipe),
            let layers = try? stack.layers(of: placed.binding, lineage: stack.lineage(of: placed.binding))
        else { return nil }
        return CheckedStack(ruleset: RulesetRef(ruleset), layers: layers.map(\.reference))
    }

    private func needsCheck(_ placed: Placed) -> Bool {
        guard let last = checks.check(of: placed.job.id) else { return true }
        return last.checkedAgainst != stackInForce(placed) || last.item != (try? factsNow(placed))?.facts.item
    }

    /// Checks every placed presentation not yet checked against the rules in force, recording each
    /// as it goes, until done or `stop` says to stop. Answers how many it checked.
    @discardableResult
    package func pass(stop: () -> Bool = { Task.isCancelled }) throws -> Int {
        var checked = 0
        for placed in placed() where needsCheck(placed) {
            if stop() { break }
            try checks.record(try resolveAgain(placed))
            checked += 1
        }
        if checked > 0 { logger.info("checked \(checked) placed presentations against the rules in force") }
        return checked
    }

    // MARK: - Reporting

    /// An out-of-date presentation as the report gives it.
    package struct Reported: Sendable {
        package var presentation: IndexedPresentation?
        package var recipe: StoredRecipe
        package var check: CheckRecord
        package var sources: [Source]
    }

    /// A library's out-of-date presentations from the check records, how many placed ones are still
    /// to be checked, and how many were placed without a job.
    package func report(library: String) throws -> (outOfDate: [Reported], pending: Int, placedWithoutJob: Int) {
        guard libraries.library(library) != nil else { throw NoSuchLibrary() }
        let here = placed().filter { $0.binding.library == library }
        let reported = here.compactMap { placed -> Reported? in
            guard let check = checks.check(of: placed.job.id), check.outcome != .current else { return nil }
            return reported(placed, check)
        }
        let byJob = Set(here.compactMap(\.job.placement?.presentation))
        return (
            reported, here.filter(needsCheck).count, try presentations(in: library).filter { !byJob.contains($0) }.count
        )
    }

    /// What promoting a branch would put out of date: every placed presentation made under the
    /// standard of that ruleset, resolved through the branch's head in its place. Records nothing.
    package func impact(of branch: String, of name: String) throws -> [Reported] {
        guard try rulesets.branches(of: name).contains(where: { $0.name == branch }) else { throw NoSuchRuleset() }
        return try placed().compactMap { placed -> Reported? in
            let recorded = placed.recipe.recipe.ruleset
            guard recorded.name == name,
                recorded.version.flatMap({ try? rulesets.branch(of: name, version: $0) }) == RulesetStore.standard
            else { return nil }
            let check = try resolveAgain(placed, onBranch: branch)
            return check.outcome == .current ? nil : reported(placed, check)
        }
    }

    /// What a draft would put out of date were it stored as the head of its base's branch: every
    /// placed presentation whose committed recipe names a version on that branch, resolved through
    /// the draft in place of the ruleset and the rest of its stack as it stands. Records nothing.
    package func impact(ofDraft draft: Ruleset, basedOn base: Int, of name: String) throws -> [Reported] {
        guard let line = try rulesets.branch(of: name, version: base) else { throw NoSuchRuleset() }
        return try placed().compactMap { placed -> Reported? in
            let recorded = placed.recipe.recipe.ruleset
            guard recorded.name == name,
                recorded.version.flatMap({ try? rulesets.branch(of: name, version: $0) }) == line
            else { return nil }
            let check = try resolveAgain(placed, replacing: draft)
            return check.outcome == .current ? nil : reported(placed, check)
        }
    }

    /// How many placed presentations each version of a ruleset made, by version.
    package func made(by name: String) -> [Int: Int] {
        var counts: [Int: Int] = [:]
        for placed in placed() where placed.recipe.recipe.ruleset.name == name {
            guard let version = placed.recipe.recipe.ruleset.version else { continue }
            counts[version, default: 0] += 1
        }
        return counts
    }

    private func reported(_ placed: Placed, _ check: CheckRecord) -> Reported {
        Reported(
            presentation: placed.job.placement?.presentation.flatMap { try? index.presentation($0) },
            recipe: placed.recipe,
            check: check,
            sources: placed.binding.segments.compactMap { sources.source($0.source) }
        )
    }

    /// The ids of every presentation the index holds in a library.
    private func presentations(in library: String) throws -> [String] {
        var ids: [String] = []
        var pending = try index.roots(in: library, listedOnly: false).map(\.containerID)
        while let next = pending.popLast() {
            ids += try index.presentations(of: next, in: library).map(\.id)
            pending += try index.children(of: next, in: library).map(\.containerID)
        }
        return ids
    }
}

extension CheckService {
    /// The binding's lineage as the library holds it now: each container as the index has its
    /// sidecar, or as the binding has it where the index has none above the item. The item's own
    /// container has to be in the library.
    private func lineageNow(of binding: Binding) throws -> [SmdKit.Container] {
        let made = try stack.lineage(of: binding)
        guard let library = libraries.library(binding.library) else { return made }
        return try made.enumerated().map { position, container in
            if let now = try index.sidecar(container.id, in: library.id)?.container { return now }
            guard position < made.count - 1 else {
                throw Unresolvable(reason: "\(container.displayTitle) is no longer in the library")
            }
            return container
        }
    }

    /// A placed recipe's facts as its binding gives them now, its item read from the lineage as the
    /// library holds it, and that lineage. The facts that come from the sources are as they were,
    /// since a source does not change once registered.
    private func factsNow(_ placed: Placed) throws -> (facts: SourceFacts, lineage: [SmdKit.Container]) {
        let lineage = try lineageNow(of: placed.binding)
        do {
            let facts = try bindingService.facts(
                of: placed.binding,
                in: lineage,
                profile: placed.recipe.recipe.output.profile
            )
            return (facts, lineage)
        } catch let error as BadBinding {
            throw Unresolvable(reason: error.reason)
        }
    }
}
