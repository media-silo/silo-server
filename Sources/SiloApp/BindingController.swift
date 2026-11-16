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

    @Operation
    @ErrorResponse(NoSuchBinding.self, .notFound)
    package func getBindingRules(@Path id: String) async throws -> Components.Schemas.BindingRules {
        Mapping.bindingRules(try service.rules(of: id))
    }
}

/// Bindings made, their own rules stored, rulesets applied to them, and resolved recipes discarded: the
/// producer's side, behind the operator's token.
@Singleton
@OpenAPIController(spec: "SiloAPI")
@Middleware(RouteMiddleware.requireOperator)
package struct BindingOperatorController {
    private let service: BindingService

    @Inject
    package init(service: BindingService) {
        self.service = service
    }

    /// Raw, because which success it answers — 201 for a new binding, 200 for the one that says
    /// what it says — is decided by the store, not by the handler's signature.
    @RawOperation
    package func makeBinding(_ input: Operations.makeBinding.Input) async throws -> Operations.makeBinding.Output {
        let body =
            switch input.body {
            case .json(let body): body
            }
        let request: NewBinding = try Mapping.transcode(body)
        do {
            let (binding, created) = try service.make(request.binding)
            let rendered = try Mapping.binding(binding, recipes: try service.binding(binding.id).recipes.map(\.id))
            return created ? .created(.init(body: .json(rendered))) : .ok(.init(body: .json(rendered)))
        } catch let bad as BadBinding {
            return .badRequest(.init(body: .json(Components.Schemas.Problem(detail: bad.reason))))
        }
    }

    /// Raw, because which success it answers — 201 when a recipe is made, 200 when every output's
    /// recipe was already held — is decided by the application.
    @RawOperation
    package func applyRuleset(_ input: Operations.applyRuleset.Input) async throws -> Operations.applyRuleset.Output {
        let body =
            switch input.body {
            case .json(let body): body
            }
        let application: Application = try Mapping.transcode(body)
        do {
            let (recipes, created) = try service.apply(application, to: input.path.id)
            let rendered: [Components.Schemas.StoredRecipe] = try recipes.map { try Mapping.transcode($0) }
            return created ? .created(.init(body: .json(rendered))) : .ok(.init(body: .json(rendered)))
        } catch is NoSuchBinding {
            return .notFound(.init())
        } catch let bad as BadApplication {
            return .badRequest(.init(body: .json(Components.Schemas.Problem(detail: bad.reason))))
        } catch let closed as ClosedBranch {
            return .conflict(.init(body: .json(Components.Schemas.Problem(detail: closed.reason))))
        } catch let unresolvable as Unresolvable {
            return .unprocessableContent(.init(body: .json(Components.Schemas.Problem(detail: unresolvable.reason))))
        }
    }

    @Operation
    @ErrorResponse(NoSuchBinding.self, .notFound)
    @ErrorResponse(BadBindingRules.self, .badRequest, { Components.Schemas.Problem(detail: $0.reason) })
    package func setBindingRules(
        @Path id: String,
        @JSONBody body: Components.Schemas.NewBindingRules
    ) async throws -> Components.Schemas.BindingRules {
        _ = try await service.setRules(Data(body.document.utf8), of: id)
        return Mapping.bindingRules(try service.rules(of: id))
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
            library: library,
            containers: containers,
            item: item,
            alternative: alternative,
            tracks: tracks ?? [],
            chapters: chapters ?? [],
            segments: segments
        )
    }
}

extension Mapping {
    /// A binding's rules as the API renders them.
    static func bindingRules(
        _ rules: (active: Int?, document: Data?, versions: [Int])
    ) -> Components.Schemas.BindingRules {
        Components.Schemas.BindingRules(
            activeVersion: rules.active,
            document: rules.document.map { String(decoding: $0, as: UTF8.self) },
            versions: rules.versions
        )
    }

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
