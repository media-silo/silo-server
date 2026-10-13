// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import FileServing
import Foundation
import HTTPAPIs
import HTTPTypes
import OpenAPIRuntime  // swiftlint:disable:this unused_import
import SiloAPI
import SiloKit
import SiloStore
import Wire
import WireMVC
import WireOpenAPI

/// Trials, read: anyone on the network may see what was tried, as anyone may watch the queue.
@Singleton
@OpenAPIController(spec: "SiloAPI")
package struct TrialController {
    private let service: JobService
    private let recipes: RecipeStore
    private let rulesets: RulesetStore

    @Inject
    package init(service: JobService, recipes: RecipeStore, rulesets: RulesetStore) {
        self.service = service
        self.recipes = recipes
        self.rulesets = rulesets
    }

    /// Each tried trial with the ruleset version that made its recipe and the branch that version
    /// is on, filtered by either.
    @Operation
    package func listTrials(@Query ruleset: String?, @Query branch: String?) async throws -> [Components.Schemas.Trial] {
        try service.trials().compactMap { job -> Components.Schemas.Trial? in
            guard let stored = recipes.recipe(job.recipe) else { return nil }
            let made = stored.recipe.ruleset
            let on = try made.version.flatMap { try rulesets.branch(of: made.name, version: $0) } ?? RulesetStore.standard
            guard ruleset.map({ $0 == made.name }) ?? true, branch.map({ $0 == on }) ?? true else { return nil }
            return Components.Schemas.Trial(
                job: job.id, recipe: job.recipe, ruleset: made.name, version: made.version, branch: on,
                binding: stored.binding, profile: stored.recipe.output.profile,
                result: try job.result.map { try Mapping.transcode($0) }, createdAt: job.createdAt
            )
        }
    }
}

/// Trials, changed: deleted, and fetched again when the fetch that follows the encode failed.
/// Behind the operator's token.
@Singleton
@OpenAPIController(spec: "SiloAPI")
@Middleware(RouteMiddleware.requireOperator)
package struct TrialOperatorController {
    private let service: JobService

    @Inject
    package init(service: JobService) {
        self.service = service
    }

    @Operation
    @ResponseStatus(.noContent)
    @ErrorResponse(NoSuchJob.self, .notFound)
    package func deleteTrial(@Path id: String) async throws {
        try service.deleteTrial(id)
    }

    @Operation
    @ErrorResponse(NoSuchJob.self, .notFound)
    @ErrorResponse(WrongState.self, .conflict, { Components.Schemas.Problem(detail: $0.description) })
    @ErrorResponse(PlacementFetchError.self, .badGateway, { Components.Schemas.Problem(detail: $0.localizedDescription) })
    package func fetchTrial(@Path id: String) async throws -> Components.Schemas.Job {
        try Mapping.transcode(try await service.fetchTrial(id))
    }
}

/// A trial's output as bytes, outside the document for the reason a presentation's is: an operation
/// buffers its body whole.
@Singleton
@Controller("/v1")
package struct TrialFileController {
    private let service: JobService

    @Inject
    package init(service: JobService) {
        self.service = service
    }

    /// Played as a presentation is, with `Range`.
    @Get("/trials/{id}/file")
    @RawRoute
    package func trialFile<Sender: HTTPResponseSender & ~Copyable & SendableMetatype>(
        request: HTTPRequest,
        pathParameters: [String: Substring],
        responseSender: consuming sending Sender
    ) async throws where Sender.Writer: ~Copyable {
        guard let id = pathParameters["id"].map(String.init), let trial = service.trial(id) else {
            try await responseSender.sendAndFinish(HTTPResponse(status: .notFound))
            return
        }
        let url = service.trialFile(of: trial)
        try await FileResponse.send(
            file: url,
            method: request.method,
            rangeHeader: request.headerFields[.range],
            contentType: FileResponse.contentType(for: url),
            to: responseSender
        )
    }
}
