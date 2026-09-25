// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloClient
import Synchronization
import Testing
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The onboarding calls over a stubbed wire: each test hands the protocol a handler and pins what
/// the client sent — method, path, bearer — against what it decoded. Serial because the handler is
/// one static seam.
@Suite(.serialized)
struct SiloClientTests {
    /// The one URLProtocol the suite routes through; `handler` is the current test's answer.
    private final class Stub: URLProtocol, @unchecked Sendable {
        static let handler = Mutex<@Sendable (URLRequest) throws -> (Int, Data)?>({ _ in nil })

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            do {
                guard let (status, data) = try Self.handler.withLock({ try $0(request) }),
                      let url = request.url,
                      let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])
                else { throw SiloClientError.badPath(request.url?.absoluteString ?? "") }
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}
    }

    private static func client(
        token: String? = nil,
        answering handler: @escaping @Sendable (URLRequest) throws -> (Int, Data)?
    ) -> SiloClient {
        Stub.handler.withLock { $0 = handler }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Stub.self]
        return SiloClient(baseURL: URL(string: "http://silo.local:8080")!, token: token, session: URLSession(configuration: configuration))
    }

    private static func body(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: 1024)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }

    @Test func theServerRouteAnswersOpenly() async throws {
        let seen = Mutex<(String, String, String?)?>(nil)
        let client = Self.client { request in
            seen.withLock { $0 = (request.httpMethod ?? "", request.url?.path ?? "", request.value(forHTTPHeaderField: "Authorization")) }
            return (200, Data(#"{"id":"s1","name":"Silo on attic","bootstrap":true}"#.utf8))
        }

        let server = try await client.server()

        #expect(server == SiloClient.ServerInfo(id: "s1", name: "Silo on attic", bootstrap: true))
        let (method, path, authorization) = try #require(seen.withLock { $0 })
        #expect(method == "GET")
        #expect(path == "/v1/server")
        #expect(authorization == nil, "the route is open: no bearer, even unconfigured")
    }

    @Test func theVerifyProbeSendsTheToken() async throws {
        let seen = Mutex<(String, String, String?)?>(nil)
        let client = Self.client(token: "horse-battery") { request in
            seen.withLock { $0 = (request.httpMethod ?? "", request.url?.path ?? "", request.value(forHTTPHeaderField: "Authorization")) }
            return (200, Data(#"{"phase":"active"}"#.utf8))
        }

        let status = try await client.verifyAccess()

        #expect(status == .active)
        let (method, path, authorization) = try #require(seen.withLock { $0 })
        #expect(method == "GET")
        #expect(path == "/v1/operator")
        #expect(authorization == "Bearer horse-battery")
    }

    @Test func aPendingVerifyCarriesTheStagesWindow() async throws {
        let client = Self.client(token: "horse-battery") { _ in
            (200, Data(#"{"phase":"pending","confirmBy":"2026-09-24T10:10:00Z"}"#.utf8))
        }

        let status = try await client.verifyAccess()

        guard case .pending(let confirmBy) = status else {
            Issue.record("a staged passkey's probe answered \(status)")
            return
        }
        #expect(confirmBy.timeIntervalSince1970 == 1_790_244_600, "the stage's deadline, decoded")
    }

    @Test func aRefusedVerifyArrivesAsAStatus() async throws {
        let client = Self.client(token: "stale") { _ in (401, Data()) }

        do {
            _ = try await client.verifyAccess()
            Issue.record("verifying with a refused token")
        } catch SiloClientError.status(401, _) {}
    }

    @Test func stagingReadsItsDeadlineOffTheWire() async throws {
        let sent = Mutex<Data?>(nil)
        let client = Self.client { request in
            sent.withLock { $0 = Self.body(of: request) }
            return (202, Data(#"{"id":"s1","name":"Living Room Silo","confirmBy":"2026-09-24T10:10:00Z"}"#.utf8))
        }

        let stage = try await client.setup(name: "Living Room Silo", passkey: "horse-battery")

        #expect(stage.id == "s1")
        #expect(stage.name == "Living Room Silo")
        #expect(stage.confirmBy.timeIntervalSince1970 == 1_790_244_600, "the iso8601 deadline, decoded")
        let staged = try #require(sent.withLock { $0 })
        let body = try JSONSerialization.jsonObject(with: staged) as? [String: String]
        #expect(body?["passkey"] == "horse-battery")
        #expect(body?["name"] == "Living Room Silo")
    }

    @Test func aStagedSetupRefusesWithTheStandingStagesWindow() async throws {
        let client = Self.client { _ in
            (409, Data(#"{"confirmBy":"2026-09-24T10:10:00Z"}"#.utf8))
        }

        do {
            _ = try await client.setup(passkey: "interloper")
            Issue.record("a second stage inside the window")
        } catch SiloClientError.conflict(let confirmBy) {
            #expect(confirmBy.timeIntervalSince1970 == 1_790_244_600, "the refusal carries the standing stage's window")
        }
    }

    @Test func aConfiguredServerAnswersGone() async throws {
        let client = Self.client { _ in (410, Data()) }

        do {
            _ = try await client.setup(passkey: "too-late")
            Issue.record("staging on a configured server")
        } catch SiloClientError.status(410, _) {}
    }

    @Test func aConfirmSpendsTheStagedPasskeyAsBearer() async throws {
        let seen = Mutex<(String, String, String?)?>(nil)
        let client = Self.client { request in
            seen.withLock { $0 = (request.httpMethod ?? "", request.url?.path ?? "", request.value(forHTTPHeaderField: "Authorization")) }
            return (201, Data(#"{"id":"s1","name":"Living Room Silo","bootstrap":false}"#.utf8))
        }

        let server = try await client.confirmSetup(bearer: "horse-battery")

        #expect(server == SiloClient.ServerInfo(id: "s1", name: "Living Room Silo", bootstrap: false))
        let (method, path, authorization) = try #require(seen.withLock { $0 })
        #expect(method == "POST")
        #expect(path == "/v1/setup/confirm")
        #expect(authorization == "Bearer horse-battery", "the passkey, not the client's token, is the bearer")
    }

    @Test func aConfirmWithNothingStagedIsNotFound() async throws {
        let client = Self.client { _ in (404, Data()) }

        do {
            _ = try await client.confirmSetup(bearer: "horse-battery")
            Issue.record("confirming with nothing staged")
        } catch SiloClientError.status(404, _) {}
    }
}
