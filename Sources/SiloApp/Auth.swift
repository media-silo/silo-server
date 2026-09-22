// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import HTTPAPIs
import HTTPTypes
import Wire
import WireMVC

/// The operator's token, from configuration. No token configured means no operator routes work,
/// which is the safe way round for a server that is otherwise open on a LAN.
@Singleton
package struct OperatorToken: Sendable {
    private let token: String?

    @Inject
    package init(config: SiloConfig) {
        token = config.operatorToken
    }

    package func accepts(_ header: String?) -> Bool {
        guard let token, let header, header.hasPrefix("Bearer ") else { return false }
        return String(header.dropFirst("Bearer ".count)) == token
    }
}

package enum RouteMiddleware {
    package static let requireOperator = FactoryKey()
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
