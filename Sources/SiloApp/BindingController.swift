// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import OpenAPIRuntime  // swiftlint:disable:this unused_import
import SiloAPI
import SiloKit
import SiloStore
import SmdSidecar
import Wire
import WireMVC
import WireOpenAPI

/// Bindings and recipes, read: open, as the queue is.
@Singleton
@OpenAPIController(spec: "SiloAPI")
package struct BindingController {
    private let service: BindingService
    private let recipes: RecipeStore

    @Inject
    package init(service: BindingService, recipes: RecipeStore) {
        self.service = service
        self.recipes = recipes
    }

    @Operation
    @ErrorResponse(NoSuchBinding.self, .notFound)
    package func getBinding(@Path id: String) async throws -> Components.Schemas.Binding {
        let (binding, recipes) = try service.binding(id)
        return try Mapping.binding(binding, recipes: recipes.map(\.id))
    }

    @Operation
    @ErrorResponse(NoSuchRecipe.self, .notFound)
    package func getRecipe(@Path id: String) async throws -> Components.Schemas.StoredRecipe {
        guard let recipe = recipes.recipe(id) else { throw NoSuchRecipe() }
        return try Mapping.transcode(recipe)
    }
}

/// Bindings made, rulesets applied to them, and drafts adjusted and discarded: the producer's side,
/// behind the operator's token.
@Singleton
@OpenAPIController(spec: "SiloAPI")
@Middleware(RouteMiddleware.requireOperator)
package struct BindingOperatorController {
    private let service: BindingService

    @Inject
    package init(service: BindingService) {
        self.service = service
    }

    @Operation
    @JSONResponse(status: .created)
    @ErrorResponse(BadBinding.self, .badRequest, { Components.Schemas.Problem(detail: $0.reason) })
    package func makeBinding(@JSONBody body: Components.Schemas.NewBinding) async throws -> Components.Schemas.Binding {
        let request: NewBinding = try Mapping.transcode(body)
        return try Mapping.binding(try service.make(request.binding), recipes: [])
    }

    @Operation
    @JSONResponse(status: .created)
    @ErrorResponse(NoSuchBinding.self, .notFound)
    @ErrorResponse(BadApplication.self, .badRequest, { Components.Schemas.Problem(detail: $0.reason) })
    @ErrorResponse(Unresolvable.self, .unprocessableContent, { Components.Schemas.Problem(detail: $0.reason) })
    package func applyRuleset(@Path id: String, @JSONBody body: Components.Schemas.Application) async throws -> [Components.Schemas.StoredRecipe] {
        let application: Application = try Mapping.transcode(body)
        return try service.apply(application, to: id).map { try Mapping.transcode($0) }
    }

    @Operation
    @ErrorResponse(NoSuchRecipe.self, .notFound)
    @ErrorResponse(BadAdjustment.self, .badRequest, { Components.Schemas.Problem(detail: $0.reason) })
    @ErrorResponse(CommittedRecipe.self, .conflict, { Components.Schemas.Problem(detail: $0.reason) })
    package func adjustRecipe(@Path id: String, @JSONBody body: [Components.Schemas.Adjustment]) async throws -> Components.Schemas.StoredRecipe {
        let adjustments: [Adjustment] = try Mapping.transcode(body)
        return try Mapping.transcode(try service.adjust(id, adjustments))
    }

    @Operation
    @ResponseStatus(.noContent)
    @ErrorResponse(NoSuchRecipe.self, .notFound)
    @ErrorResponse(CommittedRecipe.self, .conflict, { Components.Schemas.Problem(detail: $0.reason) })
    package func discardRecipe(@Path id: String) async throws {
        try service.discard(id)
    }
}

/// A binding as a producer sends it, before the silo has given it an id.
private struct NewBinding: Decodable {
    var library: String
    var containers: [String]
    var item: String
    var alternative: String?
    var tracks: [TrackMapping]?
    var chapters: [SmdSidecar.Chapter]?
    var segments: [Binding.Segment]

    var binding: Binding {
        Binding(
            library: library, containers: containers, item: item, alternative: alternative, tracks: tracks ?? [],
            chapters: chapters ?? [], segments: segments
        )
    }
}

extension Mapping {
    /// A binding as the API renders it, with the ids of its recipes.
    static func binding(_ binding: Binding, recipes: [String]) throws -> Components.Schemas.Binding {
        struct Rendered: Encodable {
            var binding: Binding
            var recipes: [String]
            func encode(to encoder: any Encoder) throws {
                try binding.encode(to: encoder)
                var container = encoder.container(keyedBy: Key.self)
                try container.encode(recipes, forKey: Key(stringValue: "recipes"))
            }
            struct Key: CodingKey {
                var stringValue: String
                init(stringValue: String) { self.stringValue = stringValue }
                var intValue: Int? { nil }
                init?(intValue: Int) { nil }
            }
        }
        return try transcode(Rendered(binding: binding, recipes: recipes))
    }
}
