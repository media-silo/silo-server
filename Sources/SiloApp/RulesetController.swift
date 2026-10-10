// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import OpenAPIRuntime  // swiftlint:disable:this unused_import
import SiloAPI
import SiloKit
import SmdKit
import SiloStore
import Wire
import WireMVC
import WireOpenAPI

/// Rulesets, read: the list, one document, a draft checked and its impact, and the dry run of the
/// resolver. Nothing here stores anything, so none of it is the operator's.
@Singleton
@OpenAPIController(spec: "SiloAPI")
package struct RulesetController {
    private let store: RulesetStore

    private let checks: CheckService

    @Inject
    package init(store: RulesetStore, checks: CheckService) {
        self.store = store
        self.checks = checks
    }

    /// Each ruleset with every version: its branch, its parent and what it made.
    @Operation
    package func listRulesets() async throws -> [Components.Schemas.RulesetSummary] {
        try store.names().compactMap { name in
            guard let latest = try store.latestVersion(of: name) else { return nil }
            let made = checks.made(by: name)
            let versions = try store.versions(of: name).map { version in
                Components.Schemas.RulesetVersion(
                    version: version, branch: try store.branch(of: name, version: version) ?? RulesetStore.standard,
                    parent: try store.parent(of: name, version: version), presentations: made[version] ?? 0
                )
            }
            return Components.Schemas.RulesetSummary(name: name, version: latest, standard: try store.head(of: name, branch: RulesetStore.standard), versions: versions)
        }
    }

    /// A document read as a store would read it, and nothing stored.
    @Operation
    @ErrorResponse(BadRuleset.self, .badRequest, { Components.Schemas.Problem(detail: $0.reason) })
    package func checkRuleset(@Path name: String, @JSONBody body: Components.Schemas.RulesetDocument) async throws -> Components.Schemas.RulesetReading {
        try Mapping.reading(try read(body.document, as: name))
    }

    /// What a draft would put out of date were it the head of its base's branch, recorded nowhere.
    @Operation
    @ErrorResponse(NoSuchRuleset.self, .notFound)
    @ErrorResponse(BadRuleset.self, .badRequest, { Components.Schemas.Problem(detail: $0.reason) })
    package func draftImpact(@Path name: String, @JSONBody body: Components.Schemas.DraftImpactRequest) async throws -> [Components.Schemas.OutOfDatePresentation] {
        let draft = try read(body.document, as: name)
        return try checks.impact(ofDraft: draft, basedOn: body.basedOn, of: name).map(Mapping.outOfDate)
    }

    private func read(_ document: String, as name: String) throws -> Ruleset {
        do {
            return try store.read(Data(document.utf8), as: name)
        } catch let error as RulesetFileError {
            throw BadRuleset(reason: error.description)
        } catch let error as RulesetStoreError {
            throw BadRuleset(reason: error.description)
        }
    }

    @Operation
    @ErrorResponse(NoSuchRuleset.self, .notFound)
    package func branchImpact(@Path name: String, @Path branch: String) async throws -> [Components.Schemas.OutOfDatePresentation] {
        try checks.impact(of: branch, of: name).map(Mapping.outOfDate)
    }

    @Operation
    @ErrorResponse(NoSuchRuleset.self, .notFound)
    package func listBranches(@Path name: String) async throws -> [Components.Schemas.Branch] {
        let branches = try store.branches(of: name)
        guard !branches.isEmpty else { throw NoSuchRuleset() }
        return branches.map(Mapping.branch)
    }

    @Operation
    @ErrorResponse(NoSuchRuleset.self, .notFound)
    package func getRuleset(@Path name: String, @Query version: Int?) async throws -> Components.Schemas.RulesetDocument {
        guard let (found, data) = try store.document(named: name, version: version) else { throw NoSuchRuleset() }
        guard let ruleset = try store.ruleset(named: name, version: found) else { throw NoSuchRuleset() }
        return Components.Schemas.RulesetDocument(
            name: name, version: found, branch: try store.branch(of: name, version: found),
            document: String(decoding: data, as: UTF8.self), reading: try Mapping.reading(ruleset)
        )
    }

    /// The dry run: the input specs joined as a binding's segments are, and a recipe for each of the
    /// ruleset's outputs. Each spec is read strictly by the silo, as a registration reads it.
    @Operation
    @ErrorResponse(NoSuchRuleset.self, .notFound)
    @ErrorResponse(BadBinding.self, .badRequest, { Components.Schemas.Problem(detail: $0.reason) })
    @ErrorResponse(Unresolvable.self, .unprocessableContent, { Components.Schemas.Problem(detail: $0.reason) })
    package func resolveRecipe(@Path name: String, @Query version: Int?, @JSONBody body: Components.Schemas.ResolveRequest) async throws -> [Components.Schemas.Recipe] {
        guard let ruleset = try store.ruleset(named: name, version: version) else { throw NoSuchRuleset() }
        var specs: [String: InputSpec] = [:]
        var segments: [Binding.Segment] = []
        for (position, input) in body.inputs.enumerated() {
            let document = try JSONEncoder().encode(input)
            do throws(InputSpecError) {
                specs["\(position + 1)"] = try InputSpec.read(from: document)
            } catch {
                throw BadBinding(reason: "input \(position + 1): \(error.description)")
            }
            segments.append(Binding.Segment(source: "\(position + 1)"))
        }
        let joined: JoinedMedia
        do throws(BindingError) {
            joined = try JoinedMedia(segments, specs: specs)
        } catch {
            throw BadBinding(reason: error.description)
        }
        var roles: [Int: AudioRole] = [:]
        for role in body.roles ?? [] {
            roles[role.audio] = AudioRole(rawValue: role.role.rawValue)
        }
        let mappings: [TrackMapping] = try Mapping.transcode(body.mappings ?? [])
        return try ruleset.outputs.map { output in
            let facts = SourceFacts(
                input: joined.spec, roles: roles, kind: body.kind.flatMap(EntryType.init(rawValue:)),
                profile: output.profile, duration: joined.duration
            )
            do {
                return try Mapping.transcode(try RecipeResolver.resolve(facts, with: ruleset, mappings: mappings))
            } catch let error as ResolutionError {
                throw Unresolvable(reason: "\(output.profile.map { "the \($0) output" } ?? "the unqualified output"): \(error.description)")
            }
        }
    }
}
