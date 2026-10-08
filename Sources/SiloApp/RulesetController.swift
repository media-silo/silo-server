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

/// Rulesets, read: the list, one document, and the dry run of the resolver.
@Singleton
@OpenAPIController(spec: "SiloAPI")
package struct RulesetController {
    private let store: RulesetStore

    @Inject
    package init(store: RulesetStore) {
        self.store = store
    }

    @Operation
    package func listRulesets() async throws -> [Components.Schemas.RulesetSummary] {
        try store.names().compactMap { name in
            try store.latestVersion(of: name).map { Components.Schemas.RulesetSummary(name: name, version: $0) }
        }
    }

    @Operation
    @ErrorResponse(NoSuchRuleset.self, .notFound)
    package func getRuleset(@Path name: String, @Query version: Int?) async throws -> Components.Schemas.RulesetDocument {
        guard let (found, data) = try store.document(named: name, version: version) else { throw NoSuchRuleset() }
        return Components.Schemas.RulesetDocument(name: name, version: found, document: String(decoding: data, as: UTF8.self))
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
