// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloAdminKit
import SiloClient
import SiloDiscovery
import SiloKit
import SmdKit
import SmdSidecar
import Synchronization
import Testing

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The console against a silo-shaped stub: every test hands the protocol the answers a real
/// silo would give and pins the engine's replies to the spec's promises — the classes, the
/// wire order, and what is and is not stored. Serial because the handler is one static seam.
@Suite(.serialized)
struct AdminConsoleTests {
    private final class Stub: URLProtocol, @unchecked Sendable {
        static let handler = Mutex<@Sendable (URLRequest) throws -> (Int, Data)?>({ _ in nil })

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            do {
                guard let (status, data) = try Self.handler.withLock({ try $0(request) }),
                    let url = request.url,
                    let response = HTTPURLResponse(
                        url: url,
                        statusCode: status,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )
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

    private static let clock = Date(timeIntervalSince1970: 1_790_000_000)

    /// The verify probe's admission: OperatorStatus, not ServerInfo, is what /v1/operator serves.
    private static let active = #"{"phase":"active"}"#

    private static func serverInfo(_ id: String, _ name: String, bootstrap: Bool) -> String {
        #"{"id":"\#(id)","name":"\#(name)","bootstrap":\#(bootstrap)}"#
    }

    /// A console wired to the stub, its clock stopped at `clock` and its browse fixed.
    private static func console(
        registry: SiloRegistry = SiloRegistry(),
        drafts: DraftStore = DraftStore(),
        passkeys: InMemoryPasskeyStore = InMemoryPasskeyStore(),
        discovered: [DiscoveredSilo] = [],
        answering handler: @escaping @Sendable (URLRequest) throws -> (Int, Data)?
    ) -> AdminConsole {
        answer(with: handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Stub.self]
        return AdminConsole(
            registry: registry,
            drafts: drafts,
            passkeys: passkeys,
            session: URLSession(configuration: configuration),
            now: { clock },
            browse: { discovered }
        )
    }

    private static func answer(with handler: @escaping @Sendable (URLRequest) throws -> (Int, Data)?) {
        Stub.handler.withLock { $0 = handler }
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

    private func row(
        _ id: String,
        in rows: [AdminConsole.Silo],
        fileID: String = #fileID,
        filePath: String = #filePath,
        line: Int = #line,
        column: Int = #column
    ) throws -> AdminConsole.Silo {
        try #require(
            rows.first { $0.id == id },
            "no row for \(id)",
            sourceLocation: SourceLocation(fileID: fileID, filePath: filePath, line: line, column: column)
        )
    }

    // MARK: - The registry

    @Test func browsingRefreshesNeverForgets() async throws {
        let registry = SiloRegistry()
        let lastSeen = Date(timeIntervalSince1970: 1_700_000_000)
        try registry.merge(
            RegisteredSilo(
                id: "attic",
                name: "Attic Silo",
                url: URL(string: "http://attic.local:8080")!,
                lastSeen: lastSeen,
                hasStoredPasskey: false
            )
        )
        let wire = Mutex<[String]>([])
        let console = Self.console(
            registry: registry,
            discovered: [DiscoveredSilo(name: "Living Room Silo", host: "living.local", port: 8080)]
        ) { request in
            guard let url = request.url else { return nil }
            wire.withLock { $0.append("\(request.httpMethod ?? "?") \(url.host ?? "?")\(url.path)") }
            guard url.host == "living.local", url.path == "/v1/server" else { return nil }
            return (200, Data(Self.serverInfo("living", "Living Room Silo", bootstrap: true).utf8))
        }

        let rows = await console.refresh()

        let attic = try row("attic", in: rows)
        #expect(attic.lastSeen == lastSeen, "an absent silo renders with its last-seen time")
        #expect(attic.classification == .unreachable, "absent is a class of its own now")
        #expect(attic.lastKnownAccess == nil, "never probed, so nothing known of access")
        let living = try row("living", in: rows)
        #expect(living.classification == .bootstrap)
        #expect(living.lastSeen == Self.clock)
        let merged = try #require(registry.entry(for: "living"))
        #expect(merged.name == "Living Room Silo")
        #expect(merged.url == URL(string: "http://living.local:8080"))
        #expect(merged.lastSeen == Self.clock)
        #expect(!merged.hasStoredPasskey)
        #expect(wire.withLock { $0 } == ["GET living.local/v1/server"], "the absent silo is never asked anything")
    }

    @Test func aTypedAddressResolvesAndMerges() async throws {
        let registry = SiloRegistry()
        let console = Self.console(registry: registry) { request in
            guard let url = request.url, url.host == "corner.local", url.path == "/v1/server" else { return nil }
            return (200, Data(Self.serverInfo("corner", "Corner Silo", bootstrap: false).utf8))
        }

        let rows = await console.refresh(typedURLs: [URL(string: "http://corner.local:9000")!])

        let corner = try row("corner", in: rows)
        #expect(corner.classification == .withoutAccess, "first contact: reachable, nothing held — the act is to claim")
        #expect(corner.url == URL(string: "http://corner.local:9000"))
        let merged = try #require(registry.entry(for: "corner"))
        #expect(merged.url == URL(string: "http://corner.local:9000"))
        #expect(merged.lastSeen == Self.clock)
    }

    // MARK: - The four classes

    @Test func everyShownSiloIsExactlyOneClass() async throws {
        let registry = SiloRegistry()
        for id in ["access", "locked", "nohands"] {
            try registry.merge(
                RegisteredSilo(
                    id: id,
                    name: id,
                    url: URL(string: "http://\(id).local:8080")!,
                    lastSeen: Self.clock,
                    hasStoredPasskey: id != "nohands"
                )
            )
        }
        let passkeys = InMemoryPasskeyStore()
        passkeys.store("key-a", for: "access")
        passkeys.store("key-b", for: "locked")
        let noderequests = Mutex<[String?]>([])
        // nohands is registered but not discovered: it is the row that has gone quiet.
        let console = Self.console(
            registry: registry,
            passkeys: passkeys,
            discovered: ["boot", "newbie", "access", "locked"].map {
                DiscoveredSilo(name: $0, host: "\($0).local", port: 8080)
            }
        ) { request in
            guard let url = request.url, let host = url.host else { return nil }
            let id = String(host.split(separator: ".")[0])
            switch (id, url.path) {
            case ("boot", "/v1/server"):
                return (200, Data(Self.serverInfo("boot", "Boot", bootstrap: true).utf8))
            case ("newbie", "/v1/server"):
                return (200, Data(Self.serverInfo("newbie", "Newbie", bootstrap: false).utf8))
            case ("access", "/v1/server"):
                return (200, Data(Self.serverInfo("access", "Access", bootstrap: false).utf8))
            case ("access", "/v1/operator"):
                noderequests.withLock { $0.append(request.value(forHTTPHeaderField: "Authorization")) }
                return request.value(forHTTPHeaderField: "Authorization") == "Bearer key-a"
                    ? (200, Data(Self.active.utf8)) : (401, Data())
            case ("locked", "/v1/server"):
                return (200, Data(Self.serverInfo("locked", "Locked", bootstrap: false).utf8))
            case ("locked", "/v1/operator"):
                noderequests.withLock { $0.append(request.value(forHTTPHeaderField: "Authorization")) }
                return (401, Data())
            default:
                return nil
            }
        }

        let rows = await console.refresh()

        #expect(try row("boot", in: rows).classification == .bootstrap)
        let newbie = try row("newbie", in: rows)
        #expect(newbie.classification == .withoutAccess)
        #expect(newbie.lastKnownAccess == nil, "never asked, so no verdict")
        let access = try row("access", in: rows)
        #expect(access.classification == .withAccess)
        #expect(access.lastKnownAccess == true)
        let locked = try row("locked", in: rows)
        #expect(locked.classification == .withoutAccess)
        #expect(locked.lastKnownAccess == false, "the refusal is the last thing known of it")
        let nohands = try row("nohands", in: rows)
        #expect(nohands.classification == .unreachable)
        #expect(nohands.lastKnownAccess == nil, "the registry kept no verdict for it")
        #expect(Set(rows.map(\.id)).count == 5, "each silo exactly one row")
        #expect(
            noderequests.withLock { $0 }.map { $0 ?? "(none)" }.sorted() == ["Bearer key-a", "Bearer key-b"],
            "the probe asks only reachable silos with a passkey, with that passkey as bearer"
        )
    }

    @Test func theProbeDecides() async throws {
        let registry = SiloRegistry()
        try registry.merge(
            RegisteredSilo(
                id: "probe",
                name: "Probe",
                url: URL(string: "http://probe.local:8080")!,
                lastSeen: Self.clock,
                hasStoredPasskey: true
            )
        )
        let passkeys = InMemoryPasskeyStore()
        passkeys.store("held", for: "probe")
        let accepts = Mutex("held")
        let console = Self.console(
            registry: registry,
            passkeys: passkeys,
            discovered: [DiscoveredSilo(name: "Probe", host: "probe.local", port: 8080)]
        ) { request in
            guard let url = request.url else { return nil }
            switch url.path {
            case "/v1/server": return (200, Data(Self.serverInfo("probe", "Probe", bootstrap: false).utf8))
            case "/v1/operator":
                return request.value(forHTTPHeaderField: "Authorization") == "Bearer \(accepts.withLock { $0 })"
                    ? (200, Data(Self.active.utf8)) : (401, Data())
            default: return nil
            }
        }

        let first = try row("probe", in: await console.refresh())
        #expect(first.classification == .withAccess)
        #expect(first.lastKnownAccess == true)

        accepts.withLock { $0 = "rotated" }
        let second = try row("probe", in: await console.refresh())
        #expect(second.classification == .withoutAccess)
        #expect(second.lastKnownAccess == false, "the probe's refusal is what is now known")
        #expect(passkeys.passkey(for: "probe") == "held", "a refused probe removes nothing")
    }

    @Test func unreachableIsLastKnownNotUnknown() async throws {
        let registry = SiloRegistry()
        try registry.merge(
            RegisteredSilo(
                id: "home",
                name: "Home Silo",
                url: URL(string: "http://home.local:8080")!,
                lastSeen: Self.clock,
                hasStoredPasskey: true
            )
        )
        let passkeys = InMemoryPasskeyStore()
        passkeys.store("key", for: "home")
        let alive = Mutex(true)
        let probed = Mutex(0)
        let console = Self.console(
            registry: registry,
            passkeys: passkeys,
            discovered: [DiscoveredSilo(name: "Home Silo", host: "home.local", port: 8080)]
        ) { request in
            guard alive.withLock({ $0 }), let url = request.url else { return nil }
            switch url.path {
            case "/v1/server": return (200, Data(Self.serverInfo("home", "Home Silo", bootstrap: false).utf8))
            case "/v1/operator":
                probed.withLock { $0 += 1 }
                return (200, Data(Self.active.utf8))
            default: return nil
            }
        }

        #expect(try row("home", in: await console.refresh()).classification == .withAccess)
        #expect(registry.entry(for: "home")?.lastKnownAccess == true, "the verdict outlives the refresh that earned it")
        #expect(probed.withLock { $0 } == 1)

        alive.withLock { $0 = false }
        let held = try row("home", in: await console.refresh())
        #expect(held.classification == .withAccess, "one miss changes nothing the operator can see")
        #expect(held.lastSeen == Self.clock)

        let gone = try row("home", in: await console.refresh())
        #expect(gone.classification == .unreachable)
        #expect(gone.lastKnownAccess == true, "last-known, not unknown")
        #expect(gone.lastSeen == Self.clock)
        #expect(probed.withLock { $0 } == 1, "an unreachable silo is not probed")
    }

    @Test func oneMissDisturbsNothing() async throws {
        let alive = Mutex(true)
        let console = Self.console(discovered: [DiscoveredSilo(name: "Attic Silo", host: "attic.local", port: 8080)]) {
            request in
            guard alive.withLock({ $0 }), let url = request.url, url.host == "attic.local", url.path == "/v1/server"
            else { return nil }
            return (200, Data(Self.serverInfo("attic", "Attic Silo", bootstrap: true).utf8))
        }

        let met = try row("attic", in: await console.refresh())
        #expect(met.classification == .bootstrap)
        #expect(met.lastSeen == Self.clock)

        alive.withLock { $0 = false }
        let held = try row("attic", in: await console.refresh())
        #expect(held.classification == .bootstrap, "the last verified class holds through one miss")
        #expect(held.lastSeen == Self.clock, "the last-seen clock stands still")

        let quiet = try row("attic", in: await console.refresh())
        #expect(quiet.classification == .unreachable, "the second consecutive miss may call it quiet")
        #expect(quiet.lastSeen == Self.clock)
    }

    @Test func contactHealsAtOnce() async throws {
        let registry = SiloRegistry()
        try registry.merge(
            RegisteredSilo(
                id: "probe",
                name: "Probe",
                url: URL(string: "http://probe.local:8080")!,
                lastSeen: Self.clock,
                hasStoredPasskey: true
            )
        )
        let passkeys = InMemoryPasskeyStore()
        passkeys.store("held", for: "probe")
        let alive = Mutex(true)
        let accepts = Mutex("held")
        let console = Self.console(
            registry: registry,
            passkeys: passkeys,
            discovered: [DiscoveredSilo(name: "Probe", host: "probe.local", port: 8080)]
        ) { request in
            guard alive.withLock({ $0 }), let url = request.url else { return nil }
            switch url.path {
            case "/v1/server": return (200, Data(Self.serverInfo("probe", "Probe", bootstrap: false).utf8))
            case "/v1/operator":
                return request.value(forHTTPHeaderField: "Authorization") == "Bearer \(accepts.withLock { $0 })"
                    ? (200, Data(Self.active.utf8)) : (401, Data())
            default: return nil
            }
        }

        #expect(try row("probe", in: await console.refresh()).classification == .withAccess)

        alive.withLock { $0 = false }
        #expect(
            try row("probe", in: await console.refresh()).classification == .withAccess,
            "one miss holds the last verified class"
        )

        accepts.withLock { $0 = "rotated" }
        alive.withLock { $0 = true }
        let healed = try row("probe", in: await console.refresh())
        #expect(healed.classification == .withoutAccess, "contact renders this sweep's verdict at once, whatever it is")
        #expect(healed.lastKnownAccess == false, "the refusal is what is now known")
    }

    @Test func launchedIntoSilenceReadsTheRegistrysVerdicts() async throws {
        let registry = SiloRegistry()
        try registry.merge(
            RegisteredSilo(
                id: "home",
                name: "Home Silo",
                url: URL(string: "http://home.local:8080")!,
                lastSeen: Self.clock,
                hasStoredPasskey: true,
                lastKnownAccess: true
            )
        )
        try registry.merge(
            RegisteredSilo(
                id: "attic",
                name: "Attic Silo",
                url: URL(string: "http://attic.local:8080")!,
                lastSeen: Self.clock,
                hasStoredPasskey: false
            )
        )
        let passkeys = InMemoryPasskeyStore()
        passkeys.store("key", for: "home")
        let probed = Mutex(0)
        let console = Self.console(
            registry: registry,
            passkeys: passkeys,
            discovered: [DiscoveredSilo(name: "Home Silo", host: "home.local", port: 8080)]
        ) { request in
            if request.url?.path == "/v1/operator" { probed.withLock { $0 += 1 } }
            return nil
        }

        let rows = await console.refresh()
        #expect(try row("home", in: rows).classification == .withAccess, "a kept access verdict holds the first miss")
        #expect(try row("attic", in: rows).classification == .unreachable, "nothing recorded, so nothing to hold")
        #expect(probed.withLock { $0 } == 0, "a missed silo is never probed")

        let again = await console.refresh()
        let gone = try row("home", in: again)
        #expect(gone.classification == .unreachable, "the second miss is the one that calls it quiet")
        #expect(gone.lastKnownAccess == true, "last-known, not unknown")
    }

    // MARK: - One sweep at a time

    @Test func twoCallsOneSweep() async throws {
        let asked = Mutex(0)
        let console = Self.console(discovered: [DiscoveredSilo(name: "Hall Silo", host: "hall.local", port: 8080)]) {
            request in
            guard let url = request.url, url.host == "hall.local", url.path == "/v1/server" else { return nil }
            asked.withLock { $0 += 1 }
            Thread.sleep(forTimeInterval: 0.15)
            return (200, Data(Self.serverInfo("hall", "Hall Silo", bootstrap: true).utf8))
        }

        async let first = console.refresh()
        async let second = console.refresh()
        let (one, two) = await (first, second)

        #expect(asked.withLock { $0 } == 1, "the second call joins the sweep in flight — the silo is asked once")
        #expect(one.map(\.id) == two.map(\.id), "both callers receive the sweep's rows")
    }

    // MARK: - The setup flow

    @Test func setupFromTheChair() async throws {
        let store = InMemoryPasskeyStore()
        let registry = SiloRegistry()
        let wire = Mutex<[String]>([])
        let console = Self.console(
            registry: registry,
            passkeys: store,
            discovered: [DiscoveredSilo(name: "Fresh Silo", host: "fresh.local", port: 8080)]
        ) { request in
            guard let url = request.url else { return nil }
            switch url.path {
            case "/v1/server":
                return request.httpMethod == "GET"
                    ? (200, Data(Self.serverInfo("s1", "Fresh Silo", bootstrap: true).utf8)) : nil
            case "/v1/setup":
                wire.withLock { $0.append("stage") }
                return (202, Data(#"{"id":"s1","name":"Living Room Silo","confirmBy":"2026-09-24T10:10:00Z"}"#.utf8))
            case "/v1/setup/confirm":
                if store.passkey(for: "s1") == nil { Issue.record("the confirm raced the Keychain write") }
                wire.withLock { $0.append("confirm") }
                return (201, Data(Self.serverInfo("s1", "Living Room Silo", bootstrap: false).utf8))
            default:
                return nil
            }
        }

        let fresh = try row("s1", in: await console.refresh())
        let prepared = try await console.prepareSetup(fresh)
        guard case .minted(let shown) = prepared.presentation else {
            Issue.record("a fresh attempt mints and shows the passkey")
            return
        }

        let rendered = try await console.runSetup(prepared, name: "Living Room Silo")

        #expect(wire.withLock { $0 } == ["stage", "confirm"])
        #expect(store.passkey(for: "s1") == shown, "the passkey is stored before the confirm is sent")
        #expect(rendered.classification == .withAccess)
        #expect(rendered.lastKnownAccess == true)
        #expect(rendered.name == "Living Room Silo")
        let merged = try #require(registry.entry(for: "s1"))
        #expect(merged.hasStoredPasskey)
        #expect(merged.lastKnownAccess == true)
        #expect(
            try row("s1", in: await console.silos).classification == .withAccess,
            "the rendered list moves with the flow"
        )
    }

    @Test func aLiveStageIsFinishedByConsent() async throws {
        let store = InMemoryPasskeyStore()
        store.store("kept-from-attempt-one", for: "s7")
        let wire = Mutex<[String]>([])
        let console = Self.console(
            passkeys: store,
            discovered: [DiscoveredSilo(name: "Fresh Silo", host: "fresh.local", port: 8080)]
        ) { request in
            guard let url = request.url else { return nil }
            wire.withLock { $0.append("\(request.httpMethod ?? "?") \(url.path)") }
            switch url.path {
            case "/v1/server":
                return request.httpMethod == "GET"
                    ? (200, Data(Self.serverInfo("s7", "Fresh Silo", bootstrap: true).utf8)) : nil
            case "/v1/operator":
                return request.value(forHTTPHeaderField: "Authorization") == "Bearer kept-from-attempt-one"
                    ? (200, Data(#"{"phase":"pending","confirmBy":"2026-09-24T10:10:00Z"}"#.utf8))
                    : (401, Data())
            case "/v1/setup":
                Issue.record("a resumed stage re-stages nothing")
                return nil
            case "/v1/setup/confirm":
                #expect(
                    request.value(forHTTPHeaderField: "Authorization") == "Bearer kept-from-attempt-one",
                    "the confirm spends the residue, not something minted"
                )
                return (201, Data(Self.serverInfo("s7", "Fresh Silo", bootstrap: false).utf8))
            default:
                return nil
            }
        }

        let fresh = try row("s7", in: await console.refresh())
        let prepared = try await console.prepareSetup(fresh)
        #expect(prepared.presentation == .reused, "the residue is never shown again")
        #expect(
            prepared.resumingUntil?.timeIntervalSince1970 == 1_790_244_600,
            "the sheet learns when the standing window shuts"
        )

        let rendered = try await console.runSetup(prepared, name: nil)

        #expect(rendered.classification == .withAccess)
        #expect(rendered.lastKnownAccess == true)
        #expect(
            wire.withLock { $0 } == ["GET /v1/server", "GET /v1/operator", "POST /v1/setup/confirm"],
            "probe first; consent sends the confirm alone"
        )
    }

    @Test func aDeadResidueIsReplaced() async throws {
        let store = InMemoryPasskeyStore()
        store.store("dead-key", for: "s8")
        let staged = Mutex<String?>(nil)
        let heldAtConfirm = Mutex<String?>(nil)
        let wire = Mutex<[String]>([])
        let console = Self.console(
            passkeys: store,
            discovered: [DiscoveredSilo(name: "Fresh Silo", host: "fresh.local", port: 8080)]
        ) { request in
            guard let url = request.url else { return nil }
            wire.withLock { $0.append("\(request.httpMethod ?? "?") \(url.path)") }
            switch url.path {
            case "/v1/server":
                return request.httpMethod == "GET"
                    ? (200, Data(Self.serverInfo("s8", "Fresh Silo", bootstrap: true).utf8)) : nil
            case "/v1/operator":
                return (401, Data())
            case "/v1/setup":
                let body = Self.body(of: request).flatMap {
                    try? JSONSerialization.jsonObject(with: $0) as? [String: String]
                }
                staged.withLock { $0 = body?["passkey"] }
                return (202, Data(#"{"id":"s8","name":"Fresh Silo","confirmBy":"2026-09-24T10:10:00Z"}"#.utf8))
            case "/v1/setup/confirm":
                heldAtConfirm.withLock { $0 = store.passkey(for: "s8") }
                return (201, Data(Self.serverInfo("s8", "Fresh Silo", bootstrap: false).utf8))
            default:
                return nil
            }
        }

        let fresh = try row("s8", in: await console.refresh())
        let prepared = try await console.prepareSetup(fresh)
        guard case .minted(let shown) = prepared.presentation else {
            Issue.record("a dead residue is replaced, not reused")
            return
        }
        #expect(shown != "dead-key")
        #expect(prepared.resumingUntil == nil, "a dead stage offers nothing to finish")
        #expect(store.passkey(for: "s8") == "dead-key", "the residue is discarded only by being replaced")

        _ = try await console.runSetup(prepared, name: nil)

        #expect(staged.withLock { $0 } == shown, "the new stage sends the fresh mint, not the residue")
        #expect(heldAtConfirm.withLock { $0 } == shown, "the write-ahead overwrote the residue in the Keychain")
        #expect(
            wire.withLock { $0 } == ["GET /v1/server", "GET /v1/operator", "POST /v1/setup", "POST /v1/setup/confirm"],
            "probe first, then the pair in full"
        )
    }

    @Test func someoneElseGotThereFirst() async throws {
        let store = InMemoryPasskeyStore()
        store.store("stay-key", for: "residue")
        let console = Self.console(
            passkeys: store,
            discovered: [
                DiscoveredSilo(name: "Fresh", host: "fresh.local", port: 8080),
                DiscoveredSilo(name: "Residue", host: "residue.local", port: 8080),
            ]
        ) { request in
            guard let url = request.url, let host = url.host else { return nil }
            let id = host == "fresh.local" ? "fresh" : "residue"
            switch url.path {
            case "/v1/server": return (200, Data(Self.serverInfo(id, id, bootstrap: true).utf8))
            case "/v1/setup": return (410, Data())
            case "/v1/operator": return (401, Data())
            default: return nil
            }
        }
        let rows = await console.refresh()

        let fresh = try await console.prepareSetup(row("fresh", in: rows))
        guard case .minted(let minted) = fresh.presentation else {
            Issue.record("nothing held, so minted")
            return
        }
        do {
            _ = try await console.runSetup(fresh, name: nil)
            Issue.record("a finished silo must refuse the staging")
        } catch AdminConsole.SetupRefusal.noLongerInBootstrap {}
        #expect(store.passkey(for: "fresh") == nil, "the minted passkey is discarded, not filed")
        #expect(minted != "stay-key")
        let finished = try row("fresh", in: await console.silos)
        #expect(finished.classification == .withoutAccess, "classified by the probe's refusal")
        #expect(finished.lastKnownAccess == nil, "nothing held, so nothing asked")

        let residue = try await console.prepareSetup(row("residue", in: rows))
        do {
            _ = try await console.runSetup(residue, name: nil)
            Issue.record("a finished silo must refuse the staging")
        } catch AdminConsole.SetupRefusal.noLongerInBootstrap {}
        #expect(store.passkey(for: "residue") == "stay-key", "what the Keychain held from before stays")
        let held = try row("residue", in: await console.silos)
        #expect(held.classification == .withoutAccess)
        #expect(held.lastKnownAccess == false, "the held key was asked and refused")
    }

    @Test func setupStagedElsewhere() async throws {
        let store = InMemoryPasskeyStore()
        let registry = SiloRegistry()
        let wire = Mutex<[String]>([])
        let console = Self.console(
            registry: registry,
            passkeys: store,
            discovered: [DiscoveredSilo(name: "Busy Silo", host: "busy.local", port: 8080)]
        ) { request in
            guard let url = request.url else { return nil }
            wire.withLock { $0.append(url.path) }
            switch url.path {
            case "/v1/server": return (200, Data(Self.serverInfo("busy", "Busy Silo", bootstrap: true).utf8))
            case "/v1/setup": return (409, Data(#"{"confirmBy":"2026-09-24T10:10:00Z"}"#.utf8))
            default: return nil
            }
        }

        let busy = try row("busy", in: await console.refresh())
        let prepared = try await console.prepareSetup(busy)

        do {
            _ = try await console.runSetup(prepared, name: nil)
            Issue.record("staging over another console's stage")
        } catch AdminConsole.SetupRefusal.stagedElsewhere(let until) {
            #expect(until.timeIntervalSince1970 == 1_790_244_600, "the operator is shown the window being waited out")
        }
        #expect(store.passkey(for: "busy") == nil)
        #expect(registry.entry(for: "busy")?.hasStoredPasskey != true)
        #expect(wire.withLock { $0 } == ["/v1/server", "/v1/setup"], "nothing follows a 409 — no store, no confirm")
    }

    // MARK: - Claim

    @Test func wrongPasskeyNothingKept() async throws {
        let registry = SiloRegistry()
        try registry.merge(
            RegisteredSilo(
                id: "known",
                name: "Known Silo",
                url: URL(string: "http://known.local:8080")!,
                lastSeen: Self.clock,
                hasStoredPasskey: false
            )
        )
        let store = InMemoryPasskeyStore()
        let console = Self.console(registry: registry, passkeys: store) { request in
            guard let url = request.url else { return nil }
            switch url.path {
            case "/v1/server": return (200, Data(Self.serverInfo("known", "Known Silo", bootstrap: false).utf8))
            case "/v1/operator": return (401, Data())
            default: return nil
            }
        }

        let rows = await console.refresh(typedURLs: [URL(string: "http://known.local:8080")!])
        let known = try row("known", in: rows)
        #expect(known.classification == .withoutAccess)

        do {
            _ = try await console.claim(known, passkey: "nope")
            Issue.record("a refused passkey must keep nothing")
        } catch is AdminConsole.ClaimRefused {}
        #expect(store.passkey(for: "known") == nil)
        #expect(registry.entry(for: "known")?.hasStoredPasskey == false)
        let spared = try row("known", in: await console.refresh(typedURLs: [URL(string: "http://known.local:8080")!]))
        #expect(spared.classification == .withoutAccess, "the silo stays without access")
        #expect(spared.lastKnownAccess == nil, "a refused claim leaves nothing stored, so nothing probed")
    }

    @Test func aClaimVerifiesBeforeItStores() async throws {
        let registry = SiloRegistry()
        let store = InMemoryPasskeyStore()
        let storedTooSoon = Mutex(false)
        let console = Self.console(registry: registry, passkeys: store) { request in
            guard let url = request.url else { return nil }
            switch url.path {
            case "/v1/server": return (200, Data(Self.serverInfo("found", "Found Silo", bootstrap: false).utf8))
            case "/v1/operator":
                if store.passkey(for: "found") != nil { storedTooSoon.withLock { $0 = true } }
                return request.value(forHTTPHeaderField: "Authorization") == "Bearer filed"
                    ? (200, Data(Self.active.utf8)) : (401, Data())
            default: return nil
            }
        }

        let found = try row("found", in: await console.refresh(typedURLs: [URL(string: "http://found.local:8080")!]))
        #expect(found.classification == .withoutAccess, "never met and met-then-refused are the same act")

        let claimed = try await console.claim(found, passkey: "filed")

        #expect(!storedTooSoon.withLock { $0 }, "the probe is the gate, not the aftermath")
        #expect(claimed.classification == .withAccess)
        #expect(claimed.lastKnownAccess == true)
        #expect(store.passkey(for: "found") == "filed")
        let merged = try #require(registry.entry(for: "found"))
        #expect(merged.hasStoredPasskey)
        #expect(merged.lastKnownAccess == true)
    }

    // MARK: - Settings

    private static func settingsReport(name: String, embeddedNode: Bool = false) -> String {
        #"{"editable":{"name":"\#(name)","embeddedNode":\#(embeddedNode),"advertise":true,"libraries":[{"id":"films","path":"/srv/media/films"}]},"readOnly":{"serverID":"home","host":"0.0.0.0","port":8742,"libraryRoots":["/srv/media"],"stateDirectory":"/var/lib/silo"}}"#
    }

    @Test func settingsAreAskedWithTheHeldPasskey() async throws {
        let passkeys = InMemoryPasskeyStore()
        passkeys.store("held", for: "home")
        let console = Self.console(
            passkeys: passkeys,
            discovered: [DiscoveredSilo(name: "Home Silo", host: "home.local", port: 8742)]
        ) { request in
            guard let url = request.url else { return nil }
            let operatorBearer = request.value(forHTTPHeaderField: "Authorization") == "Bearer held"
            switch url.path {
            case "/v1/server": return (200, Data(Self.serverInfo("home", "Home Silo", bootstrap: false).utf8))
            case "/v1/operator": return operatorBearer ? (200, Data(Self.active.utf8)) : (401, Data())
            case "/v1/settings":
                return operatorBearer ? (200, Data(Self.settingsReport(name: "Home Silo").utf8)) : (401, Data())
            default: return nil
            }
        }
        let home = try row("home", in: await console.refresh())
        #expect(home.classification == .withAccess)

        let report = try await console.settings(of: home)
        #expect(
            report.editable
                == SiloClient.SettingsReport.Editable(
                    name: "Home Silo",
                    embeddedNode: false,
                    advertise: true,
                    libraries: [SiloClient.SettingsReport.Library(id: "films", path: "/srv/media/films")]
                )
        )
        #expect(report.readOnly.stateDirectory == "/var/lib/silo")
        #expect(report.readOnly.libraryRoots == ["/srv/media"])

        passkeys.store("rotated-away", for: "home")
        await #expect(throws: AdminConsole.NoAccess.self) { try await console.settings(of: home) }
        passkeys.remove(for: "home")
        await #expect(throws: AdminConsole.NoAccess.self) { try await console.settings(of: home) }
    }

    @Test func aSettingsChangeSendsOnlyWhatChangedAndARenameIsRendered() async throws {
        let registry = SiloRegistry()
        let passkeys = InMemoryPasskeyStore()
        passkeys.store("held", for: "home")
        let sent = Mutex<[String]>([])
        let console = Self.console(
            registry: registry,
            passkeys: passkeys,
            discovered: [DiscoveredSilo(name: "Home Silo", host: "home.local", port: 8742)]
        ) { request in
            guard let url = request.url else { return nil }
            switch (request.httpMethod, url.path) {
            case (_, "/v1/server"): return (200, Data(Self.serverInfo("home", "Home Silo", bootstrap: false).utf8))
            case (_, "/v1/operator"): return (200, Data(Self.active.utf8))
            case ("PATCH", "/v1/settings"):
                let body = String(decoding: Self.body(of: request) ?? Data(), as: UTF8.self)
                sent.withLock { $0.append(body) }
                struct Patch: Decodable { var name: String? }
                let patch = try JSONDecoder().decode(Patch.self, from: Data(body.utf8))
                if patch.name == "" { return (400, Data(#"{"detail":"the name cannot be empty"}"#.utf8)) }
                return (200, Data(Self.settingsReport(name: patch.name ?? "Home Silo", embeddedNode: true).utf8))
            default: return nil
            }
        }
        let home = try row("home", in: await console.refresh())

        await #expect(throws: AdminConsole.SettingsRefused(reason: "the name cannot be empty")) {
            try await console.updateSettings(of: home, SiloClient.SettingsPatch(name: ""))
        }
        #expect(try row("home", in: await console.silos).name == "Home Silo", "a refusal changes nothing")

        let report = try await console.updateSettings(of: home, SiloClient.SettingsPatch(name: "Loft Silo"))
        #expect(report.editable.name == "Loft Silo")
        #expect(sent.withLock { $0.last } == #"{"name":"Loft Silo"}"#, "only what changed travels")
        #expect(try row("home", in: await console.silos).name == "Loft Silo", "the row takes the new name at once")
        #expect(registry.entry(for: "home")?.name == "Loft Silo", "and the registry keeps it")
    }

    // MARK: - Rulesets

    /// A silo with access holding `household`: version 3 on the standard, version 4 on a trial branch,
    /// and version 3's audio rules every one of them conditioned.
    private static func rulesetSilo(
        pending: Int = 0,
        asked: @escaping @Sendable (String) -> Void
    ) -> @Sendable (URLRequest) throws -> (Int, Data)? {
        { request in
            guard let url = request.url else { return nil }
            asked(url.path + (url.query.map { "?\($0)" } ?? ""))
            switch url.path {
            case "/v1/server": return (200, Data(Self.serverInfo("home", "Home Silo", bootstrap: false).utf8))
            case "/v1/operator": return (200, Data(Self.active.utf8))
            case "/v1/settings": return (200, Data(Self.settingsReport(name: "Home Silo").utf8))
            case "/v1/rulesets":
                return (
                    200,
                    Data(
                        #"[{"name":"household","version":4,"standard":3,"versions":[{"version":1,"branch":"standard","presentations":3},{"version":2,"branch":"standard","parent":1,"presentations":0},{"version":3,"branch":"standard","parent":2,"presentations":1},{"version":4,"branch":"trial","parent":3,"presentations":0}]}]"#
                            .utf8
                    )
                )
            case "/v1/rulesets/household/branches":
                return (
                    200,
                    Data(
                        #"[{"name":"standard","head":3,"closed":false},{"name":"trial","base":3,"head":4,"upToDateWith":3,"closed":false}]"#
                            .utf8
                    )
                )
            case "/v1/rulesets/household":
                let reading =
                    ##"{"name":"household","rules":[{"name":"#1","scope":"video","conditions":[],"action":{"copy":{}}},{"name":"lossless-main","scope":"audio","conditions":[{"fact":"audio.lossless","test":"is","value":"true"}],"action":{"copy":{}}},{"name":"commentary","scope":"audio","conditions":[{"fact":"audio.role","test":"is","value":"commentary"}],"action":{"encode":{"_0":{"codec":"aac","bitrate":"96k","channels":2,"filters":[],"options":{}}}}}],"outputs":[{"container":"mkv"}]}"##
                return (
                    200,
                    Data(
                        ##"{"name":"household","version":3,"branch":"standard","document":"<ruleset/>","reading":\##(reading)}"##
                            .utf8
                    )
                )
            case "/v1/libraries/films/out-of-date":
                let stack = #"{"ruleset":{"name":"household","version":1},"layers":[]}"#
                return (
                    200,
                    Data(
                        #"{"presentations":[{"container":"00000000000000f1","item":"feature","recipe":"r1","outcome":"outOfDate","madeBy":\#(stack),"checkedAgainst":{"ruleset":{"name":"household","version":3},"layers":[]},"changes":[{"kind":"audio","index":2,"was":{"copy":{}},"now":{"drop":{}}}],"sources":[{"id":"s1","copies":[]}]}],"pending":\#(pending),"placedWithoutJob":0}"#
                            .utf8
                    )
                )
            default: return nil
            }
        }
    }

    @Test func aRulesetOpensAtItsStandardsHeadBesideTheSilosReading() async throws {
        let passkeys = InMemoryPasskeyStore()
        passkeys.store("held", for: "home")
        let sent = Mutex<[String]>([])
        let console = Self.console(
            passkeys: passkeys,
            discovered: [DiscoveredSilo(name: "Home Silo", host: "home.local", port: 8742)],
            answering: Self.rulesetSilo { path in sent.withLock { $0.append(path) } }
        )
        let home = try row("home", in: await console.refresh())

        let opened = try await console.open(ruleset: "household", of: home)
        #expect(
            sent.withLock { $0 }.contains("/v1/rulesets/household?version=3"),
            "the standard's head, not the latest version, which is on a branch"
        )
        #expect(opened.document.version == 3)
        #expect(opened.branches.map(\.name) == ["standard", "trial"])
        #expect(opened.summary.versions?.map(\.presentations) == [3, 0, 1, 0])
        let reading = try #require(opened.document.reading)
        #expect(reading.byScope.map(\.scope) == [.video, .audio])
        #expect(
            reading.byScope[1].rules.map(\.name) == ["lossless-main", "commentary"],
            "in document order within the scope"
        )
        #expect(reading.scopesWithoutCatchAll == [.audio], "every audio rule has conditions; the video rule has none")
        #expect(reading.rules[2].action.summary == "encode aac 96k 2ch")

        _ = try await console.open(ruleset: "household", version: 4, of: home)
        #expect(sent.withLock { $0 }.last == "/v1/rulesets/household?version=4", "and any other version, when chosen")
    }

    @Test func eachLibrarysOutOfDateIsReadWithWhatIsStillToCheck() async throws {
        let passkeys = InMemoryPasskeyStore()
        passkeys.store("held", for: "home")
        let sent = Mutex<[String]>([])
        let console = Self.console(
            passkeys: passkeys,
            discovered: [DiscoveredSilo(name: "Home Silo", host: "home.local", port: 8742)],
            answering: Self.rulesetSilo(pending: 12) { path in sent.withLock { $0.append(path) } }
        )
        let home = try row("home", in: await console.refresh())

        let reports = try await console.outOfDate(of: home)
        #expect(reports.map(\.library) == ["films"])
        #expect(reports[0].report.pending == 12, "twelve still to be checked")
        let presentation = try #require(reports[0].report.presentations.first)
        #expect(presentation.madeBy.summary == "household@1")
        #expect(presentation.changes.map { "\($0.was.summary) → \($0.now.summary)" } == ["copy → drop"])
        #expect(!presentation.everySourceHasACopy, "its one source has no copy")
        #expect(
            !sent.withLock { $0 }.contains { $0.contains("/jobs") || $0.contains("/apply") },
            "and nothing is made again"
        )
    }

    // MARK: - Changing rulesets

    /// What the changing silo was sent: method, path with its query, and body.
    private struct Asked: Sendable {
        var method: String
        var path: String
        var body: String
    }

    /// A silo with access holding `household` on its standard at version `head`, with a trial branch
    /// from version 1 up to date with it, whose stores and promotions answer as the silo's would.
    private static func changingSilo(
        head: Int,
        asked: @escaping @Sendable (Asked) -> Void
    ) -> @Sendable (URLRequest) throws -> (Int, Data)? {
        { request in
            guard let url = request.url else { return nil }
            let method = request.httpMethod ?? "GET"
            let body = String(decoding: Self.body(of: request) ?? Data(), as: UTF8.self)
            asked(Asked(method: method, path: url.path + (url.query.map { "?\($0)" } ?? ""), body: body))
            func document(_ version: Int, branch: String = "standard") -> Data {
                Data(
                    #"{"name":"household","version":\#(version),"branch":"\#(branch)","document":"<v\#(version)/>"}"#
                        .utf8
                )
            }
            switch (method, url.path) {
            case (_, "/v1/server"): return (200, Data(Self.serverInfo("home", "Home Silo", bootstrap: false).utf8))
            case (_, "/v1/operator"): return (200, Data(Self.active.utf8))
            case ("POST", "/v1/rulesets/household/check"):
                if body.contains("subtitle.forcd") {
                    return (400, Data(#"{"detail":"subtitle.forcd is not a fact a rule can test"}"#.utf8))
                }
                return (200, Data(#"{"name":"household","rules":[],"outputs":[{"container":"mkv"}]}"#.utf8))
            case ("POST", "/v1/rulesets/household/impact"): return (200, Data("[]".utf8))
            case ("PUT", "/v1/rulesets/household"):
                struct Store: Decodable {
                    var basedOn: Int?
                    var branch: String?
                }
                let store = try JSONDecoder().decode(Store.self, from: Data(body.utf8))
                if store.branch == nil || store.branch == "standard", let based = store.basedOn, based != head {
                    return (
                        409,
                        Data(
                            #"{"detail":"household's standard is at household@\#(head), not household@\#(based)"}"#.utf8
                        )
                    )
                }
                return (201, document(head + 1, branch: store.branch ?? "standard"))
            case ("POST", "/v1/rulesets/household/branches"):
                return (
                    201,
                    Data(
                        #"{"name":"speech","base":\#(head),"head":\#(head),"upToDateWith":\#(head),"closed":false}"#
                            .utf8
                    )
                )
            case (_, "/v1/rulesets/household/branches"):
                return (
                    200,
                    Data(
                        #"[{"name":"standard","head":\#(head),"closed":false},{"name":"trial","base":1,"head":2,"upToDateWith":1,"closed":false}]"#
                            .utf8
                    )
                )
            case (_, "/v1/rulesets"):
                let versions =
                    ([
                        #"{"version":1,"branch":"standard","presentations":0}"#,
                        #"{"version":2,"branch":"trial","parent":1,"presentations":0}"#,
                    ]
                    + (3...max(3, head)).map { #"{"version":\#($0),"branch":"standard","presentations":0}"# }).joined(
                        separator: ","
                    )
                return (
                    200,
                    Data(
                        #"[{"name":"household","version":\#(head),"standard":\#(head),"versions":[\#(versions)]}]"#.utf8
                    )
                )
            case (_, "/v1/rulesets/household"):
                let version = url.query.flatMap { Int($0.replacingOccurrences(of: "version=", with: "")) } ?? head
                return (200, document(version, branch: version == 2 ? "trial" : "standard"))
            case ("POST", "/v1/rulesets/household/branches/trial/promote"):
                return (
                    409,
                    Data(
                        #"{"detail":"household's branch trial has not taken in household@3, household@\#(head) from the standard"}"#
                            .utf8
                    )
                )
            case (_, "/v1/rulesets/household/branches/trial/impact"): return (200, Data("[]".utf8))
            case ("PUT", "/v1/libraries/films/ruleset"):
                return body.contains("nothing")
                    ? (404, Data())
                    : (
                        200,
                        Data(
                            #"{"id":"films","ruleset":"household","containers":2,"presentations":5,"available":true}"#
                                .utf8
                        )
                    )
            case ("GET", "/v1/libraries"):
                return (200, Data(#"[{"id":"films","containers":2,"presentations":5,"available":false}]"#.utf8))
            case ("GET", "/v1/libraries/films/scan"):
                return (
                    200,
                    Data(
                        #"{"walkedAt":"2026-10-19T09:30:00Z","available":false,"report":{"read":0,"unchanged":0,"removed":0,"findings":[{"severity":"error","text":"not applied: its folder does not exist"}]}}"#
                            .utf8
                    )
                )
            case ("POST", "/v1/libraries/check"):
                return (
                    200,
                    Data(
                        #"{"path":"/srv/media/Shows/New","components":[{"path":"/srv","state":"folder"},{"path":"/srv/media","state":"folder"},{"path":"/srv/media/Shows","state":"missing"},{"path":"/srv/media/Shows/New","state":"missing"}],"root":"/srv/media","creates":["/srv/media/Shows","/srv/media/Shows/New"]\#(body.contains("create") ? "" : #","refusal":{"status":422,"detail":"/srv/media/Shows/New is not a folder that exists"}"#)}"#
                            .utf8
                    )
                )
            case ("POST", "/v1/libraries"):
                if body.contains("etc") {
                    return (403, Data(#"{"detail":"/etc lies within none of the library roots: /srv/media"}"#.utf8))
                }
                return (201, Data(#"{"id":"shows","containers":4,"presentations":40,"available":true}"#.utf8))
            case ("DELETE", "/v1/libraries/films"):
                return (409, Data(#"{"detail":"job j1 is encoding and files into films"}"#.utf8))
            case ("DELETE", "/v1/libraries/shows"): return (204, Data())
            default: return nil
            }
        }
    }

    private static func homeWithAccess(head: Int) async throws -> (AdminConsole, AdminConsole.Silo) {
        let passkeys = InMemoryPasskeyStore()
        passkeys.store("held", for: "home")
        let console = Self.console(
            passkeys: passkeys,
            discovered: [DiscoveredSilo(name: "Home Silo", host: "home.local", port: 8742)],
            answering: Self.changingSilo(head: head) { _ in }
        )
        let home = try #require(await console.refresh().first { $0.id == "home" })
        return (console, home)
    }

    @Test func aMistypedFactIsRefusedBeforeTheStore() async throws {
        let asked = Mutex<[Asked]>([])
        let (console, home) = try await Self.homeWithAccess(head: 3)
        Self.answer(with: Self.changingSilo(head: 3) { request in asked.withLock { $0.append(request) } })
        var draft = Draft.change(try await console.open(ruleset: "household", of: home).document)
        guard case .reading = try await console.check(draft, of: home) else {
            Issue.record("a draft that reads is read")
            return
        }
        draft.text =
            #"<ruleset format="1" name="household"><subtitle><when fact="subtitle.forcd" is="true"/><copy/></subtitle></ruleset>"#
        #expect(
            try await console.check(draft, of: home) == .refused("subtitle.forcd is not a fact a rule can test"),
            "the silo's words"
        )
        #expect(!asked.withLock { $0 }.contains { $0.method == "PUT" }, "and nothing is stored")
    }

    @Test func aStoreNamesItsBaseAndAVersionThatLandedFirstKeepsTheDraft() async throws {
        let asked = Mutex<[Asked]>([])
        let (console, home) = try await Self.homeWithAccess(head: 3)
        var draft = Draft.change(try await console.open(ruleset: "household", of: home).document)
        draft.text = "<changed/>"

        // Version 4 lands from another Mac before this one stores.
        Self.answer(with: Self.changingSilo(head: 4) { request in asked.withLock { $0.append(request) } })
        #expect(try await console.impact(of: draft, of: home).isEmpty)
        struct ImpactBody: Decodable, Equatable {
            var basedOn: Int
            var document: String
        }
        let impactBody = try JSONDecoder().decode(
            ImpactBody.self,
            from: Data((asked.withLock { $0 }.last?.body ?? "").utf8)
        )
        #expect(
            impactBody == ImpactBody(basedOn: 3, document: "<changed/>"),
            "the impact of the draft against its base"
        )
        guard case .landedFirst(let landed) = try await console.store(draft, to: .baseBranch, of: home) else {
            Issue.record("a store based on 3 when the head is 4 lands nothing")
            return
        }
        #expect(landed.version == 4 && landed.document == "<v4/>", "version 4 is shown, to be read against 3")
        let put = try #require(asked.withLock { $0 }.first { $0.method == "PUT" })
        #expect(put.body.contains(#""basedOn":3"#), "the store named its base")

        let rebased = draft.rebased(on: landed)
        guard case .stored(let stored) = try await console.store(rebased, to: .baseBranch, of: home) else {
            Issue.record("re-based on 4, it is stored")
            return
        }
        #expect(stored.version == 5)
        #expect(LineDifference.changes(from: "<v3/>", to: landed.document).map(\.text) == ["<v3/>", "<v4/>"])
    }

    @Test func aDraftIsStoredOnANewBranchStartedFromItsBase() async throws {
        let asked = Mutex<[Asked]>([])
        let (console, home) = try await Self.homeWithAccess(head: 3)
        Self.answer(with: Self.changingSilo(head: 3) { request in asked.withLock { $0.append(request) } })
        var draft = Draft.change(try await console.open(ruleset: "household", of: home).document)
        draft.text = "<trial/>"
        guard case .stored = try await console.store(draft, to: .newBranch("speech"), of: home) else {
            Issue.record("stored")
            return
        }
        let sent = asked.withLock { $0 }.filter { $0.method != "GET" }
        #expect(
            sent.map { "\($0.method) \($0.path)" } == [
                "POST /v1/rulesets/household/branches", "PUT /v1/rulesets/household",
            ]
        )
        #expect(sent[0].body == #"{"from":3,"name":"speech"}"# || sent[0].body == #"{"name":"speech","from":3}"#)
        #expect(
            sent[1].body.contains(#""branch":"speech""#) && sent[1].body.contains(#""basedOn":3"#),
            "at the new branch's head, its base"
        )

        let fresh = Draft.starter(named: "household")
        _ = try await console.store(fresh, to: .baseBranch, of: home)
        #expect(
            asked.withLock { $0 }.last { $0.method == "PUT" }?.body.contains(#""basedOn":0"#) == true,
            "a new ruleset is based on zero"
        )
    }

    @Test func aRefusedPromotionNamesWhatTheBranchHasNotTakenIn() async throws {
        let (console, home) = try await Self.homeWithAccess(head: 9)
        #expect(try await console.impact(ofBranch: "trial", of: "household", on: home).isEmpty)
        do {
            _ = try await console.promote("trial", of: "household", on: home)
            Issue.record("the standard has moved on since the branch's base")
        } catch let refused as AdminConsole.PromotionRefused {
            #expect(
                refused.notTakenIn.map(\.version) == [3, 4, 5, 6, 7, 8, 9],
                "every standard version since the branch is up to date with 1"
            )
            #expect(refused.base?.version == 1, "read against the branch's base")
            #expect(refused.reason.contains("household@9"))
        }
        // A draft on the branch taking the standard's head in.
        var takingIn = Draft.change(try await console.open(ruleset: "household", version: 2, of: home).document)
        takingIn.upToDateWith = 9
        let asked = Mutex<[Asked]>([])
        Self.answer(with: Self.changingSilo(head: 9) { request in asked.withLock { $0.append(request) } })
        _ = try await console.store(takingIn, to: .baseBranch, of: home)
        let put = try #require(asked.withLock { $0 }.last)
        #expect(
            put.body.contains(#""branch":"trial""#) && put.body.contains(#""upToDateWith":9"#)
                && put.body.contains(#""basedOn":2"#)
        )
    }

    /// The console reads each library's availability and last walk, adds a library at a path within a
    /// root, and shows a removal's refusal naming the job; it has no way to start a walk.
    @Test func librariesAreAddedAndRemovedFromTheConsole() async throws {
        let asked = Mutex<[Asked]>([])
        let (console, home) = try await Self.homeWithAccess(head: 3)
        Self.answer(with: Self.changingSilo(head: 3) { request in asked.withLock { $0.append(request) } })
        #expect(try await console.libraries(of: home).map(\.available) == [false])
        let walks = try await console.lastWalks(of: home)
        #expect(walks["films"]?.available == false)
        #expect(walks["films"]?.walkedAt == ISO8601DateFormatter().date(from: "2026-10-19T09:30:00Z"))
        #expect(walks["films"]?.report.findings.map(\.text) == ["not applied: its folder does not exist"])

        #expect(AdminConsole.path("Shows/", within: "/srv/media") == "/srv/media/Shows")
        #expect(AdminConsole.path("", within: "/srv/media") == "/srv/media")
        let added = try await console.addLibrary(
            id: "shows",
            path: AdminConsole.path("Shows", within: "/srv/media"),
            on: home
        )
        #expect(added.id == "shows" && added.available)
        let sent = try JSONDecoder().decode(
            [String: String].self,
            from: Data(try #require(asked.withLock { $0 }.last).body.utf8)
        )
        #expect(sent == ["id": "shows", "path": "/srv/media/Shows"])
        do {
            _ = try await console.addLibrary(id: "escape", path: "/etc", on: home)
            Issue.record("a path outside the roots is refused")
        } catch let refused as AdminConsole.SettingsRefused {
            #expect(refused.reason == "/etc lies within none of the library roots: /srv/media")
        }

        try await console.removeLibrary("shows", on: home)
        do {
            try await console.removeLibrary("films", on: home)
            Issue.record("a library a live job files into is kept")
        } catch let refused as AdminConsole.SettingsRefused {
            #expect(refused.reason == "job j1 is encoding and files into films", "naming the job")
        }
        #expect(
            !asked.withLock { $0 }.contains { $0.method == "POST" && $0.path.hasSuffix("/scan") },
            "nothing asks for a walk"
        )
    }

    /// A silo whose `films` library holds one film, Alien, whose sidecar is `sidecar` until a store
    /// writes another; the last walk reports a warning on its sidecar and an error on another's. A
    /// store or dry run whose document removes the theatrical alternative is refused with its findings.
    /// The sidecar the stub silo holds, shared between the stub and the test.
    private final class HeldSidecar: Sendable {
        let bytes: Mutex<Data>
        init(_ bytes: Data) { self.bytes = Mutex(bytes) }
    }

    private static func containerSilo(
        sidecar: HeldSidecar,
        asked: @escaping @Sendable (Asked) -> Void
    ) -> @Sendable (URLRequest) throws -> (Int, Data)? {
        { request in
            guard let url = request.url else { return nil }
            let method = request.httpMethod ?? "GET"
            let body = Self.body(of: request) ?? Data()
            asked(Asked(method: method, path: url.path, body: String(decoding: body, as: UTF8.self)))
            let held = sidecar.bytes.withLock { $0 }
            let digest = String(held.count)
            let film = "0000000000000014"
            func result(applied: Bool, _ findings: String) -> Data {
                Data(
                    #"{"applied":\#(applied),"sidecar":"<container/>","digest":"\#(digest)-next","findings":[\#(findings)]}"#
                        .utf8
                )
            }
            switch (method, url.path) {
            case (_, "/v1/server"): return (200, Data(Self.serverInfo("home", "Home Silo", bootstrap: false).utf8))
            case (_, "/v1/operator"): return (200, Data(Self.active.utf8))
            case ("GET", "/v1/libraries/films/containers"):
                return (
                    200,
                    Data(
                        #"[{"id":"\#(film)","library":"films","type":"movie","title":"Alien","displayTitle":"Alien (1997)","listed":true}]"#
                            .utf8
                    )
                )
            case ("GET", "/v1/libraries/films/containers/\(film)"):
                let container =
                    #"{"id":"\#(film)","library":"films","type":"movie","title":"Alien","displayTitle":"Alien (1997)","year":1997,"listed":true,"alternatives":[],"features":[],"sequences":[{"id":"main","exploded":"never","items":[{"id":"feature","type":"movie","title":"Alien","optional":false,"externalRefs":[],"presentations":[{"id":"p1","alternative":"theatrical","displayName":"Theatrical","file":"Alien - Theatrical.mkv"}]}]}],"extras":[],"children":[],"externalRefs":[]}"#
                return (
                    200,
                    Data(
                        #"{"library":"films","path":"Alien (1997)/container.smd","digest":"\#(digest)","artwork":["poster"],"container":\#(container)}"#
                            .utf8
                    )
                )
            case ("GET", "/v1/libraries/films/containers/\(film)/smd"): return (200, held)
            case ("GET", "/v1/libraries/films/scan"):
                return (
                    200,
                    Data(
                        #"{"walkedAt":"2026-10-19T09:30:00Z","available":true,"report":{"read":1,"unchanged":0,"removed":0,"findings":[{"severity":"warning","path":"Alien (1997)/container.smd","text":"folder \"Alien (1997)\" is not the name the layout would give it, \"Alien (1979)\""},{"severity":"error","path":"Brief/container.smd","text":"unreadable"}]}}"#
                            .utf8
                    )
                )
            case ("PUT", "/v1/libraries/films/containers/\(film)"):
                struct Edit: Decodable {
                    var document: String
                    var basedOn: String
                    var dryRun: Bool?
                }
                let edit = try JSONDecoder().decode(Edit.self, from: body)
                guard edit.basedOn == digest else {
                    return (409, Data(#"{"detail":"the sidecar is now \#(digest), not \#(edit.basedOn)"}"#.utf8))
                }
                if !edit.document.contains("theatrical") {
                    return (
                        422,
                        result(
                            applied: false,
                            #"{"severity":"error","path":"Alien (1997)/container.smd","text":"item feature: presentation names alternative theatrical, which is not there"}"#
                        )
                    )
                }
                guard edit.dryRun != true else {
                    // A silo that moves folders says which; the rest of these answers come from one
                    // that says nothing of them.
                    let moved = #"{"from":"Alien (1997)","to":"Alien (1979)"}"#
                    var answer = String(decoding: result(applied: false, ""), as: UTF8.self)
                    answer.removeLast()
                    return (200, Data((answer + #","moves":[\#(moved)]}"#).utf8))
                }
                sidecar.bytes.withLock { $0 = Data(edit.document.utf8) + Data(" ".utf8) }
                return (200, result(applied: true, ""))
            case ("PUT", "/v1/libraries/films/containers/\(film)/artwork/poster"):
                return body.starts(with: [0xFF, 0xD8, 0xFF])
                    ? (200, Data(#"{"kind":"poster","format":"jpg"}"#.utf8)) : (415, Data())
            case ("DELETE", "/v1/libraries/films/containers/\(film)/artwork/poster"): return (204, Data())
            case ("DELETE", "/v1/libraries/films/containers/\(film)/artwork/logo"): return (404, Data())
            default: return (404, Data())
            }
        }
    }

    /// The console reads a library's containers and one container as its sidecar says it, with the
    /// last walk's findings on that sidecar alone; a draft of an edit is kept on this Mac, checked by a
    /// dry run, refused with the silo's findings, stored onto its base, and kept when another edit
    /// landed first; artwork is put and removed, and a refusal said in words.
    @Test func aLibrarysContainersAreBrowsedAndEditedFromTheConsole() async throws {
        var alien = Container(
            id: ContainerID("0000000000000014")!,
            type: .movie,
            title: Title("Alien")!,
            year: 1997,
            yearInTitle: true
        )
        alien.alternatives = [Alternative(id: "theatrical", sequence: "main", title: "Theatrical")]
        alien.sequences = [
            Sequence(id: "main", items: [.leaf(Entry.Leaf(id: ItemID("feature")!, type: .movie, title: "Alien"))])
        ]
        let sidecar = HeldSidecar(
            try SidecarFile.data(
                for: Sidecar(
                    container: alien,
                    presentations: [
                        "feature": [Presentation(alternative: "theatrical", file: "Alien - Theatrical.mkv")]
                    ]
                )
            )
        )
        let asked = Mutex<[Asked]>([])
        let passkeys = InMemoryPasskeyStore()
        passkeys.store("held", for: "home")
        let console = Self.console(
            passkeys: passkeys,
            discovered: [DiscoveredSilo(name: "Home Silo", host: "home.local", port: 8742)],
            answering: Self.containerSilo(sidecar: sidecar) { request in asked.withLock { $0.append(request) } }
        )
        let home = try #require(await console.refresh().first { $0.id == "home" })

        #expect(try await console.containers(in: "films", of: home).map(\.displayTitle) == ["Alien (1997)"])
        let opened = try await console.open(container: alien.id.value, in: "films", of: home)
        #expect(opened.container.artwork == ["poster"])
        #expect(
            opened.container.container.sequences.first?.items.first?.presentations.map(\.file) == [
                "Alien - Theatrical.mkv"
            ]
        )
        #expect(
            opened.findings.map(\.text) == [
                "folder \"Alien (1997)\" is not the name the layout would give it, \"Alien (1979)\""
            ],
            "the findings on its sidecar, and no other's"
        )

        var draft = try ContainerDraft.change(opened.container, sidecar: opened.sidecar)
        #expect(draft.value == alien, "the draft is the sidecar's container, without the library's facts")
        #expect(!draft.isChanged)
        var corrected = alien
        corrected.year = 1979
        draft.set(corrected)
        #expect(draft.difference.contains { $0.kind == .added && $0.text.contains("1979") })
        try console.containerDrafts.save(draft, for: home.id)
        #expect(
            console.containerDrafts.draft(of: alien.id.value, in: "films", of: home.id)?.value?.year == 1979,
            "kept on this Mac"
        )

        guard case .wouldWrite(let dry) = try await console.check(draft, of: home) else {
            Issue.record("a draft that applies is checked")
            return
        }
        #expect(!dry.applied)
        #expect(
            dry.moves == [SiloClient.FolderMove(from: "Alien (1997)", to: "Alien (1979)")],
            "the folder it would move"
        )
        #expect(sidecar.bytes.withLock { $0 } == opened.sidecar, "a check writes nothing")

        var refused = draft
        var noTheatrical = corrected
        noTheatrical.alternatives = []
        refused.set(noTheatrical)
        guard case .refused(let refusal) = try await console.check(refused, of: home) else {
            Issue.record("the silo's findings refuse it")
            return
        }
        #expect(
            refusal.findings.map(\.text) == [
                "item feature: presentation names alternative theatrical, which is not there"
            ]
        )
        guard case .refused = try await console.store(refused, of: home) else {
            Issue.record("a store is refused alike")
            return
        }

        guard case .stored(let stored) = try await console.store(draft, of: home) else {
            Issue.record("a store onto its base is written")
            return
        }
        #expect(stored.applied)
        let put = try #require(asked.withLock { $0 }.last { $0.method == "PUT" })
        #expect(put.body.contains(#""basedOn":"\#(draft.base)""#), "naming its base")

        // The sidecar has moved on from the draft's base: the dry run says so, and a store hands back
        // what landed, for the draft to be re-based on it.
        #expect(
            try await console.check(draft, of: home)
                == .behind("the sidecar is now \(sidecar.bytes.withLock { $0 }.count), not \(draft.base)")
        )
        guard case .landedFirst(let landed) = try await console.store(draft, of: home) else {
            Issue.record("an edit that landed first is handed back")
            return
        }
        #expect(landed.container.digest != draft.base)
        let rebased = try draft.rebased(on: landed.container, sidecar: landed.sidecar)
        #expect(rebased.base == landed.container.digest && rebased.text == draft.text)
        #expect(!rebased.isBehind(landed.container.digest))

        try await console.putArtwork(
            Data([0xFF, 0xD8, 0xFF, 0xE0]),
            as: "poster",
            of: alien.id.value,
            in: "films",
            on: home
        )
        do {
            try await console.putArtwork(Data("text".utf8), as: "poster", of: alien.id.value, in: "films", on: home)
            Issue.record("a file that is not an image is refused")
        } catch let refused as AdminConsole.SettingsRefused {
            #expect(refused.reason == "the silo takes artwork as a JPEG or a PNG, and this is neither")
        }
        try await console.removeArtwork("poster", of: alien.id.value, in: "films", on: home)
        await #expect(throws: AdminConsole.SettingsRefused(reason: "the container has no logo")) {
            try await console.removeArtwork("logo", of: alien.id.value, in: "films", on: home)
        }
        #expect(
            console.artworkURL("poster", of: alien.id.value, in: "films", of: home).path
                == "/v1/libraries/films/containers/0000000000000014/artwork/poster"
        )

        await console.forget(home)
        #expect(console.containerDrafts.drafts(of: home.id).isEmpty, "forgetting a silo ends its container drafts")
    }

    /// The console asks what an addition would find before it is made — each folder along the path
    /// and the refusal it would meet — and asks for the missing folders to be made only when told to.
    @Test func aLibrarysPathIsCheckedAndItsFoldersMadeFromTheConsole() async throws {
        let asked = Mutex<[Asked]>([])
        let (console, home) = try await Self.homeWithAccess(head: 3)
        Self.answer(with: Self.changingSilo(head: 3) { request in asked.withLock { $0.append(request) } })
        let check = try await console.checkLibrary(id: "shows", path: "/srv/media/Shows/New", create: false, on: home)
        #expect(check.components.map(\.state) == [.folder, .folder, .missing, .missing])
        #expect(check.root == "/srv/media")
        #expect(check.creates == ["/srv/media/Shows", "/srv/media/Shows/New"])
        #expect(
            check.present == "/srv/media" && check.absent == "/Shows/New",
            "the path split where it stops being there, for the sheet to colour"
        )
        let blocked = try SiloClient.decoder.decode(
            SiloClient.LibraryCheck.self,
            from: Data(
                #"{"path":"/srv/media/notes.txt/Films","components":[{"path":"/srv","state":"folder"},{"path":"/srv/media","state":"folder"},{"path":"/srv/media/notes.txt","state":"notAFolder"}],"creates":[],"refusal":{"status":422,"detail":"/srv/media/notes.txt is not a folder"}}"#
                    .utf8
            )
        )
        #expect(
            blocked.present == "/srv/media" && blocked.absent == "/notes.txt/Films",
            "a file in the way is apart with what lies past it"
        )
        #expect(blocked.refusesPath(create: true), "a file in the way refuses the path whatever is asked")
        #expect(check.refusal?.status == 422)
        #expect(check.refusal?.detail == "/srv/media/Shows/New is not a folder that exists")
        #expect(check.refusesPath(create: false), "missing folders not asked for refuse the path")
        let named = try SiloClient.decoder.decode(
            SiloClient.LibraryCheck.self,
            from: Data(
                #"{"path":"/srv/media/Shows","components":[{"path":"/srv","state":"folder"},{"path":"/srv/media","state":"folder"},{"path":"/srv/media/Shows","state":"missing"}],"root":"/srv/media","creates":["/srv/media/Shows"],"refusal":{"status":409,"detail":"there is already a library shows"}}"#
                    .utf8
            )
        )
        #expect(!named.refusesPath(create: true), "a name already taken leaves the path good")
        let mounted = try SiloClient.decoder.decode(
            SiloClient.LibraryCheck.self,
            from: Data(
                #"{"path":"/Volumes/Media","components":[{"path":"/Volumes","state":"folder"},{"path":"/Volumes/Media","state":"missing"}],"creates":["/Volumes/Media"],"refusal":{"status":403,"detail":"it would be created where drives are mounted"}}"#
                    .utf8
            )
        )
        #expect(mounted.refusesPath(create: true), "a drive's mount point refuses the path even when asked to make it")
        #expect(mounted.refusesPath(create: false), "and when not")
        let checked = try JSONDecoder().decode(
            [String: String].self,
            from: Data(try #require(asked.withLock { $0 }.last).body.utf8)
        )
        #expect(checked == ["id": "shows", "path": "/srv/media/Shows/New"], "create is sent only when asked for")
        #expect(
            try await console.checkLibrary(id: "shows", path: "/srv/media/Shows/New", create: true, on: home).refusal
                == nil
        )

        _ = try await console.addLibrary(id: "shows", path: "/srv/media/Shows/New", create: true, on: home)
        let sent =
            try JSONSerialization.jsonObject(with: Data(try #require(asked.withLock { $0 }.last).body.utf8))
            as? [String: Any]
        #expect(sent?["create"] as? Bool == true)
        #expect(
            asked.withLock { $0 }.filter { $0.method == "POST" && $0.path == "/v1/libraries" }.count == 1,
            "a check adds nothing"
        )
    }

    @Test func aLibrarysStandardIsNamedFromTheConsole() async throws {
        let asked = Mutex<[Asked]>([])
        let (console, home) = try await Self.homeWithAccess(head: 3)
        Self.answer(with: Self.changingSilo(head: 3) { request in asked.withLock { $0.append(request) } })
        #expect(try await console.libraries(of: home).map(\.ruleset) == [nil])
        let library = try await console.setStandard("household", of: "films", on: home)
        #expect(library.ruleset == "household", "the standard the silo answered with")
        #expect(asked.withLock { $0 }.last?.body == #"{"ruleset":"household"}"#)
        await #expect(throws: AdminConsole.SettingsRefused.self) {
            try await console.setStandard("nothing", of: "films", on: home)
        }
    }

    /// A library whose folders were renamed by hand is laid out from the console: the dry run's moves
    /// are listed before anything moves, the layout applies them, and the library's walk then warns of
    /// none of them; a library the silo cannot reach is refused in words.
    @Test func aLibraryIsLaidOutFromTheConsole() async throws {
        let asked = Mutex<[Asked]>([])
        let laid = Mutex(false)
        let (console, home) = try await Self.homeWithAccess(head: 3)
        let base = Self.changingSilo(head: 3) { _ in }
        let move = #"{"from":"Doctor Who (1963)/Season 13","to":"Doctor Who (1963)/01 - Season 13"}"#
        let warning =
            #"{"severity":"warning","path":"Doctor Who (1963)/Season 13/container.smd","text":"folder \"Season 13\" is not the name the layout would give it, \"01 - Season 13\""}"#
        Self.answer { request in
            guard let url = request.url else { return nil }
            let method = request.httpMethod ?? "GET"
            let body = String(decoding: Self.body(of: request) ?? Data(), as: UTF8.self)
            switch (method, url.path) {
            case ("POST", "/v1/libraries/films/layout"):
                asked.withLock { $0.append(Asked(method: method, path: url.path, body: body)) }
                let dryRun = body.contains(#""dryRun":true"#)
                if !dryRun { laid.withLock { $0 = true } }
                return (200, Data(#"{"applied":\#(!dryRun),"moves":[\#(move)],"findings":[]}"#.utf8))
            case ("POST", "/v1/libraries/shows/layout"): return (503, Data())
            case ("GET", "/v1/libraries/films/scan"):
                let findings = laid.withLock { $0 } ? "" : warning
                return (
                    200,
                    Data(
                        #"{"walkedAt":"2026-10-21T09:30:00Z","available":true,"report":{"read":2,"unchanged":0,"removed":0,"findings":[\#(findings)]}}"#
                            .utf8
                    )
                )
            default: return try base(request)
            }
        }
        #expect(try await console.lastWalks(of: home)["films"]?.report.findings.count == 1)

        let planned = try await console.layOut("films", on: home, dryRun: true)
        #expect(!planned.applied)
        #expect(
            planned.moves == [
                SiloClient.FolderMove(from: "Doctor Who (1963)/Season 13", to: "Doctor Who (1963)/01 - Season 13")
            ]
        )
        #expect(!laid.withLock { $0 }, "nothing moves before the operator confirms")

        let applied = try await console.layOut("films", on: home, dryRun: false)
        #expect(applied.applied)
        #expect(applied.moves == planned.moves)
        #expect(asked.withLock { $0 }.map(\.body) == [#"{"dryRun":true}"#, "{}"])
        #expect(try await console.lastWalks(of: home)["films"]?.report.findings.isEmpty == true)

        await #expect(throws: AdminConsole.SettingsRefused.self) {
            try await console.layOut("shows", on: home, dryRun: true)
        }
    }

    // MARK: - Trials

    /// A recipe for binding `b1`'s commentary, its second audio stream, at the bitrate given.
    private static func commentaryRecipe(
        _ id: String,
        binding: String = "b1",
        version: Int,
        bitrate: String
    ) -> StoredRecipe {
        let facts = SourceFacts(audio: [
            AudioFacts(index: 1, absoluteIndex: 1, codec: "flac", lossless: true, channels: 2),
            AudioFacts(index: 2, absoluteIndex: 2, codec: "flac", lossless: true, channels: 2),
        ])
        let main = StreamDecision(
            kind: .audio,
            sourceIndex: 1,
            sourceAbsoluteIndex: 1,
            rule: "lossless-main",
            action: .copy
        )
        let commentary = StreamDecision(
            kind: .audio,
            sourceIndex: 2,
            sourceAbsoluteIndex: 2,
            rule: "commentary",
            action: .encode(EncodeSettings(codec: "aac", bitrate: bitrate, channels: 2))
        )
        let recipe = Recipe(
            ruleset: RulesetRef(name: "household", version: version),
            decisions: [main, commentary],
            output: OutputPolicy(),
            layout: OutputLayout(keeping: [main, commentary])
        )
        return StoredRecipe(id: id, binding: binding, facts: facts, recipe: recipe)
    }

    /// A silo with access whose branch `speech-96k`, at version 4, would change binding `b1`'s placed
    /// presentation; binding `b2` cannot be resolved through it, and trial jobs are made as asked.
    private static func tryingSilo(
        asked: @escaping @Sendable (Asked) -> Void
    ) -> @Sendable (URLRequest) throws -> (Int, Data)? {
        { request in
            guard let url = request.url else { return nil }
            let method = request.httpMethod ?? "GET"
            let body = String(decoding: Self.body(of: request) ?? Data(), as: UTF8.self)
            asked(Asked(method: method, path: url.path + (url.query.map { "?\($0)" } ?? ""), body: body))
            let placed = Self.commentaryRecipe("placed-1", version: 3, bitrate: "160k")
            let tried = Self.commentaryRecipe("tried-1", version: 4, bitrate: "96k")
            switch (method, url.path) {
            case (_, "/v1/server"): return (200, Data(Self.serverInfo("home", "Home Silo", bootstrap: false).utf8))
            case (_, "/v1/operator"): return (200, Data(Self.active.utf8))
            case ("GET", "/v1/rulesets/household/branches/speech-96k/impact"):
                return (
                    200,
                    Data(
                        #"[{"presentation":"p1","container":"Pyramids of Mars","item":"Part Three","recipe":"placed-1","outcome":"outOfDate","madeBy":{"ruleset":{"name":"household","version":3},"layers":[]},"checkedAgainst":{"ruleset":{"name":"household","version":4},"layers":[]},"changes":[],"sources":[]}]"#
                            .utf8
                    )
                )
            case ("GET", "/v1/recipes/placed-1"): return (200, try SiloClient.encoder.encode(placed))
            case ("GET", "/v1/recipes/tried-1"): return (200, try SiloClient.encoder.encode(tried))
            case ("POST", "/v1/bindings/b1/recipes"): return (201, try SiloClient.encoder.encode([tried]))
            case ("POST", "/v1/bindings/b2/recipes"):
                return (422, Data(#"{"detail":"no rule decides audio 3 (ac3 2ch en main)"}"#.utf8))
            case ("POST", "/v1/jobs"):
                var job = Job(id: "job-1", recipe: "tried-1", requirements: ["aac"], trial: true)
                job.state = .pending
                return (201, try SiloClient.encoder.encode(job))
            case ("GET", "/v1/trials"):
                return (
                    200,
                    Data(
                        #"[{"job":"job-1","recipe":"tried-1","ruleset":"household","version":4,"branch":"speech-96k","binding":"b1","createdAt":"2026-10-14T10:00:00Z"}]"#
                            .utf8
                    )
                )
            default: return nil
            }
        }
    }

    @Test func aBranchsVersionIsTriedOnChosenBindingsAndComparedWithWhatIsPlaced() async throws {
        let asked = Mutex<[Asked]>([])
        let (console, home) = try await Self.homeWithAccess(head: 3)
        Self.answer(with: Self.tryingSilo { request in asked.withLock { $0.append(request) } })

        let candidates = try await console.trialCandidates(of: "household", branch: "speech-96k", on: home)
        #expect(
            candidates.map(\.binding) == ["b1"],
            "the binding whose placed presentation the branch would change, offered first"
        )
        #expect(candidates.first?.item == "Part Three")

        let started = try await console.startTrials(
            of: "household",
            branch: "speech-96k",
            version: 4,
            on: ["b1", "b2"],
            of: home
        )
        #expect(started.first?.jobs.map(\.id) == ["job-1"] && started.first?.jobs.first?.trial == true)
        #expect(
            started.last?.refusal == "no rule decides audio 3 (ac3 2ch en main)",
            "a binding the version cannot resolve is told in the silo's words"
        )
        let requests = asked.withLock { $0 }
        #expect(
            requests.contains {
                $0.path == "/v1/bindings/b1/recipes" && $0.body.contains(#""branch":"speech-96k""#)
                    && $0.body.contains(#""version":4"#)
            },
            "applied at the version, on its branch"
        )
        #expect(requests.contains { $0.path == "/v1/jobs" && $0.body.contains(#""trial":true"#) }, "a trial job")
        #expect(!requests.contains { $0.path.hasSuffix("/place") }, "nothing placed")

        let compared = try #require(try await console.trials(of: "household", branch: "speech-96k", on: home).first)
        #expect(compared.trial.job == "job-1")
        #expect(compared.streams.map(\.stream) == ["audio 1", "audio 2"])
        #expect(
            compared.streams.last?.placed?.summary == "encode aac 160k 2ch"
                && compared.streams.last?.tried?.summary == "encode aac 96k 2ch",
            "the commentary at 96k where it was 160k"
        )
        #expect(compared.streams.first?.placed == compared.streams.first?.tried, "the main mix as it was")
        #expect(compared.trialFile.absoluteString.hasSuffix("/v1/trials/job-1/file"))
        #expect(compared.placedFile?.absoluteString.hasSuffix("/v1/media/p1") == true, "both files to play")
    }

    // MARK: - Forget

    @Test func forgetPurgesTheRegistryAndThePasskey() async throws {
        let registry = SiloRegistry()
        try registry.merge(
            RegisteredSilo(
                id: "quiet",
                name: "Quiet Silo",
                url: URL(string: "http://quiet.local:8080")!,
                lastSeen: Self.clock,
                hasStoredPasskey: true,
                lastKnownAccess: true
            )
        )
        let store = InMemoryPasskeyStore()
        store.store("old-key", for: "quiet")
        let drafts = DraftStore()
        try drafts.save(Draft.starter(named: "one"), for: "quiet")
        try drafts.save(Draft.starter(named: "two"), for: "quiet")
        try drafts.save(Draft.starter(named: "elsewhere"), for: "other")
        let console = Self.console(registry: registry, drafts: drafts, passkeys: store) { _ in nil }

        _ = await console.refresh()
        let quiet = try row("quiet", in: await console.refresh())
        #expect(quiet.classification == .unreachable, "gone quiet — twice — is the moment to forget")

        await console.forget(quiet)

        #expect(store.passkey(for: "quiet") == nil, "this Mac no longer holds the passkey")
        #expect(registry.entry(for: "quiet") == nil, "the registry keeps nothing of it")
        #expect(await console.silos.isEmpty, "the row leaves the rendered list")
        #expect(drafts.drafts(of: "quiet").isEmpty, "and its drafts are deleted")
        #expect(drafts.drafts(of: "other").count == 1, "another silo's are not")
    }

    @Test func aRediscoveryRestartsHistory() async throws {
        let registry = SiloRegistry()
        try registry.merge(
            RegisteredSilo(
                id: "quiet",
                name: "Quiet Silo",
                url: URL(string: "http://quiet.local:8080")!,
                lastSeen: Self.clock,
                hasStoredPasskey: true,
                lastKnownAccess: true
            )
        )
        let store = InMemoryPasskeyStore()
        store.store("old-key", for: "quiet")
        let console = Self.console(registry: registry, passkeys: store) { _ in nil }

        await console.forget(try row("quiet", in: await console.refresh()))
        #expect(registry.entry(for: "quiet") == nil, "forgotten before it answers again")

        Self.answer { request in
            guard let url = request.url, url.host == "quiet.local", url.path == "/v1/server" else { return nil }
            return (200, Data(Self.serverInfo("quiet", "Quiet Silo", bootstrap: false).utf8))
        }
        let found = try row("quiet", in: await console.refresh(typedURLs: [URL(string: "http://quiet.local:8080")!]))
        #expect(found.classification == .withoutAccess, "a forgotten silo arrives as never met")
        #expect(found.lastKnownAccess == nil)
        let merged = try #require(registry.entry(for: "quiet"))
        #expect(!merged.hasStoredPasskey)
        #expect(merged.lastKnownAccess == nil, "a rediscovery restarts history")
    }
}

// MARK: - smddb

extension AdminConsoleTests {
    /// The sidecars a fake library holds, by container id, as a silo would keep them.
    private final class HeldLibrary: Sendable {
        let sidecars: Mutex<[String: Data]>
        init(_ containers: [Container] = []) {
            sidecars = Mutex(
                Dictionary(
                    uniqueKeysWithValues: containers.map {
                        ($0.id.value, try! SidecarFile.data(for: Sidecar(container: $0)))
                    }
                )
            )
        }
        func container(_ id: ContainerID) -> Container? {
            sidecars.withLock { $0[id.value] }.flatMap { try? SidecarFile.sidecar(from: $0).container }
        }
    }

    private static func digest(_ data: Data) -> String {
        "\(data.count)-\(data.reduce(0) { $0 &* 31 &+ Int($1) })"
    }

    /// A silo with access whose library `tv` holds `held`'s sidecars and nothing else: it answers each
    /// one's library route and bytes, edits them onto their digest, and makes containers beneath one it
    /// holds, refusing one held already and a parent that does not name the top, as the silo would. A
    /// container titled `Refused` stands for one the silo's validator refuses, made or edited.
    private static func smddbSilo(_ held: HeldLibrary) -> @Sendable (URLRequest) throws -> (Int, Data)? {
        { request in
            guard let url = request.url else { return nil }
            let method = request.httpMethod ?? "GET"
            let body = Self.body(of: request) ?? Data()
            let prefix = "/v1/libraries/tv/containers"
            func finding(_ text: String) -> String { #"{"severity":"error","text":"\#(text)"}"# }
            switch (method, url.path) {
            case (_, "/v1/server"): return (200, Data(Self.serverInfo("home", "Home Silo", bootstrap: false).utf8))
            case (_, "/v1/operator"): return (200, Data(Self.active.utf8))
            case ("POST", prefix):
                struct Create: Decodable {
                    var documents: [String]
                    var parent: String?
                    var dryRun: Bool?
                }
                let create = try JSONDecoder().decode(Create.self, from: body)
                let containers = try create.documents.map { try ContainerFile.container(from: Data($0.utf8)) }
                let named = Set(containers.flatMap(\.childContainerIDs))
                guard let top = containers.first(where: { !named.contains($0.id) }) else { return (400, Data()) }
                var findings: [String] = []
                if let parent = create.parent {
                    guard let holder = held.container(ContainerID(parent)!) else { return (404, Data()) }
                    if !holder.childContainerIDs.contains(top.id) {
                        findings.append(finding("\(parent) does not name \(top.id) as a child"))
                    }
                }
                for container in containers where held.container(container.id) != nil {
                    findings.append(finding("container \(container.id) is already at \\\"\(container.id)\\\""))
                }
                for container in containers where container.title.rawValue == "Refused" {
                    findings.append(finding("\(container.id): the validator refuses it"))
                }
                let writes = containers.map { #"{"path":"\#($0.id)/container.smd","creates":true}"# }
                func result(_ applied: Bool) -> Data {
                    Data(
                        #"{"applied":\#(applied),"writes":[\#(writes.joined(separator: ","))],"findings":[\#(findings.joined(separator: ","))]}"#
                            .utf8
                    )
                }
                guard findings.isEmpty else { return (422, result(false)) }
                guard create.dryRun != true else { return (200, result(false)) }
                held.sidecars.withLock { sidecars in
                    for container in containers {
                        sidecars[container.id.value] = try! SidecarFile.data(for: Sidecar(container: container))
                    }
                }
                return (200, result(true))
            case (let method, let path) where path.hasPrefix(prefix + "/"):
                let rest = path.dropFirst(prefix.count + 1).split(separator: "/").map(String.init)
                guard let bytes = held.sidecars.withLock({ $0[rest[0]] }),
                    let container = try? SidecarFile.sidecar(from: bytes).container
                else { return (404, Data()) }
                let digest = Self.digest(bytes)
                if rest.count == 2, rest[1] == "smd" { return (200, bytes) }
                if method == "PUT" {
                    struct Edit: Decodable {
                        var document: String
                        var basedOn: String
                        var dryRun: Bool?
                    }
                    let edit = try JSONDecoder().decode(Edit.self, from: body)
                    guard edit.basedOn == digest else { return (409, Data(#"{"detail":"moved"}"#.utf8)) }
                    let value = try ContainerFile.container(from: Data(edit.document.utf8))
                    if value.title.rawValue == "Refused" {
                        return (
                            422,
                            Data(
                                #"{"applied":false,"sidecar":"","digest":"","findings":[\#(finding("the validator refuses it"))]}"#
                                    .utf8
                            )
                        )
                    }
                    let written = try SidecarFile.data(settingContainer: value, in: bytes)
                    if edit.dryRun != true { held.sidecars.withLock { $0[rest[0]] = written } }
                    return (
                        200,
                        Data(
                            #"{"applied":\#(edit.dryRun != true),"sidecar":"","digest":"\#(Self.digest(written))","findings":[]}"#
                                .utf8
                        )
                    )
                }
                let json =
                    #"{"id":"\#(container.id)","library":"tv","type":"series","title":"\#(container.title.rawValue)","displayTitle":"\#(container.displayTitle)","listed":true,"alternatives":[],"features":[],"sequences":[],"extras":[],"children":[],"externalRefs":[]}"#
                return (
                    200,
                    Data(
                        #"{"library":"tv","path":"\#(container.id)/container.smd","digest":"\#(digest)","artwork":[],"container":\#(json)}"#
                            .utf8
                    )
                )
            default: return (404, Data())
            }
        }
    }

    private static func clone() -> (LocalRepository, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("smddb-clone-\(UUID().uuidString)")
        return (LocalRepository(root: folder), folder)
    }

    private static func smddbConsole(_ held: HeldLibrary) async throws -> (AdminConsole, AdminConsole.Silo) {
        let passkeys = InMemoryPasskeyStore()
        passkeys.store("held", for: "home")
        let console = Self.console(
            passkeys: passkeys,
            discovered: [DiscoveredSilo(name: "Home Silo", host: "home.local", port: 8742)],
            answering: Self.smddbSilo(held)
        )
        let home = try #require(await console.refresh().first { $0.id == "home" })
        return (console, home)
    }

    /// A season, a serial of it, and a series naming the season, as smddb and a library each say them.
    private static let ark = Container(
        id: ContainerID("0000000000000063")!,
        type: .serial,
        title: Title("The Ark in Space")!
    )
    private static let season12: Container = {
        var season = Container(id: ContainerID("0000000000000062")!, type: .season, title: Title("Season 12")!)
        season.sequences = [
            Sequence(id: "stories", items: [.child(Entry.Child(id: ItemID("ark")!, container: ark.id))])
        ]
        return season
    }()
    private static let season13 = Container(
        id: ContainerID("0000000000000064")!,
        type: .season,
        title: Title("Season 13")!
    )
    private static func series(naming seasons: [Container]) -> Container {
        var series = Container(
            id: ContainerID("0000000000000061")!,
            type: .series,
            title: Title("Doctor Who")!,
            externalRefs: [ExternalRef(provider: .tvdb, value: "76107")]
        )
        series.sequences = [
            Sequence(
                id: "seasons",
                items: seasons.map {
                    .child(Entry.Child(id: ItemID(Slug.make(from: $0.title.rawValue))!, container: $0.id))
                }
            )
        ]
        return series
    }

    /// Each container of a library says whether its own fields are smddb's, differ from them, or are in
    /// no record of smddb's; the clone is searched by title and by a provider's id.
    @Test func aLibrarysContainersStandAgainstSmddb() async throws {
        let (database, folder) = Self.clone()
        defer { try? FileManager.default.removeItem(at: folder) }
        var alien = Container(type: .movie, title: Title("Alien")!, year: 1979, yearInTitle: true)
        try await database.save(alien)
        let matching = try SidecarFile.data(for: Sidecar(container: alien))
        #expect(try await AdminConsole.standing(of: matching, in: database) == .matches)

        var corrected = alien
        corrected.year = 1997
        let differing = try SidecarFile.data(for: Sidecar(container: corrected))
        #expect(try await AdminConsole.standing(of: differing, in: database) == .differs(alien))
        let unknown = try SidecarFile.data(for: Sidecar(container: Self.ark))
        #expect(try await AdminConsole.standing(of: unknown, in: database) == .absent)

        alien.externalRefs = [ExternalRef(provider: .tmdb, value: "348")]
        try await database.save(alien)
        try await database.save(Self.series(naming: []))
        #expect(try await AdminConsole.search("alien", in: database).map(\.id) == [alien.id])
        #expect(try await AdminConsole.search("348", in: database).map(\.id) == [alien.id])
        #expect(try await AdminConsole.search("tvdb:76107", in: database).map(\.title.rawValue) == ["Doctor Who"])
        #expect(Set(try await AdminConsole.search("", in: database).map(\.id)).count == 2, "every root")
    }

    /// An import goes beneath the nearest of smddb's ancestors the library holds, with the descendants
    /// chosen; a parent whose sidecar is older than smddb's record is offered as an edit draft from
    /// smddb first; and a container the library holds is offered as an edit, never imported.
    @Test func aContainerIsImportedFromSmddbBeneathTheNearestHeldAncestor() async throws {
        let (database, folder) = Self.clone()
        defer { try? FileManager.default.removeItem(at: folder) }
        let series = Self.series(naming: [Self.season12, Self.season13])
        for container in [series, Self.season12, Self.ark, Self.season13] { try await database.save(container) }
        // The library's series was filed before smddb's gained Season 12.
        let held = HeldLibrary([Self.series(naming: [Self.season13]), Self.season13])
        let (console, home) = try await Self.smddbConsole(held)

        guard
            case .plan(let plan) = try await console.planImport(Self.season12.id, into: "tv", of: home, from: database)
        else {
            Issue.record("Season 12 is not held, and is planned")
            return
        }
        #expect(plan.parent == series.id)
        #expect(plan.ancestors.isEmpty)
        #expect(plan.descendants.map(\.id) == [Self.ark.id])
        #expect(plan.documents(choosing: []).count == 1, "the season alone, its serial not chosen")
        #expect(plan.children(of: Self.season12.id).map(\.id) == [Self.ark.id], "the tree the sheet shows")
        #expect(plan.subtree(of: Self.season12.id) == [Self.ark.id])
        #expect(plan.children(of: Self.ark.id).isEmpty && plan.heldChildren(of: Self.season12.id).isEmpty)

        guard
            case .refused(let refused, let parentDraft?) = try await console.importContainers(
                plan,
                choosing: [Self.ark.id],
                dryRun: true,
                of: home,
                from: database
            )
        else {
            Issue.record("the dry run is refused, with the series offered from smddb")
            return
        }
        #expect(refused.findings.map(\.text) == ["\(series.id) does not name \(Self.season12.id) as a child"])
        #expect(parentDraft.value == series, "the draft's document is smddb's record")
        guard case .stored = try await console.store(parentDraft, of: home) else {
            Issue.record("the series' edit is stored")
            return
        }

        let made = try await console.importContainers(
            plan,
            choosing: [Self.ark.id],
            dryRun: false,
            of: home,
            from: database
        )
        guard case .made(let result) = made else {
            Issue.record("the import is made once the series names the season")
            return
        }
        #expect(result.writes.count == 2)
        #expect(held.container(Self.ark.id) == Self.ark)

        // A container the library holds is an edit from smddb's record, based on its sidecar.
        guard
            case .held(let draft) = try await console.planImport(Self.season13.id, into: "tv", of: home, from: database)
        else {
            Issue.record("Season 13 is held")
            return
        }
        #expect(draft.container == Self.season13.id.value)
        #expect(!draft.isNew)

        // Into a library holding none of the lineage, the ancestors are made too. The fake silo is the
        // file's one stub, so this console's library answers from here on.
        let empty = HeldLibrary()
        let (other, otherHome) = try await Self.smddbConsole(empty)
        guard case .plan(let whole) = try await other.planImport(Self.ark.id, into: "tv", of: otherHome, from: database)
        else {
            Issue.record("a serial nothing holds is planned")
            return
        }
        #expect(whole.parent == nil)
        #expect(whole.ancestors.map(\.id) == [series.id, Self.season12.id])

        // A library holding one season of the series: the plan's tree shows it beneath the series,
        // held, beside the season it can make, and an all-or-none choice covers that season's serial.
        let (partial, partialHome) = try await Self.smddbConsole(HeldLibrary([Self.season13]))
        guard
            case .plan(let tree) = try await partial.planImport(series.id, into: "tv", of: partialHome, from: database)
        else {
            Issue.record("the series is planned")
            return
        }
        #expect(tree.children(of: series.id).map(\.id) == [Self.season12.id])
        #expect(tree.heldChildren(of: series.id).map(\.id) == [Self.season13.id])
        #expect(tree.subtree(of: series.id) == [Self.season12.id, Self.ark.id])
    }

    /// A new container takes its id from smddb's client, is a draft on this Mac until it is made, and is
    /// made at the top of a library or, after an edit of its parent names it, beneath that parent.
    @Test func aContainerIsCreatedWithAProvisionalID() async throws {
        let (database, folder) = Self.clone()
        defer { try? FileManager.default.removeItem(at: folder) }
        try await database.save(Self.ark)
        let held = HeldLibrary([Self.series(naming: [Self.season13]), Self.season13])
        let (console, home) = try await Self.smddbConsole(held)

        let film = try await console.newContainer(
            .movie,
            titled: Title("The Five Doctors")!,
            in: "tv",
            at: ContainerDraft.Creating(),
            of: home,
            from: database
        )
        let id = try #require(ContainerID(film.container))
        #expect(try await database.container(id) == nil, "an id the clone has no file for")
        #expect(console.containerDrafts.draft(of: film.container, in: "tv", of: home.id) != nil, "kept on this Mac")
        #expect(film.isNew && film.isChanged && !film.isBehind("anything"))
        guard case .wouldWrite = try await console.check(new: film, of: home) else {
            Issue.record("the silo's dry run would make it")
            return
        }
        guard case .created = try await console.create(film, of: home) else {
            Issue.record("the film is made")
            return
        }
        #expect(held.container(id)?.title == Title("The Five Doctors")!)
        #expect(console.containerDrafts.draft(of: film.container, in: "tv", of: home.id) == nil, "made, the draft ends")

        let seasonDraft = try await console.newContainer(
            .season,
            titled: Title("Season 14")!,
            in: "tv",
            at: ContainerDraft.Creating(parent: Self.series(naming: []).id.value, sequence: "seasons", position: 1),
            of: home,
            from: database
        )
        guard case .wouldWrite = try await console.check(new: seasonDraft, of: home) else {
            Issue.record("the parent's edit would be written")
            return
        }
        guard case .created = try await console.create(seasonDraft, of: home) else {
            Issue.record("the season is made beneath the series")
            return
        }
        let seasonID = try #require(ContainerID(seasonDraft.container))
        #expect(held.container(Self.series(naming: []).id)?.childContainerIDs == [Self.season13.id, seasonID])
        #expect(held.container(seasonID) != nil)
    }

    /// A library's container is offered to smddb as its sidecar's own fields, with the difference from
    /// smddb's record shown first and the containers it names that smddb lacks offered with it.
    @Test func aLibrarysContainerIsProposedToSmddb() async throws {
        let (database, folder) = Self.clone()
        defer { try? FileManager.default.removeItem(at: folder) }
        var alien = Container(id: ContainerID("0000000000000071")!, type: .movie, title: Title("Alien")!, year: 1997)
        alien.sequences = [Sequence(id: "main", items: [.leaf(Entry.Leaf(id: ItemID("feature")!, type: .movie))])]
        try await database.save(alien)
        var corrected = alien
        corrected.year = 1979
        var nowhere = Self.series(naming: [Self.season13])
        nowhere.extras = [.ref(EntryRef(container: ContainerID("00000000000000ee")!, item: ItemID("elsewhere")!))]
        let held = HeldLibrary([Self.season13, nowhere])
        held.sidecars.withLock {
            $0[corrected.id.value] = try! SidecarFile.data(
                for: Sidecar(container: corrected, presentations: ["feature": [Presentation(file: "Alien.mkv")]])
            )
        }
        let (console, home) = try await Self.smddbConsole(held)

        let correction = try await console.planExport(corrected.id.value, in: "tv", of: home, to: database)
        #expect(correction.record == alien)
        #expect(correction.difference.filter { $0.kind != .same }.allSatisfy { $0.text.contains("year") })
        #expect(correction.offered.isEmpty && correction.unavailable.isEmpty)
        let written = try await console.export(correction, choosing: [], to: database)
        let file = try #require(try database.url(of: corrected.id))
        #expect(written == .written([file]))
        #expect(file.deletingLastPathComponent().lastPathComponent == "Alien [\(corrected.id)]", "in the clone's tree")
        #expect(try await database.container(corrected.id) == corrected, "the year, and none of the presentations")
        #expect(!(try String(contentsOf: file, encoding: .utf8)).contains("Alien.mkv"))

        // A series smddb lacks offers the season it names, which smddb lacks too, and names the ref's
        // container neither has as the reason it would be refused.
        let series = try await console.planExport(nowhere.id.value, in: "tv", of: home, to: database)
        #expect(series.record == nil)
        #expect(series.offered.map(\.id) == [Self.season13.id])
        #expect(series.unavailable == [ContainerID("00000000000000ee")!])
        await #expect(throws: ContributionError.self) {
            try await console.export(series, choosing: [Self.season13.id], to: database)
        }
    }

    /// What the silo refuses, and what cannot be asked of it, comes back in its words: an id smddb does
    /// not have, a container held since the plan was made, a parent gone, a new container or a parent's
    /// edit the validator refuses; a container already named by its parent is made without an edit.
    @Test func smddbRefusalsAreSaidInTheSilosWords() async throws {
        let (database, folder) = Self.clone()
        defer { try? FileManager.default.removeItem(at: folder) }
        let series = Self.series(naming: [Self.season12, Self.season13])
        for container in [series, Self.season12, Self.ark, Self.season13] { try await database.save(container) }
        let refusing = Container(id: ContainerID("0000000000000069")!, type: .series, title: Title("Refused")!)
        let held = HeldLibrary([series, Self.season13, refusing])
        let (console, home) = try await Self.smddbConsole(held)

        await #expect(throws: AdminConsole.SettingsRefused.self) {
            try await console.planImport(ContainerID("00000000000000dd")!, into: "tv", of: home, from: database)
        }

        guard
            case .plan(let plan) = try await console.planImport(Self.season12.id, into: "tv", of: home, from: database)
        else {
            Issue.record("Season 12 is planned")
            return
        }
        guard
            case .wouldMake(let dry) = try await console.importContainers(
                plan,
                choosing: [],
                dryRun: true,
                of: home,
                from: database
            )
        else {
            Issue.record("the series names Season 12, so the dry run would make it")
            return
        }
        #expect(dry.writes.count == 1 && !dry.applied)

        // Held since the plan was made: refused with no parent to bring from smddb.
        held.sidecars.withLock {
            $0[Self.season12.id.value] = try! SidecarFile.data(for: Sidecar(container: Self.season12))
        }
        guard
            case .refused(let refused, nil) = try await console.importContainers(
                plan,
                choosing: [],
                dryRun: true,
                of: home,
                from: database
            )
        else {
            Issue.record("a container held since is refused, with nothing to bring first")
            return
        }
        #expect(refused.findings.count == 1)

        // The parent gone: the silo cannot be asked, and says why.
        held.sidecars.withLock { $0[series.id.value] = nil }
        await #expect(throws: AdminConsole.StoreRefused.self) {
            try await console.importContainers(plan, choosing: [], dryRun: true, of: home, from: database)
        }
        held.sidecars.withLock { $0[series.id.value] = try! SidecarFile.data(for: Sidecar(container: series)) }

        // A new container the validator refuses, checked and made at the top of the library.
        var refused2 = try await console.newContainer(
            .movie,
            titled: Title("Refused")!,
            in: "tv",
            at: ContainerDraft.Creating(),
            of: home,
            from: database
        )
        guard case .refused = try await console.check(new: refused2, of: home) else {
            Issue.record("the dry run of making it is refused")
            return
        }
        guard case .refused(let made) = try await console.create(refused2, of: home) else {
            Issue.record("making it is refused, and the draft kept")
            return
        }
        #expect(!made.applied)
        #expect(console.containerDrafts.draft(of: refused2.container, in: "tv", of: home.id) != nil)
        refused2.text = "<nope/>"
        guard case .unreadable = try await console.check(new: refused2, of: home) else {
            Issue.record("a document that is not a container is unreadable")
            return
        }
        await #expect(throws: AdminConsole.StoreRefused.self) { try await console.create(refused2, of: home) }

        // Beneath a parent whose edit the validator refuses: the parent's refusal, nothing made.
        let child = try await console.newContainer(
            .season,
            titled: Title("Season 1")!,
            in: "tv",
            at: ContainerDraft.Creating(parent: refusing.id.value),
            of: home,
            from: database
        )
        guard case .parentRefused = try await console.create(child, of: home) else {
            Issue.record("the parent's edit is refused")
            return
        }
        #expect(held.container(ContainerID(child.container)!) == nil)

        // A container its parent already names is made with no edit of the parent.
        let named = ContainerDraft.new(Self.season12, in: "tv", at: ContainerDraft.Creating(parent: series.id.value))
        held.sidecars.withLock { $0[Self.season12.id.value] = nil }
        let before = held.sidecars.withLock { $0[series.id.value] }
        guard case .created = try await console.create(named, of: home) else {
            Issue.record("Season 12 is made beneath the series that names it")
            return
        }
        #expect(held.sidecars.withLock { $0[series.id.value] } == before, "the series is not edited")
        #expect(
            AdminConsole.naming(Self.season12, in: series, at: ContainerDraft.Creating()) == series,
            "naming a child already named changes nothing"
        )
    }
}
