// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import Logging
import SiloKit
import SiloStore
import SmdKit
import SmdSidecar
import Wire

package struct BadBinding: Error {
    package var reason: String
}
package struct NoSuchBinding: Error {}
package struct NoSuchRecipe: Error {}
package struct BadAdjustment: Error {
    package var reason: String
}
package struct CommittedRecipe: Error {
    package var reason: String
}

/// Bindings made and resolved: every check a binding must pass before it is kept, and the
/// resolution of a binding into a draft recipe for each output its ruleset makes. Nothing is stored
/// unless every output resolves, since a binding that cannot be made is not worth keeping.
@Singleton
package final class BindingService: Sendable {
    private let config: SiloConfig
    private let rulesets: RulesetStore
    private let sources: SourceStore
    private let bindings: BindingStore
    private let recipes: RecipeStore
    private let logger = Logger(label: "silo.bindings")

    @Inject
    package init(config: SiloConfig, rulesets: RulesetStore, sources: SourceStore, bindings: BindingStore, recipes: RecipeStore) {
        self.config = config
        self.rulesets = rulesets
        self.sources = sources
        self.bindings = bindings
        self.recipes = recipes
    }

    /// Checks a binding whole, resolves it once for each output it makes, and keeps the binding and
    /// its drafts — or refuses it, keeping nothing.
    package func make(_ binding: Binding) throws -> (binding: Binding, recipes: [StoredRecipe]) {
        let made = try resolve(binding)
        try bindings.insert(binding)
        try recipes.insert(made)
        logger.info("bound \(binding.item) as \(binding.id): \(made.count) recipes")
        return (binding, made)
    }

    /// Resolves a binding already made against its ruleset as it now stands, adding a draft for each
    /// output and leaving every recipe it already has as it was.
    package func resolveAgain(_ id: String) throws -> [StoredRecipe] {
        guard let binding = bindings.binding(id) else { throw NoSuchBinding() }
        let made = try resolve(binding)
        try recipes.insert(made)
        return made
    }

    package func binding(_ id: String) throws -> (binding: Binding, recipes: [StoredRecipe]) {
        guard let binding = bindings.binding(id) else { throw NoSuchBinding() }
        return (binding, recipes.recipes(of: id))
    }

    package func adjust(_ id: String, _ adjustments: [Adjustment]) throws -> StoredRecipe {
        guard let current = recipes.recipe(id) else { throw NoSuchRecipe() }
        let mappings = bindings.binding(current.binding)?.tracks ?? []
        do {
            guard let adjusted = try recipes.adjust(id, adjustments, mappings: mappings) else { throw NoSuchRecipe() }
            return adjusted
        } catch let error as AdjustmentError {
            throw BadAdjustment(reason: error.description)
        } catch let error as RecipeStoreError {
            throw CommittedRecipe(reason: error.description)
        }
    }

    package func discard(_ id: String) throws {
        do {
            guard try recipes.discard(id) != nil else { throw NoSuchRecipe() }
        } catch let error as RecipeStoreError {
            throw CommittedRecipe(reason: error.description)
        }
    }

    // MARK: - Checking and resolving

    private func resolve(_ binding: Binding) throws -> [StoredRecipe] {
        guard config.library(binding.library) != nil else { throw BadBinding(reason: "no library \(binding.library)") }
        guard let ruleset = try rulesets.ruleset(named: binding.ruleset, version: binding.rulesetVersion) else {
            throw BadBinding(reason: "no ruleset \(binding.ruleset)\(binding.rulesetVersion.map { "@\($0)" } ?? "")")
        }
        let lineage: [SmdKit.Container]
        do {
            lineage = try binding.containers.map { try ContainerFile.container(from: Data($0.utf8)) }
        } catch {
            throw BadBinding(reason: "a container document cannot be read: \(error.localizedDescription)")
        }
        guard let target = lineage.last else { throw BadBinding(reason: "a binding needs the item's container") }
        let entries = target.sequences.flatMap(\.items) + target.extras
        guard let entry = entries.first(where: { $0.id == binding.item }) else {
            throw BadBinding(reason: "\(target.displayTitle) has no item \(binding.item)")
        }
        if let alternative = binding.alternative, !target.alternatives.contains(where: { $0.id == alternative }) {
            throw BadBinding(reason: "\(target.displayTitle) has no alternative \(alternative)")
        }

        var specs: [String: InputSpec] = [:]
        for segment in binding.segments {
            if let source = sources.source(segment.source) { specs[source.id] = source.input }
        }
        let joined: JoinedMedia
        do {
            joined = try JoinedMedia(binding.segments, specs: specs)
        } catch {
            throw BadBinding(reason: error.description)
        }

        let audioStreams = joined.spec.streams.filter { $0.kind == .audio }.count
        let subtitleStreams = joined.spec.streams.filter { $0.kind == .subtitle }.count
        var roles: [Int: AudioRole] = [:]
        for track in binding.tracks {
            guard let feature = target.features.first(where: { $0.id == track.feature }) else {
                throw BadBinding(reason: "\(target.displayTitle) has no feature \(track.feature)")
            }
            if let audio = track.audio {
                guard audio >= 1, audio <= audioStreams else {
                    throw BadBinding(reason: "feature \(track.feature) is mapped to audio \(audio), which the joined media does not have")
                }
                roles[audio] = switch feature.type {
                case .commentary: .commentary
                case .isolatedMusic: .isolatedMusic
                default: .other
                }
            }
            if let subtitle = track.subtitle, subtitle < 1 || subtitle > subtitleStreams {
                throw BadBinding(reason: "feature \(track.feature) is mapped to subtitle \(subtitle), which the joined media does not have")
            }
        }

        let outputs: [OutputPolicy]
        if let chosen = binding.outputs {
            outputs = try chosen.map { choice in
                guard let output = ruleset.outputs.first(where: { $0.profile == choice.profile }) else {
                    throw BadBinding(reason: choice.profile.map { "\(ruleset.name) makes no output for the profile \($0)" } ?? "\(ruleset.name) makes no unqualified output")
                }
                return output
            }
        } else {
            outputs = ruleset.outputs
        }

        return try outputs.map { output in
            let facts = SourceFacts(input: joined.spec, roles: roles, kind: entry.type, profile: output.profile, duration: joined.duration)
            do throws(ResolutionError) {
                let recipe = try RecipeResolver.resolve(facts, with: ruleset, mappings: binding.tracks)
                return StoredRecipe(binding: binding.id, facts: facts, resolved: recipe)
            } catch {
                throw Unresolvable(reason: "\(output.profile.map { "the \($0) output" } ?? "the unqualified output"): \(error.description)")
            }
        }
    }
}
