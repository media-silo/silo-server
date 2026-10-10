// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

#if canImport(SwiftUI)
import Foundation
import SiloAdminKit
import SiloDiscovery
import Synchronization
import Testing
@testable import SiloAdmin

/// The window's model against a silo-shaped stub. The kit's suite pins the flows; this one
/// pins the hand-offs between the sheets and the model — the order SwiftUI actually runs them
/// in, which the engine never sees. Serial because the handler is one static seam.
@MainActor
@Suite(.serialized)
struct ConsoleModelTests {
    private final class Stub: URLProtocol, @unchecked Sendable {
        static let handler = Mutex<@Sendable (URLRequest) -> (Int, Data)?>({ _ in nil })

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let (status, data) = Self.handler.withLock({ $0(request) }),
                  let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])
            else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private nonisolated static func serverInfo(bootstrap: Bool) -> Data {
        Data(#"{"id":"s1","name":"Fresh Silo","bootstrap":\#(bootstrap)}"#.utf8)
    }

    /// The setup sheet's confirm dismisses before it hands over — and dismissing a sheet bound
    /// by item clears `prepared` on the spot. The confirm has to play the pair anyway: when the
    /// model read the setup back from `prepared`, it found nothing, sent nothing and said
    /// nothing, and the next Set Up minted a different passkey over an unstaged silo.
    @Test func confirmingAfterTheSheetDismissesStillSetsUp() async throws {
        let store = InMemoryPasskeyStore()
        let wire = Mutex<[String]>([])
        Stub.handler.withLock {
            $0 = { request in
                switch request.url?.path {
                case "/v1/server":
                    return (200, Self.serverInfo(bootstrap: true))
                case "/v1/setup":
                    wire.withLock { $0.append("stage") }
                    return (202, Data(#"{"id":"s1","name":"Fresh Silo","confirmBy":"2026-09-24T10:10:00Z"}"#.utf8))
                case "/v1/setup/confirm":
                    wire.withLock { $0.append("confirm") }
                    return (201, Self.serverInfo(bootstrap: false))
                default:
                    return nil
                }
            }
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Stub.self]
        let model = ConsoleModel(console: AdminConsole(
            registry: SiloRegistry(),
            passkeys: store,
            session: URLSession(configuration: configuration),
            browse: { [DiscoveredSilo(name: "Fresh Silo", host: "fresh.local", port: 8080)] }
        ))

        await model.refresh()
        let silo = try #require(model.silos.first { $0.id == "s1" })
        await model.prepareSetup(for: silo)
        let prepared = try #require(model.prepared, "Set Up opens the sheet")
        guard case .minted(let shown) = prepared.presentation else {
            Issue.record("a fresh attempt mints and shows the passkey")
            return
        }

        // The sheet's confirm, in its order: dismiss, then hand over.
        model.prepared = nil
        await model.runSetup(prepared, name: "")

        #expect(wire.withLock { $0 } == ["stage", "confirm"], "the confirm plays the pair")
        #expect(store.passkey(for: "s1") == shown, "the passkey the sheet showed is the one kept")
        #expect(model.silos.first { $0.id == "s1" }?.classification == .withAccess)
        #expect(model.refusal == nil)
    }

    /// The Rulesets section keeps itself current as the rest of the console does: a version stored
    /// elsewhere arrives at the next refresh, without the operator asking for it.
    @Test func theRulesetsSectionKeepsItselfCurrent() async throws {
        let store = InMemoryPasskeyStore()
        store.store("held", for: "s1")
        let standard = Mutex(3)
        Stub.handler.withLock {
            $0 = { request in
                let head = standard.withLock { $0 }
                let versions = (1...head).map { #"{"version":\#($0),"branch":"standard","presentations":0}"# }.joined(separator: ",")
                switch request.url?.path {
                case "/v1/server": return (200, Self.serverInfo(bootstrap: false))
                case "/v1/operator": return (200, Data(#"{"phase":"active"}"#.utf8))
                case "/v1/rulesets": return (200, Data(#"[{"name":"household","version":\#(head),"standard":\#(head),"versions":[\#(versions)]}]"#.utf8))
                case "/v1/rulesets/household/branches": return (200, Data(#"[{"name":"standard","head":\#(head),"closed":false}]"#.utf8))
                case "/v1/rulesets/household":
                    let version = request.url?.query?.split(separator: "=").last.flatMap { Int($0) } ?? head
                    return (200, Data(#"{"name":"household","version":\#(version),"branch":"standard","document":"<ruleset/>"}"#.utf8))
                default: return nil
                }
            }
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Stub.self]
        let model = ConsoleModel(console: AdminConsole(
            registry: SiloRegistry(),
            passkeys: store,
            session: URLSession(configuration: configuration),
            browse: { [DiscoveredSilo(name: "Fresh Silo", host: "fresh.local", port: 8080)] }
        ))

        await model.refresh()
        let silo = try #require(model.silos.first { $0.id == "s1" })
        model.selected = [silo.id]
        model.section = .rulesets
        await model.loadRulesets(for: silo)
        await model.open(ruleset: "household", of: silo)
        #expect(model.opened[silo.id]?.document.version == 3, "opened at the standard's head")

        standard.withLock { $0 = 4 }
        await model.refresh()
        #expect(model.rulesets[silo.id]?.first?.standard == 4, "the list takes the version stored elsewhere")
        #expect(model.opened[silo.id]?.summary.versions?.map(\.version) == [1, 2, 3, 4], "and so do the open ruleset's versions")
        #expect(model.opened[silo.id]?.document.version == 3, "while the version the operator chose stays chosen")
    }
}
#endif
