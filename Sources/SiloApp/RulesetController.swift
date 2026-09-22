// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import OpenAPIRuntime  // swiftlint:disable:this unused_import
import SiloAPI
import SiloKit
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

    @Operation
    @ErrorResponse(NoSuchRuleset.self, .notFound)
    @ErrorResponse(Unresolvable.self, .unprocessableContent, { Components.Schemas.Problem(detail: $0.reason) })
    package func resolveRecipe(@Path name: String, @Query version: Int?, @JSONBody body: Components.Schemas.ResolveRequest) async throws -> Components.Schemas.Recipe {
        guard let ruleset = try store.ruleset(named: name, version: version) else { throw NoSuchRuleset() }
        let facts: SourceFacts = try Mapping.transcode(body.facts)
        let mappings: [TrackMapping] = try Mapping.transcode(body.mappings ?? [])
        do {
            let recipe = try RecipeResolver.resolve(facts, with: ruleset, mappings: mappings)
            return try Mapping.transcode(recipe)
        } catch let error as ResolutionError {
            throw Unresolvable(reason: error.description)
        }
    }
}
