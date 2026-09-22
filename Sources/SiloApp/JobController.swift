// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import OpenAPIRuntime  // swiftlint:disable:this unused_import
import SiloAPI
import SiloKit
import SiloLibrary
import Wire
import WireMVC
import WireOpenAPI

/// Jobs, read: anyone on the network may watch the queue.
@Singleton
@OpenAPIController(spec: "SiloAPI")
package struct JobController {
    private let service: JobService

    @Inject
    package init(service: JobService) {
        self.service = service
    }

    @Operation
    package func listJobs(@Query state: Components.Schemas.JobState?) async throws -> [Components.Schemas.Job] {
        try Mapping.transcode(try service.all(state: state.flatMap { JobState(rawValue: $0.rawValue) }))
    }

    @Operation
    @ErrorResponse(NoSuchJob.self, .notFound)
    package func getJob(@Path id: String) async throws -> Components.Schemas.Job {
        try Mapping.transcode(try service.job(id))
    }
}

/// Jobs, changed: registered by the tool, assigned, cancelled, retried and placed by an operator,
/// and claimed, reported and completed by a node. All behind the operator's token for now; a
/// node's own token arrives with nodes.
@Singleton
@OpenAPIController(spec: "SiloAPI")
@Middleware(RouteMiddleware.requireOperator)
package struct JobOperatorController {
    private let service: JobService

    @Inject
    package init(service: JobService) {
        self.service = service
    }

    @Operation
    package func createJob(@JSONBody body: Components.Schemas.NewJob) async throws -> Components.Schemas.Job {
        let source: FileRef = try Mapping.transcode(body.source)
        let probe: ProbedSource? = try body.probe.map { try Mapping.transcode($0) }
        let makeMKV: MakeMKVFacts? = try body.makeMKV.map { try Mapping.transcode($0) }
        return try Mapping.transcode(try service.register(source: source, discName: body.discName, probe: probe, makeMKV: makeMKV))
    }

    @Operation
    @ErrorResponse(NoSuchJob.self, .notFound)
    @ErrorResponse(WrongState.self, .conflict, { Components.Schemas.Problem(detail: $0.description) })
    @ErrorResponse(BadAssignment.self, .badRequest, { Components.Schemas.Problem(detail: $0.reason) })
    @ErrorResponse(Unresolvable.self, .unprocessableContent, { Components.Schemas.Problem(detail: $0.reason) })
    package func assignJob(@Path id: String, @JSONBody body: Components.Schemas.Assignment) async throws -> Components.Schemas.Job {
        let assignment: Assignment = try Mapping.transcode(body)
        return try Mapping.transcode(try service.assign(id, assignment))
    }

    @Operation
    @ErrorResponse(NoSuchJob.self, .notFound)
    @ErrorResponse(WrongState.self, .conflict, { Components.Schemas.Problem(detail: $0.description) })
    package func cancelJob(@Path id: String) async throws -> Components.Schemas.Job {
        try Mapping.transcode(try service.cancel(id))
    }

    @Operation
    @ErrorResponse(NoSuchJob.self, .notFound)
    @ErrorResponse(WrongState.self, .conflict, { Components.Schemas.Problem(detail: $0.description) })
    package func retryJob(@Path id: String) async throws -> Components.Schemas.Job {
        try Mapping.transcode(try service.retry(id))
    }

    @Operation
    @ErrorResponse(NoSuchJob.self, .notFound)
    @ErrorResponse(NoSuchLibrary.self, .notFound)
    @ErrorResponse(WrongState.self, .conflict, { Components.Schemas.Problem(detail: $0.description) })
    @ErrorResponse(PlacementRefusedError.self, .conflict, { Components.Schemas.Problem(detail: $0.reason) })
    @ErrorResponse(PlacementFetchError.self, .badGateway, { Components.Schemas.Problem(detail: $0.localizedDescription) })
    package func placeJob(@Path id: String) async throws -> Components.Schemas.Job {
        try Mapping.transcode(try await service.place(id))
    }

    @Operation
    package func claimJob(@JSONBody body: Components.Schemas.ClaimRequest) async throws -> Components.Schemas.ClaimReply {
        Components.Schemas.ClaimReply(job: try await service.claim(node: body.node, capabilities: Set(body.capabilities)).map { try Mapping.transcode($0) })
    }

    @Operation
    @ErrorResponse(NoSuchJob.self, .notFound)
    package func reportProgress(@Path id: String, @JSONBody body: Components.Schemas.Progress) async throws -> Components.Schemas.ProgressReply {
        let progress: JobProgress = try Mapping.transcode(body)
        let state = try await service.report(id, progress: progress)
        return Components.Schemas.ProgressReply(state: Components.Schemas.JobState(rawValue: state.rawValue) ?? .pending)
    }

    @Operation
    @ErrorResponse(NoSuchJob.self, .notFound)
    @ErrorResponse(WrongState.self, .conflict, { Components.Schemas.Problem(detail: $0.description) })
    package func completeJob(@Path id: String, @JSONBody body: Components.Schemas.CompleteRequest) async throws -> Components.Schemas.Job {
        let output: FileRef = try Mapping.transcode(body.output)
        let result: EncodeResult = try Mapping.transcode(body.result)
        return try Mapping.transcode(try await service.complete(id, output: output, result: result))
    }

    @Operation
    @ErrorResponse(NoSuchJob.self, .notFound)
    @ErrorResponse(WrongState.self, .conflict, { Components.Schemas.Problem(detail: $0.description) })
    package func failJob(@Path id: String, @JSONBody body: Components.Schemas.FailRequest) async throws -> Components.Schemas.Job {
        try Mapping.transcode(try await service.fail(id, reason: body.reason))
    }
}
