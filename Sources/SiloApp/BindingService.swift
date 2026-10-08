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
package struct BadApplication: Error {
    package var reason: String
}
package struct NoSuchRecipe: Error {}
package struct BadAdjustment: Error {
    package var reason: String
}
package struct CommittedRecipe: Error {
    package var reason: String
}

/// Bindings made, and rulesets applied to them: every check a binding must pass before it is kept,
/// and an application of a ruleset — at a version, for some or all of its outputs — making a draft
/// recipe for each output. A binding names no ruleset, so applying another, or the same one at a
/// newer version, is the same act made again.
@Singleton
package struct BindingService: Sendable {
    private let config: SiloConfig
    private let settings: SettingsStore
    private let index: Index
    private let rulesets: RulesetStore
    private let sources: SourceStore
    private let bindings: BindingStore
    private let recipes: RecipeStore
    private let logger = Logger(label: "silo.bindings")

    @Inject
    package init(config: SiloConfig, settings: SettingsStore, index: Index, rulesets: RulesetStore, sources: SourceStore, bindings: BindingStore, recipes: RecipeStore) {
        self.config = config
        self.settings = settings
        self.index = index
        self.rulesets = rulesets
        self.sources = sources
        self.bindings = bindings
        self.recipes = recipes
    }

    /// Checks a binding whole and keeps it, or refuses it, keeping nothing.
    package func make(_ binding: Binding) throws -> Binding {
        _ = try entry(of: binding)
        try bindings.insert(binding)
        logger.info("bound \(binding.item) as \(binding.id)")
        return binding
    }

    /// Applies a ruleset to a binding: resolves it once for each output the application makes, and
    /// keeps a draft for each — or, when any output cannot be resolved, keeps nothing. Every recipe
    /// the binding already has is left as it was.
    package func apply(_ application: Application, to id: String) throws -> [StoredRecipe] {
        guard let binding = bindings.binding(id) else { throw NoSuchBinding() }
        guard let name = application.ruleset ?? settings.current.libraries.first(where: { $0.id == binding.library })?.ruleset else {
            throw BadApplication(reason: "the application names no ruleset, and library \(binding.library) has none of its own")
        }
        guard let ruleset = try rulesets.ruleset(named: name, version: application.version) else {
            throw BadApplication(reason: "no ruleset \(name)\(application.version.map { "@\($0)" } ?? "")")
        }
        let outputs: [OutputPolicy]
        if let chosen = application.outputs {
            outputs = try chosen.map { choice in
                guard let output = ruleset.outputs.first(where: { $0.profile == choice.profile }) else {
                    throw BadApplication(reason: choice.profile.map { "\(ruleset.name) makes no output for the profile \($0)" } ?? "\(ruleset.name) makes no unqualified output")
                }
                return output
            }
        } else {
            outputs = ruleset.outputs
        }
        let entry: Entry
        do {
            entry = try self.entry(of: binding)
        } catch let error as BadBinding {
            // A binding was checked when it was made; one that no longer holds — a library removed,
            // say — cannot be resolved, which is the application's failure, not a malformed request.
            throw Unresolvable(reason: error.reason)
        }
        let layers = try self.layers(of: binding, lineage: entry.lineage)
        let made = try outputs.map { output in
            let facts = SourceFacts(input: entry.joined.spec, roles: entry.roles, kind: entry.kind, profile: output.profile, duration: entry.joined.duration)
            do throws(ResolutionError) {
                let recipe = try RecipeResolver.resolve(facts, with: ruleset, layers: layers, mappings: binding.tracks)
                return StoredRecipe(binding: binding.id, facts: facts, resolved: recipe)
            } catch {
                throw Unresolvable(reason: "\(output.profile.map { "the \($0) output" } ?? "the unqualified output"): \(error.description)")
            }
        }
        try recipes.insert(made)
        logger.info("applied \(RulesetRef(ruleset)) to \(binding.id): \(made.count) recipes")
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

    // MARK: - The stack

    /// The layers above the ruleset, nearest first: the rules in force of each container of the
    /// lineage, from the item's own up, as the index holds their sidecars now. A container with no
    /// sidecar, or no `<rules>`, has no layer; one whose rules cannot be read refuses the application.
    private func layers(of binding: Binding, lineage: [SmdKit.Container]) throws -> [RulesLayer] {
        guard let library = config.library(binding.library) else { return [] }
        var layers: [RulesLayer] = []
        for container in lineage.reversed() {
            guard let row = try index.container(container.id), let reference = try index.sidecar(container.id)?.rules else { continue }
            let folder = row.folder.isEmpty ? library.root : library.root.appendingPathComponent(row.folder, isDirectory: true)
            do throws(RulesLayerError) {
                layers.append(try RulesLayerFile.read(.container(container.id.value), reference, in: folder))
            } catch {
                throw Unresolvable(reason: error.description)
            }
        }
        return layers
    }

    // MARK: - Checking

    /// What a binding knows of its entry, once it is checked: the item's kind, the role each mapped
    /// audio stream takes from its feature, and the segments joined.
    private struct Entry {
        var kind: EntryType?
        var roles: [Int: AudioRole]
        var joined: JoinedMedia
        /// The item's container and every one above it, root first.
        var lineage: [SmdKit.Container]
    }

    private func entry(of binding: Binding) throws -> Entry {
        guard config.library(binding.library) != nil else { throw BadBinding(reason: "no library \(binding.library)") }
        let lineage: [SmdKit.Container]
        do {
            lineage = try binding.containers.map { try ContainerFile.container(from: Data($0.utf8)) }
        } catch {
            throw BadBinding(reason: "a container document cannot be read: \(error.localizedDescription)")
        }
        guard let target = lineage.last else { throw BadBinding(reason: "a binding needs the item's container") }
        let entries = target.sequences.flatMap(\.items) + target.extras
        guard let item = entries.first(where: { $0.id?.value == binding.item }) else {
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
        return Entry(kind: item.type, roles: roles, joined: joined, lineage: lineage)
    }
}
