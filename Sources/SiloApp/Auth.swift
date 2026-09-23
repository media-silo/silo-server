// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import HTTPAPIs
import HTTPTypes
import SiloStore
import Wire
import WireMVC

/// The operator's token, located by the daemon: the environment's when it is set — it wins
/// whenever it is — and otherwise the stored credential's hash, which a confirmed setup landed.
/// Neither present is bootstrap, and no operator routes work, which is the safe way round for a
/// server that is otherwise open on a LAN.
@Singleton
package struct OperatorToken: Sendable {
    private let token: String?
    private let credential: OperatorCredential

    @Inject
    package init(config: SiloConfig, credential: OperatorCredential) {
        token = config.operatorToken
        self.credential = credential
    }

    package func accepts(_ header: String?) -> Bool {
        guard let header, header.hasPrefix("Bearer ") else { return false }
        let bearer = String(header.dropFirst("Bearer ".count))
        if let token { return bearer == token }
        guard !bearer.isEmpty else { return false }
        return credential.acceptsHash(NodeStore.hash(bearer))
    }
}

package enum RouteMiddleware {
    package static let requireOperator = FactoryKey()
    package static let requireNode = FactoryKey()
    package static let confirmSetup = FactoryKey()
}

/// The setup confirm's bearer is the staged passkey — an input, not a gate, and one the typed
/// operation cannot declare: OpenAPI reserves `Authorization` out of `Input`, so the header is
/// read here instead. A matching bearer spends the stage and the operation runs on to answer
/// the server as it now is; a miss answers 401, and nothing staged answers 404, both without
/// the operation ever running.
@Factory(RouteMiddleware.confirmSetup)
@MiddlewareFactory
package struct ConfirmSetup<
    Ctx: HTTPServerCapability.RequestContext & ~Copyable,
    Reader: AsyncReader & ~Copyable,
    Sender: HTTPResponseSender & ~Copyable
>: Middleware
where Reader.ReadElement == UInt8, Reader.FinalElement == HTTPFields?, Sender.Writer: ~Copyable {
    @Inject let service: ServerService

    package typealias Input = RequestResponseMiddlewareBox<Ctx, Reader, Sender>
    package typealias NextInput = Input

    package func intercept<Return: ~Copyable>(
        input: consuming Input,
        next: (consuming NextInput) async throws -> Return
    ) async throws -> Return {
        guard input.isPending else { return try await next(input) }
        let header = input.peekedRequest.headerFields[.authorization]
        let bearer = header.flatMap { $0.hasPrefix("Bearer ") ? String($0.dropFirst("Bearer ".count)) : nil }
        let refusal: HTTPResponse.Status?
        do {
            try service.confirmSetup(bearer: bearer)
            refusal = nil
        } catch is NothingStaged {
            refusal = .notFound
        } catch is ConfirmRefused {
            refusal = .unauthorized
        }
        guard let refusal else { return try await next(input) }
        return try await next(
            input.responding { sender in
                try await sender.sendAndFinish(HTTPResponse(status: refusal))
            }
        )
    }
}

/// Answers 401 for a request without an approved node's token or the operator's. Seeing a node's
/// token is its heartbeat. The node named in a request body is trusted to be the token's; on a
/// household network that is enough, and the operator's token is what the embedded node and the
/// operator's own tooling use.
@Factory(RouteMiddleware.requireNode)
@MiddlewareFactory
package struct RequireNode<
    Ctx: HTTPServerCapability.RequestContext & ~Copyable,
    Reader: AsyncReader & ~Copyable,
    Sender: HTTPResponseSender & ~Copyable
>: Middleware
where Reader.ReadElement == UInt8, Reader.FinalElement == HTTPFields?, Sender.Writer: ~Copyable {
    @Inject let token: OperatorToken
    @Inject let nodes: NodeService

    package typealias Input = RequestResponseMiddlewareBox<Ctx, Reader, Sender>
    package typealias NextInput = Input

    package func intercept<Return: ~Copyable>(
        input: consuming Input,
        next: (consuming NextInput) async throws -> Return
    ) async throws -> Return {
        let header = input.peekedRequest.headerFields[.authorization]
        var authorised = token.accepts(header)
        if !authorised, let header, header.hasPrefix("Bearer ") {
            authorised = nodes.authenticate(bearer: String(header.dropFirst("Bearer ".count))) != nil
        }
        guard input.isPending, !authorised else { return try await next(input) }
        return try await next(
            input.responding { sender in
                try await sender.sendAndFinish(HTTPResponse(status: .unauthorized))
            }
        )
    }
}

/// Answers 401 for a request without the operator's bearer token, and lets the rest through.
/// Applied to a controller, it covers every operation the controller holds, which is how the
/// document's operator-only operations are grouped: by controller.
@Factory(RouteMiddleware.requireOperator)
@MiddlewareFactory
package struct RequireOperator<
    Ctx: HTTPServerCapability.RequestContext & ~Copyable,
    Reader: AsyncReader & ~Copyable,
    Sender: HTTPResponseSender & ~Copyable
>: Middleware
where Reader.ReadElement == UInt8, Reader.FinalElement == HTTPFields?, Sender.Writer: ~Copyable {
    @Inject let token: OperatorToken

    package typealias Input = RequestResponseMiddlewareBox<Ctx, Reader, Sender>
    package typealias NextInput = Input

    package func intercept<Return: ~Copyable>(
        input: consuming Input,
        next: (consuming NextInput) async throws -> Return
    ) async throws -> Return {
        let authorised = token.accepts(input.peekedRequest.headerFields[.authorization])
        guard input.isPending, !authorised else { return try await next(input) }
        return try await next(
            input.responding { sender in
                try await sender.sendAndFinish(HTTPResponse(status: .unauthorized))
            }
        )
    }
}
