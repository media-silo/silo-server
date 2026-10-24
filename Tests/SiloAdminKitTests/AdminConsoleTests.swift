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
        /// The library each container is in, `tv` unless filed elsewhere.
        let libraries: Mutex<[String: String]>
        /// The artwork kinds each container's folder holds.
        let artwork: Mutex<[String: Set<String>]> = Mutex([:])
        init(_ containers: [Container] = []) {
            sidecars = Mutex(
                Dictionary(
                    uniqueKeysWithValues: containers.map {
                        ($0.id.value, try! SidecarFile.data(for: Sidecar(container: $0)))
                    }
                )
            )
            libraries = Mutex([:])
        }
        func container(_ id: ContainerID) -> Container? {
            sidecars.withLock { $0[id.value] }.flatMap { try? SidecarFile.sidecar(from: $0).container }
        }
        func sidecar(_ id: ContainerID) -> Sidecar? {
            sidecars.withLock { $0[id.value] }.flatMap { try? SidecarFile.sidecar(from: $0) }
        }
        func library(of id: String) -> String { libraries.withLock { $0[id] } ?? "tv" }
        /// Files a sidecar in a library other than `tv`.
        func file(_ sidecar: Sidecar, in library: String) {
            sidecars.withLock { $0[sidecar.container.id.value] = try! SidecarFile.data(for: sidecar) }
            libraries.withLock { $0[sidecar.container.id.value] = library }
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
            let parts = url.path.split(separator: "/").map(String.init)
            let library = parts.count > 3 && parts[1] == "libraries" ? parts[2] : "tv"
            let prefix = "/v1/libraries/\(library)/containers"
            func finding(_ text: String) -> String { #"{"severity":"error","text":"\#(text)"}"# }
            func summary(_ container: Container) -> String {
                #"{"id":"\#(container.id)","library":"\#(held.library(of: container.id.value))","type":"\#(container.type.rawValue)","title":"\#(container.title.rawValue)","displayTitle":"\#(container.displayTitle)","listed":\#(container.listed)}"#
            }
            func json<Value: Encodable>(_ value: Value) -> String {
                String(decoding: try! JSONEncoder().encode(value), as: UTF8.self)
            }
            switch (method, url.path) {
            case ("GET", "/v1/lookup"):
                let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                let ref = ExternalRef(
                    provider: Provider(rawValue: query.first { $0.name == "provider" }?.value ?? ""),
                    value: query.first { $0.name == "value" }?.value ?? ""
                )
                let carrying = held.sidecars.withLock { $0.values }.compactMap {
                    try? SidecarFile.sidecar(from: $0).container
                }
                .filter { container in
                    container.externalRefs.contains(ref)
                        || (container.sequences.flatMap(\.items) + container.extras).contains {
                            $0.externalRefs.contains(ref)
                        }
                }
                return (200, Data("[\(carrying.map(summary).joined(separator: ","))]".utf8))
            case (_, "/v1/server"): return (200, Data(Self.serverInfo("home", "Home Silo", bootstrap: false).utf8))
            case (_, "/v1/operator"): return (200, Data(Self.active.utf8))
            case ("GET", prefix):
                // The library's containers no other names, listed or not.
                let all = held.sidecars.withLock { $0 }.compactMap { id, bytes in
                    held.library(of: id) == library ? try? SidecarFile.sidecar(from: bytes).container : nil
                }
                let named = Set(all.flatMap(\.childContainerIDs))
                let top = all.filter { !named.contains($0.id) }.sorted { $0.id.value < $1.id.value }
                return (200, Data("[\(top.map(summary).joined(separator: ","))]".utf8))
            case ("POST", prefix):
                struct Create: Decodable {
                    struct Attributed: Decodable {
                        var container: String
                        var subject: String
                        var provider: String
                        var value: String
                    }
                    var documents: [String]
                    var parent: String?
                    var dryRun: Bool?
                    var attributions: [Attributed]?
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
                for container in containers {
                    let attributions = (create.attributions ?? []).filter { $0.container == container.id.value }.map {
                        Attribution(
                            subject: Attribution.Subject(rawValue: $0.subject),
                            provider: Provider(rawValue: $0.provider),
                            value: $0.value
                        )
                    }
                    held.file(Sidecar(container: container, attributions: attributions), in: library)
                }
                return (200, result(true))
            case (let method, let path) where path.hasPrefix(prefix + "/"):
                let rest = path.dropFirst(prefix.count + 1).split(separator: "/").map(String.init)
                guard let bytes = held.sidecars.withLock({ $0[rest[0]] }), held.library(of: rest[0]) == library,
                    let sidecar = try? SidecarFile.sidecar(from: bytes)
                else { return (404, Data()) }
                let container = sidecar.container
                let digest = Self.digest(bytes)
                if rest.count == 2, rest[1] == "smd" { return (200, bytes) }
                if rest.count == 3, rest[1] == "artwork", method == "PUT" {
                    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                    let provider = query.first { $0.name == "provider" }?.value
                    let value = query.first { $0.name == "value" }?.value
                    var attributions = sidecar.attributions.filter { $0.subject != .artwork(rest[2]) }
                    if let provider, let value {
                        attributions.append(
                            Attribution(
                                subject: .artwork(rest[2]),
                                provider: Provider(rawValue: provider),
                                value: value
                            )
                        )
                    }
                    let written = try SidecarFile.data(settingAttributions: attributions, in: bytes)
                    held.sidecars.withLock { $0[rest[0]] = written }
                    held.artwork.withLock { $0[rest[0], default: []].insert(rest[2]) }
                    return (200, Data(#"{"kind":"\#(rest[2])","format":"jpg"}"#.utf8))
                }
                if method == "PUT" {
                    struct Edit: Decodable {
                        var document: String
                        var basedOn: String
                        var dryRun: Bool?
                        var attributions: [SiloClient.Container.Attribution]?
                        var declined: [SiloClient.Container.ExternalRef]?
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
                    var written = try SidecarFile.data(settingContainer: value, in: bytes)
                    if let attributions = edit.attributions {
                        written = try SidecarFile.data(
                            settingAttributions: attributions.map {
                                Attribution(
                                    subject: Attribution.Subject(rawValue: $0.subject),
                                    provider: Provider(rawValue: $0.provider),
                                    value: $0.value
                                )
                            } + sidecar.attributions.filter { $0.subject.artworkKind != nil },
                            in: written
                        )
                    }
                    if let declined = edit.declined {
                        written = try SidecarFile.data(
                            settingDeclined: declined.map {
                                ExternalRef(provider: Provider(rawValue: $0.provider), value: $0.value)
                            },
                            in: written
                        )
                    }
                    if edit.dryRun != true { held.sidecars.withLock { $0[rest[0]] = written } }
                    return (
                        200,
                        Data(
                            #"{"applied":\#(edit.dryRun != true),"sidecar":"","digest":"\#(Self.digest(written))","findings":[]}"#
                                .utf8
                        )
                    )
                }
                let attributions = json(sidecar.attributions.map(AdminConsoleTests.wire))
                let declined = json(
                    sidecar.declined.map {
                        SiloClient.Container.ExternalRef(provider: $0.provider.rawValue, value: $0.value)
                    }
                )
                let parent = held.sidecars.withLock { $0 }.first { _, bytes in
                    (try? SidecarFile.sidecar(from: bytes))?.container.childContainerIDs.contains(container.id) == true
                }?.key
                let refs = json(
                    container.externalRefs.map {
                        SiloClient.Container.ExternalRef(provider: $0.provider.rawValue, value: $0.value)
                    }
                )
                let parentField = parent.map { #","parent":"\#($0)""# } ?? ""
                let containerJSON =
                    #"{"id":"\#(container.id)","library":"\#(library)","type":"\#(container.type.rawValue)","title":"\#(container.title.rawValue)","displayTitle":"\#(container.displayTitle)","listed":true,"alternatives":[],"features":[],"sequences":[],"extras":[],"children":[],"externalRefs":\#(refs),"attributions":\#(attributions)\#(parentField)}"#
                let artwork = json(Array(held.artwork.withLock { $0[container.id.value] ?? [] }).sorted())
                return (
                    200,
                    Data(
                        #"{"library":"\#(library)","path":"\#(container.id)/container.smd","digest":"\#(digest)","artwork":\#(artwork),"container":\#(containerJSON),"declined":\#(declined)}"#
                            .utf8
                    )
                )
            default: return (404, Data())
            }
        }
    }

    fileprivate static func wire(_ attribution: Attribution) -> SiloClient.Container.Attribution {
        SiloClient.Container.Attribution(
            subject: attribution.subject.rawValue,
            provider: attribution.provider.rawValue,
            value: attribution.value
        )
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

// MARK: - TMDb

extension AdminConsoleTests {
    /// TMDb's answers as the tests give them: each record by its number, nothing else.
    private struct FakeTMDb: TMDbSource {
        var movies: [Int: TMDb.Movie] = [:]
        var series: [Int: TMDb.Series] = [:]
        /// By `series/number`.
        var seasons: [String: TMDb.Season] = [:]
        var collections: [Int: TMDb.Collection] = [:]
        var groups: [String: TMDb.EpisodeGroup] = [:]
        /// By episode id.
        var episodeIDs: [Int: TMDb.ExternalIDs] = [:]
        /// By `provider:value`.
        var found: [String: TMDb.Found] = [:]
        var refusesToken = false
        /// Fails as no answer of TMDb's says, as a dropped connection does.
        var unreachable = false
        var images: [TMDb.Record: TMDb.Images] = [:]
        /// When set, each episode's other ids are answered after a pause, counting how many are asked at once.
        var asking: Asking?

        struct Missing: Error {}

        /// How many questions of TMDb's are being asked at once, and the most there have been.
        final class Asking: Sendable {
            private let counts = Mutex((now: 0, most: 0))
            var most: Int { counts.withLock { $0.most } }

            func ask() async throws {
                counts.withLock { $0 = (now: $0.now + 1, most: max($0.most, $0.now + 1)) }
                defer { counts.withLock { $0.now -= 1 } }
                try await Task.sleep(for: .milliseconds(20))
            }
        }

        /// A JPEG's signature and nothing else, as every image TMDb serves here.
        static let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00])
        func images(of record: TMDb.Record) async throws -> TMDb.Images { images[record] ?? .init() }
        func image(at path: String) async throws -> Data { Self.jpeg }

        func authenticate() async throws {
            if refusesToken { throw TMDb.Unavailable.refused }
            if unreachable { throw Missing() }
        }
        func search(_ query: String) async throws -> [TMDb.SearchResult] { [] }
        func movie(_ id: Int) async throws -> TMDb.Movie { try movies[id] ?? { throw Missing() }() }
        func series(_ id: Int) async throws -> TMDb.Series { try series[id] ?? { throw Missing() }() }
        func season(_ number: Int, of series: Int) async throws -> TMDb.Season {
            try seasons["\(series)/\(number)"] ?? { throw Missing() }()
        }
        func episodeGroup(_ id: String) async throws -> TMDb.EpisodeGroup { try groups[id] ?? { throw Missing() }() }
        func collection(_ id: Int) async throws -> TMDb.Collection { try collections[id] ?? { throw Missing() }() }
        func externalIDs(of episode: TMDb.Episode, in series: Int) async throws -> TMDb.ExternalIDs {
            try await asking?.ask()
            return episodeIDs[episode.id] ?? .init()
        }
        func find(_ ref: ExternalRef) async throws -> TMDb.Found { found["\(ref.provider):\(ref.value)"] ?? .init() }
    }

    private static let alienRecord = TMDb.Movie(
        id: 348,
        title: "Alien",
        year: 1979,
        overview: "In space no one can hear you scream.",
        externalIDs: TMDb.ExternalIDs(imdb: "tt0078748", wikidata: "Q103569")
    )

    private static func episode(
        _ id: Int,
        _ season: Int,
        _ number: Int,
        _ title: String,
        aired: String? = nil,
        runtime: Int? = nil
    )
        -> TMDb.Episode
    {
        TMDb.Episode(id: id, season: season, number: number, title: title, airDate: aired, runtime: runtime)
    }

    /// The console, silo, clone and TMDb a walk is asked of.
    private struct Walking {
        var console: AdminConsole
        var home: AdminConsole.Silo
        var database: any ContainerDatabase
        var tmdb: any TMDbSource
        var library = "tv"

        /// Opens a stop: its container read against TMDb.
        func read(_ id: String, in walk: inout TMDbWalk) async throws {
            walk.read(try await console.compare(id, in: library, of: home, from: database, tmdb: tmdb))
        }

        /// Opens a stop, ticks what is given, and confirms it.
        func confirm(_ id: String, choosing chosen: Set<String> = [], in walk: inout TMDbWalk) async throws {
            if walk.stops[id]?.comparison == nil { try await read(id, in: &walk) }
            walk.stops[id]?.chosen = chosen
            walk.confirm(id, beneath: try await console.stops(beneath: id, in: walk, of: home))
        }

        /// A walk rooted at a held container, its root read, ticked as given, and confirmed.
        func walk(_ id: String, choosing chosen: Set<String> = []) async throws -> TMDbWalk {
            var walk = try await console.startWalk(at: id, in: library, of: home)
            try await confirm(id, choosing: chosen, in: &walk)
            return walk
        }
    }

    /// The edit a walk's store makes of a container.
    private static func edit(of id: String, in plan: TMDbWalk.Plan) -> ContainerDraft? {
        plan.steps.lazy.compactMap { step in
            if case .edit(let draft) = step.kind, draft.container == id { draft } else { nil }
        }
        .first
    }

    /// The token is asked of TMDb: none given, or one TMDb refuses, leaves its actions unavailable, and
    /// says which.
    @Test func tmdbIsUnavailableWithoutAToken() async throws {
        #expect(await AdminConsole.tmdbStanding(token: nil) { _ in FakeTMDb() } == .noToken)
        #expect(await AdminConsole.tmdbStanding(token: "") { _ in FakeTMDb() } == .noToken)
        #expect(TMDb.Unavailable.noToken.reason == "No TMDb token is given in this Mac's settings.")
        #expect(await AdminConsole.tmdbStanding(token: "stale") { _ in FakeTMDb(refusesToken: true) } == .refused)
        #expect(TMDb.Unavailable.refused.reason == "TMDb refused the token in this Mac's settings.")
        #expect(await AdminConsole.tmdbStanding(token: "good") { _ in FakeTMDb() } == nil)
        #expect(await AdminConsole.tmdbStanding(token: "good") { _ in FakeTMDb(unreachable: true) } == .answered(0))
    }

    /// A film, a season beneath a series the library holds, and a season regrouped into serials, each
    /// drafted from TMDb's record with facts taken plainly and the outline attributed, kept on this Mac,
    /// and made through the create route.
    @Test func aContainerIsDraftedFromTMDb() async throws {
        let (database, folder) = Self.clone()
        defer { try? FileManager.default.removeItem(at: folder) }
        var doctorWho = Self.series(naming: [Self.season13])
        doctorWho.externalRefs.append(ExternalRef(provider: .tmdb, value: "121"))
        let held = HeldLibrary([doctorWho, Self.season13])
        let (console, home) = try await Self.smddbConsole(held)
        var tmdb = FakeTMDb(movies: [348: Self.alienRecord])
        let parts = [
            Self.episode(1001, 14, 1, "The Robots of Death: Part One"),
            Self.episode(1002, 14, 2, "The Robots of Death: Part Two"),
            Self.episode(1003, 14, 3, "The Talons of Weng-Chiang: Part One"),
        ]
        tmdb.seasons["121/14"] = TMDb.Season(id: 3644, number: 14, name: "Season 14", year: 1976, episodes: parts)

        guard
            case .draft(let film) = try await console.startDraft(
                of: TMDb.Record(.movie, 348),
                into: "tv",
                of: home,
                from: database,
                tmdb: tmdb
            )
        else {
            Issue.record("a film neither smddb nor the library holds is drafted")
            return
        }
        let alien = try #require(film.container(film.top))
        #expect(alien.type == .movie && alien.title == Title("Alien")! && alien.year == 1979)
        #expect(
            alien.externalRefs == [
                ExternalRef(provider: .tmdb, value: "348"), ExternalRef(provider: .imdb, value: "tt0078748"),
                ExternalRef(provider: .wikidata, value: "Q103569"),
            ]
        )
        #expect(alien.outline == "In space no one can hear you scream.")
        let attributed = [Attribution(subject: .outline, provider: .tmdb, value: "348")]
        #expect(film.attributions[film.top] == attributed)
        #expect(try await database.container(alien.id) == nil, "an id the clone has no file for")
        #expect(console.tmdbDrafts.drafts(of: home.id).map(\.id) == [film.id], "kept on this Mac")
        guard case .created = try await console.create(film, of: home) else {
            Issue.record("the film is made")
            return
        }
        #expect(held.sidecar(alien.id)?.attributions == attributed, "made with its outline's attribution")
        #expect(console.tmdbDrafts.drafts(of: home.id).isEmpty, "made, the draft ends")

        // A season of a series the library holds, filed beneath it.
        let season = try await console.startDraft(
            ofSeason: 14,
            of: 121,
            beneath: doctorWho.id.value,
            into: "tv",
            of: home,
            from: database,
            tmdb: tmdb
        )
        let fourteen = try #require(season.container(season.top))
        let entries = fourteen.sequences.flatMap(\.items)
        #expect(entries.map(\.externalRefs) == parts.map { [$0.ref] })
        #expect(entries.allSatisfy { $0.title == nil }, "TMDb has a title for each, so none is stored")
        #expect(season.episodeTitles["1001"] == "The Robots of Death: Part One", "but each is shown")
        guard case .wouldWrite = try await console.check(season, of: home) else {
            Issue.record("the parent's edit naming the season would be written")
            return
        }
        guard case .created = try await console.create(season, of: home) else {
            Issue.record("the season is made beneath the series")
            return
        }
        #expect(held.container(doctorWho.id)?.childContainerIDs.contains(fourteen.id) == true)
        #expect(held.container(fourteen.id)?.sequences.flatMap(\.items).count == 3)

        // The same season regrouped into two serials before it is made.
        held.sidecars.withLock { $0[fourteen.id.value] = nil }
        var regrouped = try await console.startDraft(
            ofSeason: 14,
            of: 121,
            beneath: doctorWho.id.value,
            into: "tv",
            of: home,
            from: database,
            tmdb: tmdb
        )
        let items = try #require(regrouped.container(regrouped.top)).sequences[0].items.compactMap(\.id)
        let robots = try await database.provisionalID()
        let talons = try await database.provisionalID()
        regrouped.regroup(
            Array(items[0...1]),
            in: regrouped.top,
            into: robots,
            type: .serial,
            typeLabel: "Story",
            title: Title("The Robots of Death")!
        )
        regrouped.regroup(
            [items[2]],
            in: regrouped.top,
            into: talons,
            type: .serial,
            title: Title("The Talons of Weng-Chiang")!
        )
        guard case .created = try await console.create(regrouped, of: home) else {
            Issue.record("the regrouped season is made")
            return
        }
        #expect(held.container(ContainerID(regrouped.top)!)?.childContainerIDs == [robots, talons])
        #expect(
            held.container(robots)?.sequences.flatMap(\.items).map(\.externalRefs) == [[parts[0].ref], [parts[1].ref]],
            "in TMDb's order"
        )

        // A series the library holds by its reference is not drafted.
        tmdb.series[121] = TMDb.Series(id: 121, name: "Doctor Who", seasons: [])
        guard
            case .held(let summary) = try await console.startDraft(
                of: TMDb.Record(.series, 121),
                into: "tv",
                of: home,
                from: database,
                tmdb: tmdb
            )
        else {
            Issue.record("the series the library holds is said to be held")
            return
        }
        #expect(summary.id == doctorWho.id.value)
    }

    /// A record smddb holds, by its reference on a container of the record's kind, is imported from
    /// smddb; the same number on a film is another record, and does not stop a series being drafted.
    @Test func aRecordSmddbHoldsIsImportedRatherThanDrafted() async throws {
        let (database, folder) = Self.clone()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (console, home) = try await Self.smddbConsole(HeldLibrary())
        let tmdb = FakeTMDb(series: [121: TMDb.Series(id: 121, name: "Doctor Who", year: 1963, seasons: [])])
        let film = Container(
            type: .movie,
            title: Title("The Two Towers")!,
            externalRefs: [ExternalRef(provider: .tmdb, value: "121")]
        )
        try await database.save(film)
        guard
            case .draft = try await console.startDraft(
                of: TMDb.Record(.series, 121),
                into: "tv",
                of: home,
                from: database,
                tmdb: tmdb
            )
        else {
            Issue.record("a film carrying the same number does not hold the series")
            return
        }

        var series = Self.series(naming: [])
        series.externalRefs.append(ExternalRef(provider: .tmdb, value: "121"))
        try await database.save(series)
        #expect(
            try await console.startDraft(
                of: TMDb.Record(.series, 121),
                into: "tv",
                of: home,
                from: database,
                tmdb: tmdb
            )
                == .importFromSmddb(series)
        )
    }

    /// A series' season 0 is its specials, unassigned: placed by where they aired, into a breakout, or
    /// declined, with what each suggestion says; one left unassigned is not made.
    @Test func aSeriesSpecialsArePlacedFromThePool() async throws {
        let (database, folder) = Self.clone()
        defer { try? FileManager.default.removeItem(at: folder) }
        let held = HeldLibrary()
        let (console, home) = try await Self.smddbConsole(held)
        var tmdb = FakeTMDb()
        tmdb.series[900] = TMDb.Series(
            id: 900,
            name: "Doctor Who",
            year: 2005,
            seasons: [.init(id: 50, number: 0, name: "Specials"), .init(id: 51, number: 1, name: "Series 1")]
        )
        let first = Self.episode(2001, 1, 1, "Rose", aired: "2005-03-26")
        let second = Self.episode(2002, 1, 2, "The End of the World", aired: "2005-04-09")
        tmdb.seasons["900/1"] = TMDb.Season(id: 51, number: 1, name: "Series 1", year: 2005, episodes: [first, second])
        let christmas = Self.episode(3001, 0, 1, "Children in Need", aired: "2005-04-02", runtime: 7)
        let sofaOne = Self.episode(3002, 0, 2, "Behind the Sofa: Rose", runtime: 40)
        let unplaced = Self.episode(3003, 0, 3, "A Night Out", runtime: 40)
        let sofaTwo = Self.episode(3004, 0, 4, "Behind the Sofa: The End of the World", runtime: 40)
        let trailer = Self.episode(3005, 0, 5, "Series 1 Trailer", runtime: 2)
        tmdb.seasons["900/0"] = TMDb.Season(
            id: 50,
            number: 0,
            name: "Specials",
            episodes: [christmas, sofaOne, unplaced, sofaTwo, trailer]
        )

        guard
            case .draft(var tree) = try await console.startDraft(
                of: TMDb.Record(.series, 900),
                into: "tv",
                of: home,
                from: database,
                tmdb: tmdb
            )
        else {
            Issue.record("the series is drafted")
            return
        }
        #expect(tree.containers.map(\.type) == [.series, .season], "season 0 is not a season")
        #expect(tree.specials.map(\.id) == [3001, 3002, 3003, 3004, 3005])
        #expect(tree.unassigned.count == 5)
        let season = try #require(tree.containers.last).id.value

        var (suggested, suggestions) = try await console.suggest(for: tree, of: home, from: database, tmdb: tmdb)
        tree = suggested
        #expect(suggestions[3001]?.placement == .entry(in: season, sequence: "episodes", position: 1))
        #expect(suggestions[3001]?.reason == "it aired between Rose and The End of the World")
        #expect(
            suggestions[3005]
                == AdminConsole.SpecialSuggestion(placement: .declined, reason: "its title says it is a trailer")
        )
        #expect(suggestions[3002] == nil && suggestions[3003] == nil)

        tree.place(3001, suggestions[3001]?.placement)
        var sofa = Container(
            id: try await database.provisionalID(),
            type: .series,
            title: Title("Behind the Sofa")!,
            listed: false
        )
        sofa.sequences = [Sequence(id: "episodes", items: [])]
        tree.place(3002, .breakout(sofa.id.value, from: season, asExtra: true), breakout: sofa)
        tree.place(3004, .breakout(sofa.id.value, from: season, asExtra: true))
        tree.place(3005, .declined)
        (suggested, suggestions) = try await console.suggest(for: tree, of: home, from: database, tmdb: tmdb)
        tree = suggested
        #expect(suggestions[3003]?.placement == .breakout(sofa.id.value, from: season, asExtra: true))
        #expect(suggestions[3003]?.reason == "the specials either side of it are in Behind the Sofa")
        #expect(tree.making.described.first == "make Behind the Sofa, a series of its own, at the top of the library")

        guard case .created = try await console.create(tree, of: home) else {
            Issue.record("the series is made with its placed specials")
            return
        }
        let madeSofa = try #require(held.container(sofa.id))
        #expect(!madeSofa.listed)
        #expect(madeSofa.sequences.flatMap(\.items).map(\.externalRefs) == [[sofaOne.ref], [sofaTwo.ref]])
        let madeSeason = try #require(held.container(ContainerID(season)!))
        #expect(
            madeSeason.sequences.flatMap(\.items).map(\.externalRefs) == [[first.ref], [christmas.ref], [second.ref]]
        )
        #expect(madeSeason.extras.compactMap(\.reference).map(\.container) == [sofa.id, sofa.id])
        let series = try #require(held.sidecar(ContainerID(tree.top)!))
        #expect(series.declined == [trailer.ref])
        let everything = held.sidecars.withLock { Array($0.values) }.map { String(decoding: $0, as: UTF8.self) }
        #expect(!everything.contains { $0.contains(#"value="3003""#) }, "the unassigned special is not made")
    }

    /// A special whose IMDb id is a TMDb movie's, which another library holds, is suggested as the
    /// movie's duplicate; taken, the film's item carries the special's id and the series refers to it.
    @Test func aSpecialIsSuggestedAsAMoviesDuplicate() async throws {
        let (database, folder) = Self.clone()
        defer { try? FileManager.default.removeItem(at: folder) }
        let held = HeldLibrary()
        var day = Container(
            id: ContainerID("0000000000000081")!,
            type: .movie,
            title: Title("The Day of the Doctor")!,
            externalRefs: [ExternalRef(provider: .tmdb, value: "1000")]
        )
        day.sequences = [Sequence(id: "main", items: [.leaf(Entry.Leaf(id: ItemID("feature")!, type: .movie))])]
        held.file(Sidecar(container: day), in: "films")
        let (console, home) = try await Self.smddbConsole(held)
        var tmdb = FakeTMDb()
        tmdb.series[901] = TMDb.Series(
            id: 901,
            name: "Doctor Who",
            seasons: [.init(id: 60, number: 0, name: "Specials")]
        )
        let special = Self.episode(5000, 0, 1, "The Day of the Doctor", aired: "2013-11-23", runtime: 77)
        tmdb.seasons["901/0"] = TMDb.Season(id: 60, number: 0, name: "Specials", episodes: [special])
        tmdb.episodeIDs[5000] = TMDb.ExternalIDs(imdb: "tt2779318")
        tmdb.found["imdb:tt2779318"] = TMDb.Found(movies: [TMDb.Movie(id: 1000, title: "The Day of the Doctor")])

        guard
            case .draft(let drafted) = try await console.startDraft(
                of: TMDb.Record(.series, 901),
                into: "tv",
                of: home,
                from: database,
                tmdb: tmdb
            )
        else {
            Issue.record("the series is drafted")
            return
        }
        var (tree, suggestions) = try await console.suggest(for: drafted, of: home, from: database, tmdb: tmdb)
        let suggestion = try #require(suggestions[5000])
        #expect(
            suggestion.placement
                == .duplicate(home: day.id.value, item: "feature", library: "films", from: tree.top, asExtra: false)
        )
        #expect(suggestion.reason == "its IMDb id is The Day of the Doctor's, TMDb's movie 1000, which films holds")
        #expect(tree.specials[0].refs.contains(ExternalRef(provider: .imdb, value: "tt2779318")), "asked of TMDb")
        tree.place(5000, suggestion.placement)
        #expect(tree.making.described.last == "add TMDb's id to feature of \(day.id) in films")
        guard case .created = try await console.create(tree, of: home) else {
            Issue.record("the series is made")
            return
        }
        let film = try #require(held.container(day.id))
        #expect(film.sequences[0].items[0].externalRefs.contains(special.ref), "the home carries both ids")
        let series = try #require(held.container(ContainerID(tree.top)!))
        #expect(
            series.sequences.flatMap(\.items).compactMap(\.reference) == [
                EntryRef(container: day.id, item: ItemID("feature")!)
            ]
        )
    }

    /// An attributed outline keeps its attribution through a rewording, loses it with the outline, and
    /// loses it alone when the operator says the text is their own; smddb's record taken in is smddb's.
    @Test func anAttributedOutlineIsKeptThroughAnEdit() async throws {
        let outlined = Container(
            id: ContainerID("0000000000000091")!,
            type: .movie,
            title: Title("Alien")!,
            outline: "In space no one can hear you scream."
        )
        let attribution = Attribution(subject: .outline, provider: .tmdb, value: "348")
        let held = HeldLibrary()
        held.file(Sidecar(container: outlined, attributions: [attribution]), in: "tv")
        let (console, home) = try await Self.smddbConsole(held)

        let opened = try await console.open(container: outlined.id.value, in: "tv", of: home)
        var draft = try ContainerDraft.change(opened.container, sidecar: opened.sidecar)
        #expect(draft.attributions == [attribution] && !draft.isChanged)
        var reworded = outlined
        reworded.outline = "No one can hear you scream in space."
        draft.set(reworded)
        #expect(draft.attributions == [attribution], "a rewording is still derived from it")
        guard case .stored = try await console.store(draft, of: home) else {
            Issue.record("the rewording is stored")
            return
        }
        #expect(held.sidecar(outlined.id)?.container.outline == reworded.outline)
        #expect(held.sidecar(outlined.id)?.attributions == [attribution])

        let again = try await console.open(container: outlined.id.value, in: "tv", of: home)
        var own = try ContainerDraft.change(again.container, sidecar: again.sidecar)
        own.removeAttribution(of: .outline)
        #expect(own.isChanged, "an attribution removed is a change")
        guard case .stored = try await console.store(own, of: home) else {
            Issue.record("the attribution's removal is stored")
            return
        }
        #expect(held.sidecar(outlined.id)?.attributions.isEmpty == true)
        #expect(held.sidecar(outlined.id)?.container.outline == reworded.outline)

        var gone = draft
        var bare = reworded
        bare.outline = nil
        gone.set(bare)
        #expect(gone.attributions.isEmpty, "the outline gone takes its attribution")
        var fromSmddb = draft
        var record = reworded
        record.outline = "smddb's own words"
        fromSmddb.take(record)
        #expect(fromSmddb.attributions.isEmpty, "smddb's text is not TMDb's")
        var sameText = draft
        sameText.take(reworded)
        #expect(sameText.attributions == [attribution])
    }

    /// A contribution takes smddb's value, or none, for each field the library attributes, and says which.
    @Test func anAttributedFieldIsLeftOutOfAContribution() async throws {
        let (database, folder) = Self.clone()
        defer { try? FileManager.default.removeItem(at: folder) }
        let attribution = Attribution(subject: .outline, provider: .tmdb, value: "348")
        let alien = Container(
            id: ContainerID("0000000000000092")!,
            type: .movie,
            title: Title("Alien")!,
            outline: "In space no one can hear you scream."
        )
        let held = HeldLibrary()
        held.file(Sidecar(container: alien, attributions: [attribution]), in: "tv")
        let (console, home) = try await Self.smddbConsole(held)

        let plan = try await console.planExport(alien.id.value, in: "tv", of: home, to: database)
        #expect(plan.leftOut == [alien.id: [attribution]])
        #expect(plan.container.outline == nil)
        _ = try await console.export(plan, choosing: [], to: database)
        #expect(try await database.container(alien.id)?.outline == nil, "the clone's file has no outline")

        var record = alien
        record.outline = "smddb's own words"
        try await database.save(record)
        let over = try await console.planExport(alien.id.value, in: "tv", of: home, to: database)
        #expect(over.container.outline == "smddb's own words")
        #expect(
            !over.difference.contains { $0.kind != .same && $0.text.contains("outline") },
            "no change to the outline"
        )
    }

    /// A collection is drafted with a container for each of its films; a film in a collection the
    /// library holds is filed beneath it.
    @Test func aCollectionIsDraftedAndAFilmFiledBeneathTheOneHeld() async throws {
        let (database, folder) = Self.clone()
        defer { try? FileManager.default.removeItem(at: folder) }
        let alienCollection = Container(
            id: ContainerID("00000000000000a1")!,
            type: .collection,
            title: Title("Alien Collection")!,
            externalRefs: [ExternalRef(provider: .tmdb, value: "8091")]
        )
        let held = HeldLibrary([alienCollection])
        let (console, home) = try await Self.smddbConsole(held)
        var alien = Self.alienRecord
        alien.collection = 8091
        var tmdb = FakeTMDb(movies: [348: alien, 679: TMDb.Movie(id: 679, title: "Aliens", year: 1986)])
        tmdb.collections[9000] = TMDb.Collection(
            id: 9000,
            name: "Quadrilogy",
            overview: "Ripley, four times.",
            parts: [TMDb.Movie(id: 348, title: "Alien"), TMDb.Movie(id: 679, title: "Aliens")]
        )

        guard
            case .draft(let quadrilogy) = try await console.startDraft(
                of: TMDb.Record(.collection, 9000),
                into: "tv",
                of: home,
                from: database,
                tmdb: tmdb
            )
        else {
            Issue.record("a collection no library holds is drafted")
            return
        }
        #expect(quadrilogy.containers.map(\.type) == [.collection, .movie, .movie])
        let top = try #require(quadrilogy.container(quadrilogy.top))
        #expect(top.childContainerIDs == quadrilogy.containers.dropFirst().map(\.id), "each film in its order")
        #expect(
            quadrilogy.attributions[quadrilogy.top] == [Attribution(subject: .outline, provider: .tmdb, value: "9000")]
        )
        #expect(quadrilogy.making.described == ["make Quadrilogy and the 2 beneath it"])

        guard
            case .draft(let film) = try await console.startDraft(
                of: TMDb.Record(.movie, 348),
                into: "tv",
                of: home,
                from: database,
                tmdb: tmdb
            )
        else {
            Issue.record("the film is drafted")
            return
        }
        #expect(film.creating.parent == alienCollection.id.value, "beneath the collection the library holds")
        guard case .created = try await console.create(film, of: home) else {
            Issue.record("the film is made beneath the collection")
            return
        }
        #expect(held.container(alienCollection.id)?.childContainerIDs == [ContainerID(film.top)!])
    }

    /// A series read through one of its episode groups is a child of the type given for each group, its
    /// episodes in the group's order and the specials the group places out of the pool. Read by its
    /// seasons, a special takes the place the series' first episode group gives it, or, short and named
    /// for what it is, is an extra of that type.
    @Test func aSeriesIsReadThroughAnEpisodeGroup() async throws {
        let (database, folder) = Self.clone()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (console, home) = try await Self.smddbConsole(HeldLibrary())
        var tmdb = FakeTMDb()
        tmdb.series[902] = TMDb.Series(
            id: 902,
            name: "Torchwood",
            seasons: [.init(id: 70, number: 0, name: "Specials"), .init(id: 71, number: 1, name: "Series 1")],
            episodeGroups: [.init(id: "g1", name: "Story arcs")]
        )
        let first = Self.episode(4101, 1, 1, "Everything Changes")
        let second = Self.episode(4102, 1, 2, "Day One")
        let third = Self.episode(4103, 1, 3, "Ghost Machine")
        let interlude = Self.episode(4001, 0, 1, "Interlude", runtime: 45)
        let makingOf = Self.episode(4002, 0, 2, "The Making of Torchwood", runtime: 12)
        tmdb.seasons["902/1"] = TMDb.Season(id: 71, number: 1, name: "Series 1", episodes: [first, second, third])
        tmdb.seasons["902/0"] = TMDb.Season(id: 70, number: 0, name: "Specials", episodes: [interlude, makingOf])
        tmdb.groups["g1"] = TMDb.EpisodeGroup(
            id: "g1",
            name: "Story arcs",
            groups: [
                .init(name: "Arc One", episodes: [first, interlude, second]),
                .init(name: "Arc Two", episodes: [third]),
            ]
        )

        guard
            case .draft(let arcs) = try await console.startDraft(
                of: TMDb.Record(.series, 902),
                shape: AdminConsole.TMDbShape(group: "g1", groupType: .arc, groupTypeLabel: "Arc"),
                into: "tv",
                of: home,
                from: database,
                tmdb: tmdb
            )
        else {
            Issue.record("the series is drafted through its group")
            return
        }
        #expect(arcs.containers.map(\.type) == [.series, .arc, .arc])
        #expect(arcs.containers.dropFirst().map(\.typeLabel) == ["Arc", "Arc"])
        #expect(
            arcs.containers[1].sequences.flatMap(\.items).map(\.externalRefs)
                == [[first.ref], [interlude.ref], [second.ref]]
        )
        #expect(arcs.specials.map(\.id) == [makingOf.id], "the group placed the other")

        guard
            case .draft(let seasons) = try await console.startDraft(
                of: TMDb.Record(.series, 902),
                into: "tv",
                of: home,
                from: database,
                tmdb: tmdb
            )
        else {
            Issue.record("the series is drafted by its seasons")
            return
        }
        let season = try #require(seasons.containers.last).id.value
        let (_, suggestions) = try await console.suggest(for: seasons, of: home, from: database, tmdb: tmdb)
        #expect(
            suggestions[interlude.id]
                == AdminConsole.SpecialSuggestion(
                    placement: .entry(in: season, sequence: "episodes", position: 1),
                    reason: "Story arcs places it after Everything Changes",
                    basis: .group
                )
        )
        #expect(
            suggestions[makingOf.id]
                == AdminConsole.SpecialSuggestion(
                    placement: .extra(of: seasons.top, type: EntryType.behindTheScenes.rawValue),
                    reason: "its title says it is a making-of"
                )
        )
    }

    /// Where smddb's record of the series files a special, by the references its containers share with
    /// the tree's; and a special whose other id is another series' episode, or a film no library holds,
    /// is that one's duplicate, or advice to draft that first.
    @Test func aSpecialIsSuggestedWhereSmddbFilesItOrAsAnotherRecordsDuplicate() async throws {
        let (database, folder) = Self.clone()
        defer { try? FileManager.default.removeItem(at: folder) }
        let filed = Self.episode(4201, 0, 1, "Attack of the Graske", runtime: 40)
        let interviewed = Self.episode(4202, 0, 2, "Meeting the Doctor", runtime: 40)
        let shared = Self.episode(4203, 0, 3, "Rose: Extended", runtime: 40)
        let film = Self.episode(4204, 0, 4, "The Movie", runtime: 40)
        let unheld = Self.episode(4205, 0, 5, "Dalek: Extended", runtime: 40)
        var record = Container(
            type: .series,
            title: Title("Doctor Who")!,
            externalRefs: [ExternalRef(provider: .tvdb, value: "78804")]
        )
        record.extras = [.leaf(Entry.Leaf(id: ItemID("meeting")!, type: .interview, externalRefs: [interviewed.ref]))]
        var recordSeason = Container(
            type: .season,
            title: Title("Series 1")!,
            externalRefs: [ExternalRef(provider: .tmdb, value: "81")]
        )
        recordSeason.sequences = [
            Sequence(
                id: "episodes",
                items: [.leaf(Entry.Leaf(id: ItemID("graske")!, type: .episode, externalRefs: [filed.ref]))]
            )
        ]
        try await database.save(record)
        try await database.save(recordSeason)
        let rose = Self.episode(8000, 1, 1, "Rose")
        var other = Container(id: ContainerID("00000000000000b1")!, type: .series, title: Title("Doctor Who")!)
        other.sequences = [
            Sequence(
                id: "episodes",
                items: [.leaf(Entry.Leaf(id: ItemID("rose")!, type: .episode, externalRefs: [rose.ref]))]
            )
        ]
        let (console, home) = try await Self.smddbConsole(HeldLibrary([other]))
        var tmdb = FakeTMDb()
        tmdb.series[903] = TMDb.Series(
            id: 903,
            name: "Doctor Who",
            seasons: [.init(id: 80, number: 0, name: "Specials"), .init(id: 81, number: 1, name: "Series 1")],
            externalIDs: TMDb.ExternalIDs(tvdb: "78804")
        )
        tmdb.seasons["903/1"] = TMDb.Season(id: 81, number: 1, name: "Series 1", episodes: [])
        tmdb.seasons["903/0"] = TMDb.Season(
            id: 80,
            number: 0,
            name: "Specials",
            episodes: [filed, interviewed, shared, film, unheld]
        )
        tmdb.episodeIDs[shared.id] = TMDb.ExternalIDs(imdb: "tt0001")
        tmdb.episodeIDs[film.id] = TMDb.ExternalIDs(tvdb: "55")
        tmdb.episodeIDs[unheld.id] = TMDb.ExternalIDs(imdb: "tt0002")
        tmdb.found["imdb:tt0001"] = TMDb.Found(episodes: [(series: 777, episode: rose)])
        tmdb.found["tvdb:55"] = TMDb.Found(movies: [TMDb.Movie(id: 1234, title: "Doctor Who")])
        tmdb.found["imdb:tt0002"] = TMDb.Found(episodes: [(series: 778, episode: Self.episode(8001, 1, 6, "Dalek"))])

        guard
            case .draft(let tree) = try await console.startDraft(
                of: TMDb.Record(.series, 903),
                into: "tv",
                of: home,
                from: database,
                tmdb: tmdb
            )
        else {
            Issue.record("a series smddb holds by another provider's id alone is drafted")
            return
        }
        let season = try #require(tree.containers.last).id.value
        let (_, suggestions) = try await console.suggest(for: tree, of: home, from: database, tmdb: tmdb)
        #expect(
            suggestions[filed.id]
                == AdminConsole.SpecialSuggestion(
                    placement: .entry(in: season),
                    reason: "smddb files it in \(recordSeason.displayTitle)",
                    basis: .smddb
                )
        )
        #expect(
            suggestions[interviewed.id]
                == AdminConsole.SpecialSuggestion(
                    placement: .extra(of: tree.top, type: EntryType.interview.rawValue),
                    reason: "smddb files it among \(record.displayTitle)'s extras",
                    basis: .smddb
                )
        )
        #expect(
            suggestions[shared.id]
                == AdminConsole.SpecialSuggestion(
                    placement: .duplicate(
                        home: other.id.value,
                        item: "rose",
                        library: "tv",
                        from: tree.top,
                        asExtra: true
                    ),
                    reason: "its IMDb id is Rose's, an episode of TMDb's series 777, which tv holds",
                    basis: .duplicate
                )
        )
        #expect(
            suggestions[film.id]
                == AdminConsole.SpecialSuggestion(
                    placement: nil,
                    reason: "its TVDB id is Doctor Who's, TMDb's movie 1234, which no library holds: draft it first",
                    basis: .duplicate
                )
        )
        #expect(
            suggestions[unheld.id]
                == AdminConsole.SpecialSuggestion(
                    placement: nil,
                    reason:
                        "its IMDb id is Dalek's, an episode of TMDb's series 778, which no library holds: draft it first",
                    basis: .duplicate
                )
        )
    }

    /// A special placed in a breakout the library holds already adds an entry to it, one in a container
    /// of its own is a child, and one as an extra is an extra; all made with the tree.
    @Test func specialsArePlacedInAHeldBreakoutAContainerOfTheirOwnAndTheExtras() async throws {
        let (database, folder) = Self.clone()
        defer { try? FileManager.default.removeItem(at: folder) }
        var sofa = Container(id: ContainerID("00000000000000c1")!, type: .series, title: Title("Behind the Sofa")!)
        sofa.sequences = [Sequence(id: "episodes", items: [])]
        let held = HeldLibrary([sofa])
        let (console, home) = try await Self.smddbConsole(held)
        var tmdb = FakeTMDb()
        tmdb.series[904] = TMDb.Series(
            id: 904,
            name: "Doctor Who",
            seasons: [.init(id: 90, number: 0, name: "Specials"), .init(id: 91, number: 1, name: "Series 2")]
        )
        let pilot = Self.episode(4301, 1, 1, "New Earth")
        let onTheSofa = Self.episode(4401, 0, 1, "Behind the Sofa: New Earth", runtime: 40)
        let invasion = Self.episode(4402, 0, 2, "The Christmas Invasion", runtime: 60)
        let bloopers = Self.episode(4403, 0, 3, "Bloopers", runtime: 40)
        tmdb.seasons["904/1"] = TMDb.Season(id: 91, number: 1, name: "Series 2", episodes: [pilot])
        tmdb.seasons["904/0"] = TMDb.Season(
            id: 90,
            number: 0,
            name: "Specials",
            episodes: [onTheSofa, invasion, bloopers]
        )
        guard
            case .draft(var tree) = try await console.startDraft(
                of: TMDb.Record(.series, 904),
                into: "tv",
                of: home,
                from: database,
                tmdb: tmdb
            )
        else {
            Issue.record("the series is drafted")
            return
        }
        let season = try #require(tree.containers.last).id.value
        let ownID = try await database.provisionalID()
        tree.place(onTheSofa.id, .breakout(sofa.id.value, from: season, asExtra: false))
        tree.place(invasion.id, .child(of: tree.top, id: ownID.value, type: ContainerType.episode.rawValue))
        tree.place(bloopers.id, .extra(of: season, type: EntryType.featurette.rawValue))
        #expect(tree.making.described.last == "add an entry to \(sofa.id) in tv")

        guard case .created = try await console.create(tree, of: home) else {
            Issue.record("the series is made with its placed specials")
            return
        }
        let entryID = ItemID("\(Slug.make(from: onTheSofa.title))-\(onTheSofa.id)")!
        let madeSofa = try #require(held.container(sofa.id))
        #expect(madeSofa.sequences.flatMap(\.items).map(\.id) == [entryID])
        #expect(madeSofa.sequences.flatMap(\.items).map(\.externalRefs) == [[onTheSofa.ref]])
        let madeSeason = try #require(held.container(ContainerID(season)!))
        #expect(
            madeSeason.sequences.flatMap(\.items).compactMap(\.reference) == [
                EntryRef(container: sofa.id, item: entryID)
            ]
        )
        #expect(madeSeason.extras.map(\.externalRefs) == [[bloopers.ref]])
        #expect(held.container(ContainerID(tree.top)!)?.childContainerIDs.contains(ownID) == true)
        let own = try #require(held.container(ownID))
        #expect(own.type == .episode && own.title == Title("The Christmas Invasion")!)
        #expect(own.sequences.flatMap(\.items).map(\.externalRefs) == [[invasion.ref]])
    }

    /// The silo's dry run says what it makes of a tree with no parent, and a refusal keeps the draft.
    @Test func aTreeTheSiloRefusesIsKept() async throws {
        let (database, folder) = Self.clone()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (console, home) = try await Self.smddbConsole(HeldLibrary())
        let tmdb = FakeTMDb(movies: [348: Self.alienRecord, 349: TMDb.Movie(id: 349, title: "Refused")])
        guard
            case .draft(let alien) = try await console.startDraft(
                of: TMDb.Record(.movie, 348),
                into: "tv",
                of: home,
                from: database,
                tmdb: tmdb
            ),
            case .draft(let refused) = try await console.startDraft(
                of: TMDb.Record(.movie, 349),
                into: "tv",
                of: home,
                from: database,
                tmdb: tmdb
            )
        else {
            Issue.record("both films are drafted")
            return
        }
        guard case .wouldWrite = try await console.check(alien, of: home) else {
            Issue.record("the silo would make the film")
            return
        }
        guard case .refused(let findings) = try await console.check(refused, of: home) else {
            Issue.record("the silo's validator refuses the other")
            return
        }
        #expect(findings.findings.map(\.text).contains { $0.contains("the validator refuses it") })
        guard case .refused = try await console.create(refused, of: home) else {
            Issue.record("the making is refused")
            return
        }
        #expect(console.tmdbDrafts.drafts(of: home.id).map(\.id).contains(refused.id), "a refusal keeps the draft")
    }

    /// A tree's containers are edited, their attributions pruned with the outline or removed alone, and
    /// one dropped with everything beneath it; the top is not dropped.
    @Test func aTreesContainersAreEditedAndDropped() throws {
        var season = Container(
            id: ContainerID("00000000000000d2")!,
            type: .season,
            title: Title("Season 1")!,
            outline: "The first."
        )
        season.sequences = [Sequence(id: "episodes", items: [])]
        var series = Container(id: ContainerID("00000000000000d1")!, type: .series, title: Title("Doctor Who")!)
        series.outline = "A time traveller."
        series.sequences = [
            Sequence(id: "seasons", items: [.child(Entry.Child(id: ItemID("one")!, container: season.id))])
        ]
        let attributed = [Attribution(subject: .outline, provider: .tmdb, value: "1")]
        var tree = TMDbTree(
            library: "tv",
            record: TMDb.Record(.series, 1),
            creating: ContainerDraft.Creating(),
            containers: [series, season],
            top: series.id,
            attributions: [series.id: attributed, season.id: attributed]
        )

        var renamed = series
        renamed.title = Title("Doctor Who (Classic)")!
        tree.set(renamed)
        #expect(tree.title == renamed.displayTitle && tree.attributions[series.id.value] == attributed)
        var bare = season
        bare.outline = nil
        tree.set(bare)
        #expect(tree.attributions[season.id.value] == [], "the outline gone takes its attribution")
        tree.removeAttribution(of: .outline, from: series.id.value)
        #expect(tree.attributions[series.id.value] == [])

        let documents = tree.documents
        tree.set(Container(id: ContainerID("00000000000000d9")!, type: .season, title: Title("Elsewhere")!))
        #expect(tree.documents == documents, "a container the tree does not hold is not set")
        let breakout = Container(id: ContainerID("00000000000000d3")!, type: .series, title: Title("Confidential")!)
        tree.place(1, .breakout(breakout.id.value, from: season.id.value, asExtra: true), breakout: breakout)
        var retitled = breakout
        retitled.title = Title("Doctor Who Confidential")!
        tree.set(retitled)
        #expect(tree.container(breakout.id.value)?.title == retitled.title)

        tree.drop(series.id.value)
        #expect(tree.containers.count == 2, "the top stays")
        tree.drop(season.id.value)
        #expect(tree.containers.map(\.id) == [series.id])
        #expect(tree.container(series.id.value)?.childContainerIDs == [])
        #expect(tree.attributions[season.id.value] == nil)
    }

    /// The drafts from TMDb are kept in a file, read again by the next store, and removed one by one or
    /// all of a silo's at once.
    @Test func draftsFromTMDbAreKeptInAFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("tmdb-drafts-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("drafts.json")
        let film = Container(id: ContainerID("00000000000000e1")!, type: .movie, title: Title("Alien")!)
        let tree = TMDbTree(
            library: "tv",
            record: TMDb.Record(.movie, 348),
            creating: ContainerDraft.Creating(),
            containers: [film],
            top: film.id
        )
        let store = TMDbDraftStore(file: file)
        try store.save(tree, for: "home")
        let read = TMDbDraftStore(file: file).drafts(of: "home")
        #expect(read.map(\.id) == [tree.id] && read.map(\.documents) == [tree.documents], "to the second it was edited")
        try store.remove(tree.id, of: "home")
        #expect(TMDbDraftStore(file: file).drafts(of: "home").isEmpty)
        try store.save(tree, for: "home")
        try store.removeAll(of: "home")
        try store.removeAll(of: "home")
        #expect(TMDbDraftStore(file: file).drafts(of: "home").isEmpty)
    }

    /// An alternative's outline is attributed as the container's is: pruned with it, lost when smddb's
    /// differs, and given smddb's value in a contribution; a draft kept before attributions reads with
    /// none; and a new container's attributions are made with it.
    @Test func anAlternativesOutlineIsAttributedAsTheContainersIs() async throws {
        let (database, folder) = Self.clone()
        defer { try? FileManager.default.removeItem(at: folder) }
        let held = HeldLibrary()
        let (console, home) = try await Self.smddbConsole(held)
        let subject = Attribution.Subject.outline(ofAlternative: "uk")
        let attribution = Attribution(subject: subject, provider: .tmdb, value: "348")
        let artwork = Attribution(
            subject: Attribution.Subject(rawValue: "artwork:poster"),
            provider: .tmdb,
            value: "/a.jpg"
        )
        var alien = Container(id: ContainerID("00000000000000f1")!, type: .movie, title: Title("Alien")!)
        alien.alternatives = [Alternative(id: "uk", sequence: "main", outline: "TMDb's words")]
        #expect(ContainerDraft.pruned([attribution, artwork], for: alien) == [attribution, artwork])
        var unoutlined = alien
        unoutlined.alternatives[0].outline = nil
        #expect(ContainerDraft.pruned([attribution, artwork], for: unoutlined) == [artwork])

        var record = alien
        record.alternatives[0].outline = "smddb's words"
        let (contributed, leftOut) = AdminConsole.contributable(
            Sidecar(container: alien, attributions: [attribution]),
            record: record
        )
        #expect(contributed.alternatives[0].outline == "smddb's words" && leftOut == [attribution])

        var draft = try await console.newContainer(
            .movie,
            titled: Title("Alien")!,
            in: "tv",
            at: ContainerDraft.Creating(),
            of: home,
            from: database
        )
        var made = try #require(draft.value)
        made.alternatives = alien.alternatives
        draft.set(made)
        draft.attributions = [attribution]
        var same = draft
        var differing = draft
        same.take(made)
        #expect(same.attributions == [attribution], "smddb's reads the same")
        var smddbs = made
        smddbs.alternatives[0].outline = "smddb's words"
        differing.take(smddbs)
        #expect(differing.attributions.isEmpty)

        var kept = try JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as! [String: Any]
        kept["attributions"] = nil
        kept["baseAttributions"] = nil
        let old = try JSONDecoder().decode(ContainerDraft.self, from: JSONSerialization.data(withJSONObject: kept))
        #expect(old.id == draft.id && old.text == draft.text && old.attributions.isEmpty)

        guard case .created = try await console.create(draft, of: home) else {
            Issue.record("the film is made")
            return
        }
        #expect(held.sidecar(ContainerID(draft.container)!)?.attributions == [attribution])
    }
}

// MARK: - Differences from TMDb

extension AdminConsoleTests {
    /// A held season, a serial and a breakout read against TMDb: an episode TMDb has gained is offered
    /// at its place and taken alone; an extra TMDb lacks is shown and offered for nothing; an entry's
    /// missing id is listed against it, through the season above a serial and through TMDb's lookup for
    /// a breakout; regrouped episodes are neither missing nor out of order; and a series' specials are
    /// covered wherever they were filed or declined, a gained one listed as unassigned.
    @Test func aHeldContainersDifferencesFromTMDbAreTakenOrLeft() async throws {
        let (database, folder) = Self.clone()
        defer { try? FileManager.default.removeItem(at: folder) }
        let one = Self.episode(1001, 14, 1, "Part One")
        let two = Self.episode(1002, 14, 2, "Part Two")
        let three = Self.episode(1003, 14, 3, "Part Three")
        func entry(_ id: String, _ episode: TMDb.Episode) -> Entry {
            .leaf(Entry.Leaf(id: ItemID(id)!, type: .episode, externalRefs: [episode.ref]))
        }
        var season = Container(
            id: ContainerID("00000000000000a2")!,
            type: .season,
            title: Title("Season 14")!,
            year: 1976,
            externalRefs: [ExternalRef(provider: .tmdb, value: "3644")]
        )
        season.sequences = [Sequence(id: "episodes", items: [entry("part-one", one), entry("part-three", three)])]
        season.extras = [.leaf(Entry.Leaf(id: ItemID("making-of")!, type: .behindTheScenes, title: "The Making Of"))]
        var series = Container(
            id: ContainerID("00000000000000a1")!,
            type: .series,
            title: Title("Doctor Who")!,
            externalRefs: [ExternalRef(provider: .tmdb, value: "121")]
        )
        series.sequences = [
            Sequence(id: "seasons", items: [.child(Entry.Child(id: ItemID("s14")!, container: season.id))])
        ]
        let held = HeldLibrary([series, season])
        let (console, home) = try await Self.smddbConsole(held)
        var tmdb = FakeTMDb()
        tmdb.series[121] = TMDb.Series(
            id: 121,
            name: "Doctor Who",
            seasons: [.init(id: 50, number: 0, name: "Specials"), .init(id: 3644, number: 14, name: "Season 14")]
        )
        tmdb.seasons["121/14"] = TMDb.Season(
            id: 3644,
            number: 14,
            name: "Season 14",
            year: 1976,
            episodes: [one, two, three]
        )
        tmdb.episodeIDs[1001] = TMDb.ExternalIDs(imdb: "tt0001001")

        let compared = try await console.compare(season.id.value, in: "tv", of: home, from: database, tmdb: tmdb)
        #expect(compared.reading == "Season 14 of TMDb's series 121")
        #expect(compared.differences.contains(.episode(two, after: one.ref)))
        #expect(
            compared.differences.contains(
                .reference(item: "part-one", ExternalRef(provider: .imdb, value: "tt0001001"))
            )
        )
        #expect(!compared.differences.contains { if case .order = $0 { true } else { false } })
        #expect(compared.heldOnly == ["making-of: The Making Of"], "shown, and offered for nothing")
        let walking = Walking(console: console, home: home, database: database, tmdb: tmdb)
        let walk = try await walking.walk(season.id.value, choosing: ["episode:1002"])
        let plan = try walk.plan()
        let draft = try #require(Self.edit(of: season.id.value, in: plan))
        #expect(draft.value?.sequences[0].items.map(\.externalRefs) == [[one.ref], [two.ref], [three.ref]])
        #expect(
            draft.value?.extras == season.extras && draft.value?.externalRefs == season.externalRefs,
            "nothing else"
        )
        #expect(plan.steps.count == 1, "the season's edit and nothing else")
        let stored = try await console.store(walk, of: home, tmdb: tmdb)
        #expect(stored.refusal == nil && stored.rest.isEmpty)
        #expect(
            held.container(season.id)?.sequences[0].items.map(\.externalRefs) == [[one.ref], [two.ref], [three.ref]]
        )

        // The same season with its episodes regrouped into a serial beneath it, which carries no TMDb
        // id of its own and is read through the season.
        var serial = Container(id: ContainerID("00000000000000a3")!, type: .serial, title: Title("The Hand of Fear")!)
        serial.sequences = [
            Sequence(id: "parts", items: [entry("part-one", one), entry("part-two", two), entry("part-three", three)])
        ]
        var regrouped = season
        regrouped.sequences = [
            Sequence(id: "stories", items: [.child(Entry.Child(id: ItemID("hand")!, container: serial.id))])
        ]
        regrouped.extras = []
        held.sidecars.withLock {
            $0[regrouped.id.value] = try! SidecarFile.data(for: Sidecar(container: regrouped))
            $0[serial.id.value] = try! SidecarFile.data(for: Sidecar(container: serial))
        }
        let whole = try await console.compare(regrouped.id.value, in: "tv", of: home, from: database, tmdb: tmdb)
        #expect(!whole.differences.contains { if case .episode = $0 { true } else { false } }, "none is missing")
        #expect(!whole.differences.contains { if case .order = $0 { true } else { false } })
        let parts = try await console.compare(serial.id.value, in: "tv", of: home, from: database, tmdb: tmdb)
        #expect(parts.reading.hasPrefix("through Season 14"))
        #expect(parts.differences == [.reference(item: "part-one", ExternalRef(provider: .imdb, value: "tt0001001"))])

        // The series' specials: one in a breakout, one at a film's home, one declined, one gained.
        let sofa = Self.episode(3002, 0, 2, "Behind the Sofa: The Hand of Fear", runtime: 40)
        let day = Self.episode(3003, 0, 3, "The Day of the Doctor", runtime: 77)
        let declinedTrailer = Self.episode(3004, 0, 4, "Season 14 Trailer", runtime: 2)
        let gained = Self.episode(3005, 0, 5, "Season 15 Trailer", runtime: 2)
        tmdb.seasons["121/0"] = TMDb.Season(
            id: 50,
            number: 0,
            name: "Specials",
            episodes: [sofa, day, declinedTrailer, gained]
        )
        var breakout = Container(
            id: ContainerID("00000000000000a4")!,
            type: .series,
            title: Title("Behind the Sofa")!,
            listed: false
        )
        breakout.sequences = [
            Sequence(
                id: "episodes",
                items: [
                    .leaf(
                        Entry.Leaf(
                            id: ItemID("hand")!,
                            type: .episode,
                            externalRefs: [sofa.ref, ExternalRef(provider: .imdb, value: "tt0003002")]
                        )
                    )
                ]
            )
        ]
        var film = Container(id: ContainerID("00000000000000a5")!, type: .movie, title: Title("The Day of the Doctor")!)
        film.sequences = [
            Sequence(
                id: "main",
                items: [.leaf(Entry.Leaf(id: ItemID("feature")!, type: .movie, externalRefs: [day.ref]))]
            )
        ]
        held.sidecars.withLock { $0[breakout.id.value] = try! SidecarFile.data(for: Sidecar(container: breakout)) }
        held.file(Sidecar(container: film), in: "films")
        held.sidecars.withLock {
            $0[series.id.value] = try! SidecarFile.data(
                for: Sidecar(container: series, declined: [declinedTrailer.ref])
            )
        }
        let specials = try await console.compare(series.id.value, in: "tv", of: home, from: database, tmdb: tmdb)
        let unassigned = specials.differences.compactMap {
            if case .special(let special) = $0 { special.id } else { nil }
        }
        #expect(unassigned == [gained.id], "a special filed anywhere, or declined, is covered")
        #expect(specials.declined.map(\.id) == [declinedTrailer.id])
        #expect(specials.suggestions[gained.id]?.placement == .declined)
        #expect(!specials.differences.contains { if case .episode = $0 { true } else { false } })

        // The breakout, beneath nothing TMDb knows, read through the series its entry's IMDb id leads to.
        tmdb.found["imdb:tt0003002"] = TMDb.Found(episodes: [(series: 121, episode: sofa)])
        tmdb.episodeIDs[3002] = TMDb.ExternalIDs(imdb: "tt0003002", tvdb: "30002")
        let through = try await console.compare(breakout.id.value, in: "tv", of: home, from: database, tmdb: tmdb)
        #expect(through.reading == "through TMDb's series 121, which its entries are episodes of")
        #expect(through.differences == [.reference(item: "hand", ExternalRef(provider: .tvdb, value: "30002"))])
    }

    /// TMDb's poster for a film the library holds is offered for the kind the folder lacks and put with
    /// its attribution; an image of the operator's own put over it carries none.
    @Test func artworkIsTakenFromTMDbWithItsAttribution() async throws {
        let (database, folder) = Self.clone()
        defer { try? FileManager.default.removeItem(at: folder) }
        var alien = Container(
            id: ContainerID("00000000000000b1")!,
            type: .movie,
            title: Title("Alien")!,
            year: 1979,
            externalRefs: [ExternalRef(provider: .tmdb, value: "348")]
        )
        alien.sequences = [Sequence(id: "main", items: [.leaf(Entry.Leaf(id: ItemID("feature")!, type: .movie))])]
        let held = HeldLibrary()
        held.file(Sidecar(container: alien), in: "films")
        let (console, home) = try await Self.smddbConsole(held)
        var tmdb = FakeTMDb(movies: [348: TMDb.Movie(id: 348, title: "Alien", year: 1979)])
        tmdb.images[TMDb.Record(.movie, 348)] = TMDb.Images(posters: ["/poster.jpg"], backdrops: ["/backdrop.jpg"])

        let compared = try await console.compare(alien.id.value, in: "films", of: home, from: database, tmdb: tmdb)
        #expect(
            compared.differences == [
                .artwork(kind: "poster", path: "/poster.jpg", record: TMDb.Record(.movie, 348)),
                .artwork(kind: "fanart", path: "/backdrop.jpg", record: TMDb.Record(.movie, 348)),
            ]
        )
        let walking = Walking(console: console, home: home, database: database, tmdb: tmdb, library: "films")
        let walk = try await walking.walk(alien.id.value, choosing: ["artwork:poster"])
        #expect(
            try walk.plan().steps.map(\.described) == ["put TMDb's poster on \(alien.displayTitle), credited to TMDb"],
            "artwork changes no field"
        )
        #expect(try await console.store(walk, of: home, tmdb: tmdb).refusal == nil)
        #expect(
            held.sidecar(alien.id)?.attributions == [
                Attribution(subject: .artwork("poster"), provider: .tmdb, value: "348")
            ]
        )

        try await console.putArtwork(FakeTMDb.jpeg, as: "poster", of: alien.id.value, in: "films", on: home)
        #expect(held.sidecar(alien.id)?.attributions.isEmpty == true, "the operator's own image is credited to no one")
    }

    /// A film's and a collection's own fields that TMDb says otherwise, and the ids it holds that the
    /// film lacks, are offered; taken, they are one edit draft, the outline attributed to the record.
    @Test func aFilmsAndACollectionsFieldsAreTakenFromTMDb() async throws {
        let (database, folder) = Self.clone()
        defer { try? FileManager.default.removeItem(at: folder) }
        var film = Container(
            id: ContainerID("00000000000000c1")!,
            type: .movie,
            title: Title("Alien (1979 cut)")!,
            externalRefs: [ExternalRef(provider: .tmdb, value: "348")]
        )
        film.sequences = [Sequence(id: "main", items: [.leaf(Entry.Leaf(id: ItemID("feature")!, type: .movie))])]
        let collection = Container(
            id: ContainerID("00000000000000c2")!,
            type: .collection,
            title: Title("Alien Films")!,
            externalRefs: [ExternalRef(provider: .tmdb, value: "8091")]
        )
        let held = HeldLibrary()
        held.file(Sidecar(container: film), in: "films")
        held.file(Sidecar(container: collection), in: "films")
        let (console, home) = try await Self.smddbConsole(held)
        var tmdb = FakeTMDb(movies: [348: Self.alienRecord])
        tmdb.collections[8091] = TMDb.Collection(id: 8091, name: "Alien Collection", overview: "Ripley.", parts: [])

        let compared = try await console.compare(film.id.value, in: "films", of: home, from: database, tmdb: tmdb)
        #expect(compared.reading == "TMDb's movie 348")
        let imdb = ExternalRef(provider: .imdb, value: "tt0078748")
        #expect(
            compared.differences == [
                .title("Alien"), .year(1979), .outline("In space no one can hear you scream.", record: "348"),
                .reference(item: nil, imdb), .reference(item: nil, ExternalRef(provider: .wikidata, value: "Q103569")),
            ]
        )
        let walking = Walking(console: console, home: home, database: database, tmdb: tmdb, library: "films")
        let walk = try await walking.walk(film.id.value, choosing: ["title", "year", "outline", "ref::imdb:tt0078748"])
        let draft = try #require(Self.edit(of: film.id.value, in: try walk.plan()))
        let taken = try #require(draft.value)
        #expect(taken.title == Title("Alien")! && taken.year == 1979 && taken.outline == Self.alienRecord.overview)
        #expect(taken.externalRefs == film.externalRefs + [imdb], "the id left is not taken")
        #expect(draft.attributions == [Attribution(subject: .outline, provider: .tmdb, value: "348")])
        #expect(try await console.store(walk, of: home, tmdb: tmdb).refusal == nil, "the edit is stored")
        #expect(held.sidecar(film.id)?.attributions == draft.attributions)

        let set = try await console.compare(collection.id.value, in: "films", of: home, from: database, tmdb: tmdb)
        #expect(set.reading == "TMDb's collection 8091")
        #expect(set.differences == [.title("Alien Collection"), .outline("Ripley.", record: "8091")])
    }

    /// A season TMDb's series above it does not hold, or with no series above it, cannot be read, nor can
    /// a container with no TMDb id anywhere; one beneath a series is read against its specials, its items'
    /// order and missing ids taken from TMDb's; and a missing episode TMDb has nothing before goes last.
    @Test func aComparisonSaysWhyItCannotReadAContainer() async throws {
        let (database, folder) = Self.clone()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = Self.episode(3101, 0, 1, "The Five Doctors", runtime: 90)
        let second = Self.episode(3102, 0, 2, "Dimensions in Time", runtime: 15)
        func entry(_ id: String, _ episode: TMDb.Episode) -> Entry {
            .leaf(Entry.Leaf(id: ItemID(id)!, type: .episode, externalRefs: [episode.ref]))
        }
        let unknown = Container(
            id: ContainerID("00000000000000d4")!,
            type: .season,
            title: Title("Season 30")!,
            externalRefs: [ExternalRef(provider: .tmdb, value: "9999")]
        )
        var anniversaries = Container(
            id: ContainerID("00000000000000d5")!,
            type: .serial,
            title: Title("Anniversaries")!
        )
        anniversaries.sequences = [Sequence(id: "parts", items: [entry("dimensions", second), entry("five", first)])]
        var arc = Container(id: ContainerID("00000000000000d3")!, type: .arc, title: Title("The Specials")!)
        arc.sequences = [
            Sequence(
                id: "parts",
                items: [
                    .child(Entry.Child(id: ItemID("unknown")!, container: unknown.id)),
                    .child(Entry.Child(id: ItemID("anniversaries")!, container: anniversaries.id)),
                ]
            )
        ]
        var series = Container(
            id: ContainerID("00000000000000d1")!,
            type: .series,
            title: Title("Doctor Who")!,
            externalRefs: [ExternalRef(provider: .tmdb, value: "121")]
        )
        series.sequences = [
            Sequence(id: "arcs", items: [.child(Entry.Child(id: ItemID("specials")!, container: arc.id))])
        ]
        let orphan = Container(
            id: ContainerID("00000000000000d6")!,
            type: .season,
            title: Title("Season 14")!,
            externalRefs: [ExternalRef(provider: .tmdb, value: "3644")]
        )
        var nothing = Container(id: ContainerID("00000000000000d7")!, type: .serial, title: Title("Shada")!)
        nothing.sequences = [
            Sequence(
                id: "parts",
                items: [
                    .leaf(
                        Entry.Leaf(
                            id: ItemID("one")!,
                            type: .episode,
                            externalRefs: [ExternalRef(provider: .imdb, value: "tt9999999")]
                        )
                    )
                ]
            )
        ]
        var season = Container(
            id: ContainerID("00000000000000d8")!,
            type: .season,
            title: Title("Season 14")!,
            externalRefs: [ExternalRef(provider: .tmdb, value: "3644")]
        )
        let robots = Self.episode(1001, 14, 1, "The Robots of Death")
        let talons = Self.episode(1002, 14, 2, "The Talons of Weng-Chiang")
        season.sequences = [Sequence(id: "episodes", items: [entry("talons", talons)])]
        series.sequences.append(
            Sequence(id: "seasons", items: [.child(Entry.Child(id: ItemID("s14")!, container: season.id))])
        )
        let held = HeldLibrary([series, arc, unknown, anniversaries, orphan, nothing, season])
        let (console, home) = try await Self.smddbConsole(held)
        var tmdb = FakeTMDb()
        tmdb.series[121] = TMDb.Series(
            id: 121,
            name: "Doctor Who",
            seasons: [.init(id: 50, number: 0, name: "Specials"), .init(id: 3644, number: 14, name: "Season 14")]
        )
        tmdb.seasons["121/0"] = TMDb.Season(id: 50, number: 0, name: "Specials", episodes: [first, second])
        tmdb.seasons["121/14"] = TMDb.Season(id: 3644, number: 14, name: "Season 14", episodes: [robots, talons])
        tmdb.episodeIDs[first.id] = TMDb.ExternalIDs(imdb: "tt0085213")

        let reasons = [
            (unknown, "TMDb's series 121 has no season 9999"),
            (orphan, "the season carries TMDb's id, but no series above it does"),
            (
                nothing,
                "Shada carries no TMDb id, nothing above it does, and none of its items has an id TMDb can find"
            ),
        ]
        for (container, reason) in reasons {
            let error = await #expect(throws: AdminConsole.NoTMDbReading.self) {
                try await console.compare(container.id.value, in: "tv", of: home, from: database, tmdb: tmdb)
            }
            #expect(error?.reason == reason)
        }

        let compared = try await console.compare(
            anniversaries.id.value,
            in: "tv",
            of: home,
            from: database,
            tmdb: tmdb
        )
        #expect(compared.reading == "through Doctor Who, TMDb's series 121")
        let imdb = ExternalRef(provider: .imdb, value: "tt0085213")
        #expect(
            compared.differences == [
                .reference(item: "five", imdb), .order(sequence: "parts", items: ["five", "dimensions"]),
            ]
        )
        let walking = Walking(console: console, home: home, database: database, tmdb: tmdb)
        let walk = try await walking.walk(anniversaries.id.value, choosing: Set(compared.differences.map(\.id)))
        let taken = try #require(Self.edit(of: anniversaries.id.value, in: try walk.plan())?.value)
        #expect(taken.sequences[0].items.map(\.id?.value) == ["five", "dimensions"])
        #expect(taken.sequences[0].items[0].externalRefs == [first.ref, imdb])

        let fourteen = try await console.compare(season.id.value, in: "tv", of: home, from: database, tmdb: tmdb)
        #expect(fourteen.differences == [.episode(robots, after: nil)])
        let gained = try await walking.walk(season.id.value, choosing: ["episode:1001"])
        #expect(
            Self.edit(of: season.id.value, in: try gained.plan())?.value?.sequences[0].items.map(\.externalRefs)
                == [[talons.ref], [robots.ref]],
            "with nothing before it at TMDb, last"
        )
    }

    /// A held series read against TMDb says each step as it goes, counting what each step asks, and lists
    /// the specials nothing covers before their suggestions are read; what it ends with is what it told.
    @Test func aComparisonSaysEachStepAsItGoesWithWhatItHasFound() async throws {
        let (database, folder) = Self.clone()
        defer { try? FileManager.default.removeItem(at: folder) }
        let specials = (0..<9).map { Self.episode(3300 + $0, 0, $0 + 1, "Special \($0 + 1)", runtime: 40) }
        var series = Container(
            id: ContainerID("00000000000000f1")!,
            type: .series,
            title: Title("Doctor Who")!,
            externalRefs: [ExternalRef(provider: .tmdb, value: "121")]
        )
        series.sequences = [Sequence(id: "seasons", items: [])]
        let (console, home) = try await Self.smddbConsole(HeldLibrary([series]))
        var tmdb = FakeTMDb()
        tmdb.series[121] = TMDb.Series(
            id: 121,
            name: "Doctor Who",
            year: 1963,
            seasons: [
                .init(id: 50, number: 0, name: "Specials"), .init(id: 3644, number: 14, name: "Season 14"),
                .init(id: 3645, number: 15, name: "Season 15"),
            ]
        )
        tmdb.seasons["121/0"] = TMDb.Season(id: 50, number: 0, name: "Specials", episodes: specials)
        let told = Mutex<[(AdminConsole.TMDbProgress, AdminConsole.TMDbComparison)]>([])
        let compared = try await console.compare(
            series.id.value,
            in: "tv",
            of: home,
            from: database,
            tmdb: tmdb,
            progress: { step, found in told.withLock { $0.append((step, found)) } }
        )
        let steps = told.withLock { $0 }
        var said: [String] = []
        for (step, _) in steps where said.last != step.step { said.append(step.step) }
        #expect(
            said == [
                "Reading TMDb", "Looking for TMDb's seasons in the library", "Reading TMDb's artwork",
                "Reading TMDb's specials", "Looking for TMDb's specials in the library",
                "Suggesting where the specials go",
            ]
        )
        let counted = [
            "Looking for TMDb's seasons in the library": 2, "Looking for TMDb's specials in the library": 9,
            "Suggesting where the specials go": 9,
        ]
        for (step, total) in counted {
            let told = steps.filter { $0.0.step == step }.map(\.0)
            #expect(told.map(\.done) == Array(0...total) && told.allSatisfy { $0.total == total }, "\(step)")
        }
        func unassigned(_ comparison: AdminConsole.TMDbComparison) -> [Int] {
            comparison.differences.compactMap { if case .special(let special) = $0 { special.id } else { nil } }
        }
        let suggesting = steps.filter { $0.0.step == "Suggesting where the specials go" }.map(\.1)
        #expect(
            suggesting.allSatisfy { unassigned($0) == specials.map(\.id) && $0.suggestions.isEmpty },
            "listed while their suggestions are read"
        )
        #expect(unassigned(compared) == specials.map(\.id))
        #expect(compared.differences.filter { if case .season = $0 { true } else { false } }.count == 2)
    }

    /// A long series' questions are asked of TMDb several at once, and never more at once than TMDb's
    /// rate allows for.
    @Test func aComparisonAsksTMDbSeveralQuestionsAtOnce() async throws {
        let (database, folder) = Self.clone()
        defer { try? FileManager.default.removeItem(at: folder) }
        let specials = (0..<20).map { Self.episode(3400 + $0, 0, $0 + 1, "Special \($0 + 1)") }
        var series = Container(
            id: ContainerID("00000000000000f2")!,
            type: .series,
            title: Title("Doctor Who")!,
            externalRefs: [ExternalRef(provider: .tmdb, value: "121")]
        )
        series.sequences = [Sequence(id: "seasons", items: [])]
        let (console, home) = try await Self.smddbConsole(HeldLibrary([series]))
        var tmdb = FakeTMDb()
        tmdb.series[121] = TMDb.Series(
            id: 121,
            name: "Doctor Who",
            seasons: [.init(id: 50, number: 0, name: "Specials")]
        )
        tmdb.seasons["121/0"] = TMDb.Season(id: 50, number: 0, name: "Specials", episodes: specials)
        let asking = FakeTMDb.Asking()
        tmdb.asking = asking
        let compared = try await console.compare(series.id.value, in: "tv", of: home, from: database, tmdb: tmdb)
        #expect(compared.differences.count == 20)
        #expect(asking.most > 1 && asking.most <= 6, "\(asking.most) at once")
    }

    /// A held series' specials nothing covers are taken into every placement, here and in the
    /// containers the library holds, with a declined one placed after all losing its decline; the
    /// series' own fields, its missing id, and a season it lacks are taken with them.
    @Test func aHeldSeriesSpecialsAreTakenIntoEveryPlacement() async throws {
        let (database, folder) = Self.clone()
        defer { try? FileManager.default.removeItem(at: folder) }
        let specials = (0..<11).map { Self.episode(3200 + $0, 0, $0 + 1, "Special \($0 + 1)", runtime: 40) }
        let (here, there, extraHere, extraThere, own, duplicateHere, duplicateThere) = (
            specials[0], specials[1], specials[2], specials[3], specials[4], specials[5], specials[6]
        )
        let (newBreakout, heldBreakout, declined, undeclined) = (specials[7], specials[8], specials[9], specials[10])
        var season = Container(
            id: ContainerID("00000000000000e2")!,
            type: .season,
            title: Title("Season 14")!,
            externalRefs: [ExternalRef(provider: .tmdb, value: "3644")]
        )
        season.sequences = [Sequence(id: "episodes", items: [])]
        var series = Container(
            id: ContainerID("00000000000000e1")!,
            type: .series,
            title: Title("Doctor Who")!,
            externalRefs: [ExternalRef(provider: .tmdb, value: "121")]
        )
        series.sequences = [
            Sequence(id: "seasons", items: [.child(Entry.Child(id: ItemID("s14")!, container: season.id))])
        ]
        var sofa = Container(id: ContainerID("00000000000000e3")!, type: .series, title: Title("Behind the Sofa")!)
        sofa.sequences = [Sequence(id: "episodes", items: [])]
        var film = Container(id: ContainerID("00000000000000e4")!, type: .movie, title: Title("The Five Doctors")!)
        film.sequences = [Sequence(id: "main", items: [.leaf(Entry.Leaf(id: ItemID("feature")!, type: .movie))])]
        let held = HeldLibrary([season, sofa])
        held.sidecars.withLock {
            $0[series.id.value] = try! SidecarFile.data(for: Sidecar(container: series, declined: [undeclined.ref]))
        }
        held.file(Sidecar(container: film), in: "films")
        let (console, home) = try await Self.smddbConsole(held)
        var tmdb = FakeTMDb()
        tmdb.series[121] = TMDb.Series(
            id: 121,
            name: "Doctor Who",
            year: 1963,
            overview: "A time traveller.",
            seasons: [
                .init(id: 50, number: 0, name: "Specials"), .init(id: 3644, number: 14, name: "Season 14"),
                .init(id: 3645, number: 15, name: "Season 15"),
            ],
            externalIDs: TMDb.ExternalIDs(tvdb: "76107")
        )
        tmdb.seasons["121/0"] = TMDb.Season(id: 50, number: 0, name: "Specials", episodes: specials)
        tmdb.seasons["121/14"] = TMDb.Season(id: 3644, number: 14, name: "Season 14", episodes: [])
        let walking = Walking(console: console, home: home, database: database, tmdb: tmdb)

        var walk = try await console.startWalk(at: series.id.value, in: "tv", of: home)
        try await walking.read(series.id.value, in: &walk)
        let compared = try #require(walk.stops[series.id.value]?.comparison)
        #expect(walk.declined.map(\.id) == [undeclined.id])
        #expect(walk.unassigned.map(\.id) == specials.dropLast().map(\.id), "beside every stop, not the series' own")
        #expect(compared.differences.contains(.season(.init(id: 3645, number: 15, name: "Season 15"))))
        #expect(!compared.differences.contains { $0.id == "season:3644" }, "the season the library holds")
        let confidential = Container(
            id: try await database.provisionalID(),
            type: .series,
            title: Title("Confidential")!,
            listed: false
        )
        let ownID = try await database.provisionalID()
        let home14 = season.id.value
        let atTheSeries: [Int: SpecialPlacement] = [
            here.id: .entry(in: series.id.value),
            extraHere.id: .extra(of: series.id.value, type: EntryType.featurette.rawValue),
            own.id: .child(of: series.id.value, id: ownID.value, type: ContainerType.serial.rawValue),
            duplicateHere.id: .duplicate(
                home: film.id.value,
                item: "feature",
                library: "films",
                from: series.id.value,
                asExtra: true
            ),
            declined.id: .declined,
            undeclined.id: .extra(of: series.id.value, type: EntryType.trailer.rawValue),
        ]
        for (special, placement) in atTheSeries { walk.place(special, placement) }
        walk.place(
            newBreakout.id,
            .breakout(confidential.id.value, from: series.id.value, asExtra: true),
            companion: confidential
        )
        try await walking.confirm(
            series.id.value,
            choosing: ["year", "outline", "ref::tvdb:76107", "season:3645"],
            in: &walk
        )
        #expect(walk.next == home14)
        let atTheSeason: [Int: SpecialPlacement] = [
            there.id: .entry(in: home14),
            extraThere.id: .extra(of: home14, type: EntryType.interview.rawValue),
            duplicateThere.id: .duplicate(
                home: film.id.value,
                item: "feature",
                library: "films",
                from: home14,
                asExtra: false
            ),
            heldBreakout.id: .breakout(sofa.id.value, from: home14, asExtra: false),
        ]
        try await walking.read(home14, in: &walk)
        for (special, placement) in atTheSeason { walk.place(special, placement) }
        try await walking.confirm(home14, in: &walk)
        #expect(walk.unassigned.isEmpty && walk.state(of: home14) == .changed)

        let plan = try walk.plan()
        #expect(
            plan.steps.map(\.id).filter { !$0.hasPrefix("held:") } == [
                "create:\(confidential.id)", "edit:\(series.id)", "create:\(ownID)", "edit:\(home14)",
            ],
            "the companion first, then each stop's edit, the series' followed by the container it names"
        )
        #expect(
            plan.steps.filter { $0.id.hasPrefix("held:") }.map(\.described) == [
                "add TMDb's id to feature of \(film.id) in films",
                "add TMDb's id to feature of \(film.id) in films",
                "add an entry to \(sofa.id) in tv",
            ]
        )
        #expect(plan.steps.firstIndex { $0.id.hasPrefix("held:") } == 1, "before the edits that refer to them")
        #expect(plan.seasons.map(\.season.number) == [15], "drafted from TMDb once the walk is stored")
        let draft = try #require(Self.edit(of: series.id.value, in: plan))
        let taken = try #require(draft.value)
        #expect(taken.year == 1963 && taken.outline == "A time traveller.")
        #expect(taken.externalRefs.contains(ExternalRef(provider: .tvdb, value: "76107")))
        #expect(taken.sequences[0].items.map(\.externalRefs) == [[], [here.ref], []])
        #expect(taken.sequences[0].items.last?.childContainer == ownID, "naming the container of its own")
        #expect(
            taken.extras.map(\.type) == [.featurette, nil, nil, .trailer],
            "the extra, the duplicate's and the breakout's refs, and the special placed after all"
        )
        #expect(draft.declined == [declined.ref], "the decline placed after all goes")

        let stored = try await console.store(walk, of: home, tmdb: tmdb)
        #expect(stored.refusal == nil && stored.stored.count == plan.steps.count)
        #expect(held.container(confidential.id)?.sequences.flatMap(\.items).map(\.externalRefs) == [[newBreakout.ref]])
        #expect(held.container(sofa.id)?.sequences.flatMap(\.items).map(\.externalRefs) == [[heldBreakout.ref]])
        #expect(held.container(ownID)?.sequences.flatMap(\.items).map(\.externalRefs) == [[own.ref]])
        let madeSeason = try #require(held.container(season.id))
        #expect(madeSeason.sequences[0].items.map(\.externalRefs) == [[there.ref], [], []])
        #expect(
            madeSeason.sequences[0].items.compactMap(\.reference).map(\.container) == [film.id, sofa.id],
            "referring to the film's item and the breakout's entry"
        )
        #expect(madeSeason.extras.map(\.type) == [.interview] && madeSeason.extras[0].externalRefs == [extraThere.ref])
        #expect(held.container(film.id)?.sequences[0].items[0].externalRefs == [duplicateHere.ref, duplicateThere.ref])
        #expect(held.sidecar(series.id)?.declined == [declined.ref])
    }

    // MARK: Walks

    /// A held series of three seasons, each holding serials, with TMDb's record of each, for walks.
    private static func walkedSeries() -> (
        series: Container, seasons: [Container], serials: [Container], TMDb: FakeTMDb
    ) {
        let serials = (1...4).map { number in
            var serial = Container(
                id: ContainerID(String(format: "%016x", 0x1b0 + number))!,
                type: .serial,
                title: Title("Serial \(number)")!
            )
            serial.sequences = [
                Sequence(
                    id: "parts",
                    items: [
                        .leaf(
                            Entry.Leaf(
                                id: ItemID("part-one")!,
                                type: .episode,
                                externalRefs: [ExternalRef(provider: .tmdb, value: String(5000 + number))]
                            )
                        )
                    ]
                )
            ]
            return serial
        }
        // Held in an order their ids do not sort in, which is the order the walk keeps.
        let seasons = [(3, [serials[3]]), (1, [serials[0], serials[1]]), (2, [serials[2]])].map { number, beneath in
            var season = Container(
                id: ContainerID(String(format: "%016x", 0x1a0 + number))!,
                type: .season,
                title: Title("Season \(number)")!,
                externalRefs: [ExternalRef(provider: .tmdb, value: String(900 + number))]
            )
            season.sequences = [
                Sequence(
                    id: "stories",
                    items: beneath.map {
                        .child(Entry.Child(id: ItemID(Slug.make(from: $0.title.rawValue))!, container: $0.id))
                    }
                )
            ]
            return season
        }
        var series = Container(
            id: ContainerID("00000000000001a0")!,
            type: .series,
            title: Title("Doctor Who")!,
            externalRefs: [ExternalRef(provider: .tmdb, value: "121")]
        )
        series.sequences = [
            Sequence(
                id: "seasons",
                items: seasons.map {
                    .child(Entry.Child(id: ItemID(Slug.make(from: $0.title.rawValue))!, container: $0.id))
                }
            )
        ]
        var tmdb = FakeTMDb()
        tmdb.series[121] = TMDb.Series(
            id: 121,
            name: "Doctor Who",
            seasons: [
                .init(id: 50, number: 0, name: "Specials"), .init(id: 901, number: 1, name: "Season 1"),
                .init(id: 902, number: 2, name: "Season 2"), .init(id: 903, number: 3, name: "Season 3"),
            ]
        )
        tmdb.seasons["121/0"] = TMDb.Season(id: 50, number: 0, name: "Specials", episodes: [])
        for number in 1...3 {
            let episodes = serials.indices.filter {
                seasons[[1, 2, 0][number - 1]].childContainerIDs.contains(serials[$0].id)
            }
            .map { Self.episode(5001 + $0, number, $0 + 1, "Part One") }
            tmdb.seasons["121/\(number)"] = TMDb.Season(
                id: 900 + number,
                number: number,
                name: "Season \(number)",
                episodes: episodes
            )
        }
        return (series, [seasons[1], seasons[2], seasons[0]], serials, tmdb)
    }

    /// Confirming a series with nothing ticked records it as looked at and queues each season the library
    /// holds beneath it, in its sequence's order; confirming a season queues its serials ahead of the next
    /// season, so the walk goes depth first.
    @Test func confirmingAStopQueuesTheContainersBeneathItInTheTreesOrder() async throws {
        let (database, folder) = Self.clone()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (series, seasons, serials, tmdb) = Self.walkedSeries()
        let (console, home) = try await Self.smddbConsole(HeldLibrary([series] + seasons + serials))
        let walking = Walking(console: console, home: home, database: database, tmdb: tmdb)

        var walk = try await console.startWalk(at: series.id.value, in: "tv", of: home)
        #expect(walk.order == [series.id.value] && walk.state(of: series.id.value) == .pending)
        #expect(walk.series == series.id.value)
        try await walking.confirm(series.id.value, in: &walk)
        #expect(walk.state(of: series.id.value) == .lookedAt)
        let held = [seasons[2], seasons[0], seasons[1]].map(\.id.value)
        #expect(walk.order == [series.id.value] + held, "in the order the series' sequence holds them")
        #expect(walk.stops[held[0]]?.title == "Season 3" && walk.stops[held[0]]?.parent == series.id.value)
        #expect(held.allSatisfy { walk.state(of: $0) == .pending && walk.stops[$0]?.comparison == nil })
        #expect(walk.next == held[0], "and none of them read until it is opened")

        try await walking.confirm(held[1], in: &walk)
        #expect(walk.next == held[0])
        try await walking.confirm(held[0], in: &walk)
        #expect(
            walk.order == [series.id.value, held[0], serials[3].id.value, held[1]] + serials[0...1].map(\.id.value) + [
                held[2]
            ]
        )
        #expect(walk.next == serials[3].id.value, "the season's serial before the next season")

        // A stop TMDb never read, confirmed as it is, takes nothing and still queues what is beneath it.
        walk.confirm(held[2], beneath: try await console.stops(beneath: held[2], in: walk, of: home))
        #expect(walk.stops[held[2]]?.comparison == nil && walk.state(of: held[2]) == .lookedAt)
        #expect(walk.order.last == serials[2].id.value)
        #expect(try walk.plan().steps.isEmpty)
    }

    /// A special placed as an entry of a season while the season's stop is open leaves the unassigned,
    /// and is stored in the season's edit carrying its references; the series no longer lists it. A walk
    /// rooted at the season has the series' specials beside it too.
    @Test func aSpecialPlacedAtAStopIsStoredInThatContainersEdit() async throws {
        let (database, folder) = Self.clone()
        defer { try? FileManager.default.removeItem(at: folder) }
        var (series, seasons, serials, tmdb) = Self.walkedSeries()
        let k9 = Self.episode(3501, 0, 1, "K9 and Company", runtime: 50)
        tmdb.seasons["121/0"] = TMDb.Season(id: 50, number: 0, name: "Specials", episodes: [k9])
        let held = HeldLibrary([series] + seasons + serials)
        let (console, home) = try await Self.smddbConsole(held)
        let walking = Walking(console: console, home: home, database: database, tmdb: tmdb)
        let season = seasons[0].id.value

        var walk = try await walking.walk(series.id.value)
        #expect(walk.unassigned.map(\.id) == [k9.id])
        try await walking.read(season, in: &walk)
        walk.place(k9.id, .entry(in: season, sequence: "stories", position: 1))
        #expect(walk.unassigned.isEmpty && walk.placed(in: season).map(\.id) == [k9.id])
        try await walking.confirm(season, in: &walk)
        #expect(walk.state(of: season) == .changed, "a placement is a change")
        walk.place(k9.id, nil)
        #expect(walk.unassigned.map(\.id) == [k9.id] && walk.state(of: season) == .lookedAt, "and unplaced, it is back")
        walk.place(k9.id, .entry(in: season, sequence: "stories", position: 1))

        let stored = try await console.store(walk, of: home, tmdb: tmdb)
        #expect(stored.refusal == nil && stored.stored.map(\.id) == ["edit:\(season)"])
        let items = try #require(held.container(seasons[0].id)?.sequences[0].items)
        #expect(items.map(\.externalRefs) == [[], [k9.ref], []], "at the position it was placed")
        let again = try await console.compare(series.id.value, in: "tv", of: home, from: database, tmdb: tmdb)
        #expect(!again.differences.contains { if case .special = $0 { true } else { false } }, "no longer unassigned")

        var below = try await console.startWalk(at: season, in: "tv", of: home)
        #expect(below.series == series.id.value)
        let k10 = Self.episode(3502, 0, 2, "Dimensions in Time", runtime: 15)
        tmdb.seasons["121/0"] = TMDb.Season(id: 50, number: 0, name: "Specials", episodes: [k9, k10])
        below.pool(try await console.specials(of: series.id.value, in: "tv", of: home, from: database, tmdb: tmdb))
        #expect(below.unassigned.map(\.id) == [k10.id], "the series' specials, read through the series above")
        below.place(k10.id, .declined)
        try await walking.confirm(season, in: &below)
        #expect(try below.plan().steps.map(\.id) == ["decline:\(series.id)"], "the series, no stop, declines it")
        #expect(try await console.store(below, of: home, tmdb: tmdb).refusal == nil)
        #expect(held.sidecar(series.id)?.declined == [k10.ref])
    }

    /// A confirmed season opened again shows its ticks as they were left; one more ticked is kept only
    /// once the season is confirmed again, which replaces its pending change.
    @Test func aConfirmedStopOpenedAgainKeepsWhatWasChosen() async throws {
        let (database, folder) = Self.clone()
        defer { try? FileManager.default.removeItem(at: folder) }
        var (series, seasons, serials, tmdb) = Self.walkedSeries()
        tmdb.episodeIDs[5001] = TMDb.ExternalIDs(imdb: "tt0005001", tvdb: "5001")
        let (console, home) = try await Self.smddbConsole(HeldLibrary([series] + seasons + serials))
        let walking = Walking(console: console, home: home, database: database, tmdb: tmdb)
        let serial = serials[0].id.value
        let (imdb, tvdb) = ("ref:part-one:imdb:tt0005001", "ref:part-one:tvdb:5001")

        var walk = try await walking.walk(series.id.value)
        try await walking.confirm(seasons[0].id.value, in: &walk)
        try await walking.read(serial, in: &walk)
        #expect(Set(walk.stops[serial]?.comparison?.differences.map(\.id) ?? []) == [imdb, tvdb])
        try await walking.confirm(serial, choosing: [imdb], in: &walk)
        #expect(Self.edit(of: serial, in: try walk.plan())?.value?.sequences[0].items[0].externalRefs.count == 2)

        #expect(walk.stops[serial]?.chosen == [imdb], "opened again, as it was left")
        walk.stops[serial]?.chosen.insert(tvdb)
        #expect(
            Self.edit(of: serial, in: try walk.plan())?.value?.sequences[0].items[0].externalRefs.count == 2,
            "ticked, not yet kept"
        )
        walk.confirm(serial, beneath: try await console.stops(beneath: serial, in: walk, of: home))
        let refs = Self.edit(of: serial, in: try walk.plan())?.value?.sequences[0].items[0].externalRefs
        #expect(refs?.map(\.provider) == [.tmdb, .tvdb, .imdb], "both, in one edit, in the reading's order")
    }

    /// A walk stored with stops it never opened, or opened and never confirmed, stores only what its
    /// confirmed stops took.
    @Test func aWalkStoresOnlyWhatWasConfirmed() async throws {
        let (database, folder) = Self.clone()
        defer { try? FileManager.default.removeItem(at: folder) }
        var (series, seasons, serials, tmdb) = Self.walkedSeries()
        tmdb.series[121]?.overview = "A time traveller."
        tmdb.seasons["121/1"]?.overview = "The first."
        let held = HeldLibrary([series] + seasons + serials)
        let (console, home) = try await Self.smddbConsole(held)
        let walking = Walking(console: console, home: home, database: database, tmdb: tmdb)
        let before = held.sidecars.withLock { $0 }

        var walk = try await walking.walk(series.id.value, choosing: ["outline"])
        try await walking.read(seasons[0].id.value, in: &walk)
        walk.stops[seasons[0].id.value]?.chosen = ["outline"]
        #expect(try walk.plan().steps.map(\.id) == ["edit:\(series.id)"])
        #expect(try await console.store(walk, of: home, tmdb: tmdb).refusal == nil)
        let after = held.sidecars.withLock { $0 }
        #expect(after.filter { before[$0.key] != $0.value }.map(\.key) == [series.id.value])
        #expect(held.container(series.id)?.outline == "A time traveller.")
    }

    /// The store lists every edit before it makes any, and the silo refusing the second of three stops it
    /// there: the first is stored, and the walk keeps the second and third to be stored again.
    @Test func aWalksStoreStopsAtTheFirstRefusal() async throws {
        let (database, folder) = Self.clone()
        defer { try? FileManager.default.removeItem(at: folder) }
        var (series, seasons, serials, tmdb) = Self.walkedSeries()
        tmdb.series[121]?.overview = "A time traveller."
        tmdb.seasons["121/1"]?.name = "Refused"
        tmdb.seasons["121/2"]?.overview = "The second."
        let held = HeldLibrary([series] + seasons + serials)
        let (console, home) = try await Self.smddbConsole(held)
        let walking = Walking(console: console, home: home, database: database, tmdb: tmdb)
        let (one, two) = (seasons[0].id.value, seasons[1].id.value)

        var walk = try await walking.walk(series.id.value, choosing: ["outline"])
        try await walking.confirm(one, choosing: ["title"], in: &walk)
        try await walking.confirm(two, choosing: ["outline"], in: &walk)
        let plan = try walk.plan()
        #expect(plan.steps.map(\.id) == ["edit:\(series.id)", "edit:\(one)", "edit:\(two)"])
        #expect(
            plan.steps.map(\.described) == [
                "edit Doctor Who: its outline", "edit Season 1: its title", "edit Season 2: its outline",
            ]
        )

        let stored = try await console.store(walk, of: home, tmdb: tmdb)
        #expect(stored.stored.map(\.id) == ["edit:\(series.id)"])
        #expect(stored.refusal == "the validator refuses it")
        #expect(stored.rest.map(\.id) == ["edit:\(one)", "edit:\(two)"])
        #expect(try stored.walk.plan().steps.map(\.id) == ["edit:\(one)", "edit:\(two)"], "kept, to be stored again")
        #expect(held.container(series.id)?.outline == "A time traveller.")
        #expect(held.container(seasons[1].id)?.outline == nil)
    }

    /// A special placed as the duplicate of an item a confirmed stop holds is made in that stop's own
    /// edit, beside what the stop took, so the store makes one edit of it and refuses neither.
    @Test func anEditOfAConfirmedStopIsPartOfThatStopsEdit() async throws {
        let (database, folder) = Self.clone()
        defer { try? FileManager.default.removeItem(at: folder) }
        var (series, seasons, serials, tmdb) = Self.walkedSeries()
        let omnibus = Self.episode(3601, 0, 1, "Serial 1: Omnibus", runtime: 90)
        tmdb.seasons["121/0"] = TMDb.Season(id: 50, number: 0, name: "Specials", episodes: [omnibus])
        tmdb.episodeIDs[5001] = TMDb.ExternalIDs(imdb: "tt0005001")
        let held = HeldLibrary([series] + seasons + serials)
        let (console, home) = try await Self.smddbConsole(held)
        let walking = Walking(console: console, home: home, database: database, tmdb: tmdb)
        let (season, serial) = (seasons[0].id.value, serials[0].id.value)

        var walk = try await walking.walk(series.id.value)
        try await walking.confirm(season, in: &walk)
        try await walking.confirm(serial, choosing: ["ref:part-one:imdb:tt0005001"], in: &walk)
        try await walking.read(season, in: &walk)
        walk.place(
            omnibus.id,
            .duplicate(home: serial, item: "part-one", library: "tv", from: season, asExtra: true)
        )
        let plan = try walk.plan()
        #expect(plan.steps.map(\.id) == ["edit:\(season)", "edit:\(serial)"], "no edit of the serial of its own")
        let refs = Self.edit(of: serial, in: plan)?.value?.sequences[0].items[0].externalRefs
        #expect(
            refs == [
                ExternalRef(provider: .tmdb, value: "5001"), ExternalRef(provider: .imdb, value: "tt0005001"),
                omnibus.ref,
            ]
        )

        let stored = try await console.store(walk, of: home, tmdb: tmdb)
        #expect(stored.refusal == nil)
        #expect(held.container(serials[0].id)?.sequences[0].items[0].externalRefs == refs)
        #expect(held.container(seasons[0].id)?.extras.compactMap(\.reference).map(\.item.value) == ["part-one"])
    }

    // MARK: Alternatives and companions

    /// The walked series with its first season's first serial, The Daleks, holding four episodes and an
    /// alternate broadcast order, TMDb's titles and runtimes for them, and the specials given.
    private static func daleks(
        _ specials: [TMDb.Episode]
    ) -> (series: Container, held: [Container], serial: Container, parts: [TMDb.Episode], TMDb: FakeTMDb) {
        var (series, seasons, serials, tmdb) = Self.walkedSeries()
        let parts = ["The Dead Planet", "The Survivors", "The Escape", "The Ambush"].enumerated().map { index, title in
            Self.episode(5101 + index, 1, index + 1, title, runtime: 25)
        }
        func entry(_ index: Int) -> Entry {
            .leaf(Entry.Leaf(id: ItemID("part-\(index + 1)")!, type: .episode, externalRefs: [parts[index].ref]))
        }
        var serial = serials[0]
        serial.title = Title("The Daleks")!
        serial.sequences = [
            Sequence(id: "parts", items: parts.indices.map(entry)),
            Sequence(id: "broadcast", items: [.ref(EntryRef(item: ItemID("part-1")!))]),
        ]
        serial.alternatives = [Alternative(id: "broadcast", sequence: "broadcast", title: "As broadcast")]
        tmdb.seasons["121/1"]?.episodes = parts
        tmdb.seasons["121/0"] = TMDb.Season(id: 50, number: 0, name: "Specials", episodes: specials)
        return (series, seasons + [serial] + serials.dropFirst(), serial, parts, tmdb)
    }

    /// Walks to the serial: the series confirmed, and its seasons until the serial is a stop, which is
    /// read.
    private func walkToTheSerial(_ walking: Walking, _ series: Container, _ serial: Container) async throws -> TMDbWalk
    {
        var walk = try await walking.walk(series.id.value)
        for season in walk.order.dropFirst() where walk.stops[serial.id.value] == nil {
            try await walking.confirm(season, in: &walk)
        }
        try await walking.read(serial.id.value, in: &walk)
        return walk
    }

    /// A special placed as a new edition of a serial is a sequence holding it alone, named by an
    /// alternative with the title given; one placed in the serial's alternate sequence goes at its
    /// position; and the serial's other sequences are unchanged.
    @Test func aSpecialPlacedAsANewEditionIsASequenceOfItsOwn() async throws {
        let (database, folder) = Self.clone()
        defer { try? FileManager.default.removeItem(at: folder) }
        let omnibus = Self.episode(3701, 0, 1, "The Daleks: Omnibus", runtime: 100)
        let trailer = Self.episode(3702, 0, 2, "The Daleks: Trailer", runtime: 40)
        let (series, contents, serial, _, tmdb) = Self.daleks([omnibus, trailer])
        let held = HeldLibrary([series] + contents)
        let (console, home) = try await Self.smddbConsole(held)
        let walking = Walking(console: console, home: home, database: database, tmdb: tmdb)

        var walk = try await walkToTheSerial(walking, series, serial)
        walk.place(omnibus.id, .edition(of: serial.id.value, title: "Omnibus"))
        walk.place(trailer.id, .entry(in: serial.id.value, sequence: "broadcast", position: 1))
        #expect(walk.placed(in: serial.id.value).count == 2)
        try await walking.confirm(serial.id.value, in: &walk)
        #expect(try await console.store(walk, of: home, tmdb: tmdb).refusal == nil)

        let made = try #require(held.container(serial.id))
        #expect(made.sequences.map(\.id) == ["parts", "broadcast", "omnibus"])
        #expect(made.sequences[0] == serial.sequences[0], "the parts are as they were")
        #expect(made.sequences[2].items.map(\.externalRefs) == [[omnibus.ref]])
        #expect(made.sequences[1].items.map(\.externalRefs) == [[], [trailer.ref]], "at its position")
        #expect(
            made.alternatives == [
                Alternative(id: "broadcast", sequence: "broadcast", title: "As broadcast"),
                Alternative(id: "omnibus", sequence: "omnibus", title: "Omnibus"),
            ]
        )
    }

    /// A special placed as a version of the first of a serial's four episodes is a sequence holding it
    /// first and referring to the other three, named by an alternative; the serial still holds one entry
    /// for each episode.
    @Test func aSpecialPlacedAsAVersionOfAnEpisodeRefersToTheRest() async throws {
        let (database, folder) = Self.clone()
        defer { try? FileManager.default.removeItem(at: folder) }
        let enhanced = Self.episode(3711, 0, 1, "The Dead Planet (Special Edition)", runtime: 25)
        let (series, contents, serial, _, tmdb) = Self.daleks([enhanced])
        let held = HeldLibrary([series] + contents)
        let (console, home) = try await Self.smddbConsole(held)
        let walking = Walking(console: console, home: home, database: database, tmdb: tmdb)

        var walk = try await walkToTheSerial(walking, series, serial)
        walk.place(enhanced.id, .version(of: serial.id.value, item: "part-1", title: "Special edition"))
        try await walking.confirm(serial.id.value, in: &walk)
        #expect(try await console.store(walk, of: home, tmdb: tmdb).refusal == nil)

        let made = try #require(held.container(serial.id))
        let version = try #require(made.sequences.last)
        #expect(version.id == "special-edition")
        #expect(version.items.first?.externalRefs == [enhanced.ref])
        #expect(version.items.dropFirst().map(\.reference?.item.value) == ["part-2", "part-3", "part-4"])
        #expect(
            made.alternatives.last
                == Alternative(id: "special-edition", sequence: "special-edition", title: "Special edition")
        )
        #expect(made.itemIDs.count == 5, "one entry for each episode, and the special's")
    }

    /// A special whose title names a serial beside "Omnibus", one that runs as long as the serial's
    /// episodes together, and one whose title names an episode beside "Special Edition" are suggested,
    /// once the serial is read, as new editions of it and as a version of the episode.
    @Test func anOmnibusAndASpecialEditionAreSuggestedAsAlternatives() async throws {
        let (database, folder) = Self.clone()
        defer { try? FileManager.default.removeItem(at: folder) }
        let omnibus = Self.episode(3721, 0, 1, "The Daleks: Omnibus", runtime: 100)
        let movie = Self.episode(3722, 0, 2, "The Daleks: The Movie", runtime: 98)
        let enhanced = Self.episode(3723, 0, 3, "The Survivors (Special Edition)", runtime: 25)
        let elsewhere = Self.episode(3724, 0, 4, "The Daleks in Colour", runtime: 60)
        let (series, contents, serial, parts, tmdb) = Self.daleks([omnibus, movie, enhanced, elsewhere])
        let (console, home) = try await Self.smddbConsole(HeldLibrary([series] + contents))
        let walking = Walking(console: console, home: home, database: database, tmdb: tmdb)

        let walk = try await walkToTheSerial(walking, series, serial)
        let id = serial.id.value
        #expect(
            walk.suggestions[omnibus.id]
                == AdminConsole.SpecialSuggestion(
                    placement: .edition(of: id, title: "Omnibus"),
                    reason: "its title names The Daleks as an omnibus",
                    basis: .alternative
                )
        )
        #expect(
            walk.suggestions[movie.id]
                == AdminConsole.SpecialSuggestion(
                    placement: .edition(of: id, title: "Omnibus"),
                    reason: "it runs 98 minutes, as The Daleks's 4 episodes do together",
                    basis: .alternative
                )
        )
        #expect(
            walk.suggestions[enhanced.id]
                == AdminConsole.SpecialSuggestion(
                    placement: .version(of: id, item: "part-2", title: "Special edition"),
                    reason: "its title names The Survivors as another version of it",
                    basis: .alternative
                )
        )
        #expect(walk.suggestions[elsewhere.id] == nil, "named, but neither an omnibus nor as long")
        #expect(walk.suggestions[omnibus.id]?.placement.flatMap(walk.home) == id, "suggested at the serial")

        // A draft's specials are suggested the same way, against its containers.
        var tree = TMDbTree(
            library: "tv",
            record: TMDb.Record(.series, 121),
            creating: ContainerDraft.Creating(),
            containers: [serial],
            top: serial.id,
            episodeTitles: Dictionary(uniqueKeysWithValues: parts.map { (String($0.id), $0.title) }),
            runtimes: Dictionary(uniqueKeysWithValues: parts.map { (String($0.id), 25) }),
            specials: [Special(episode: movie), Special(episode: enhanced), Special(episode: omnibus)]
        )
        tree.episodeGroups = []
        let (_, suggestions) = try await console.suggest(for: tree, of: home, from: database, tmdb: tmdb)
        #expect(suggestions[movie.id]?.placement == .edition(of: id, title: "Omnibus"))
        #expect(suggestions[enhanced.id]?.placement == .version(of: id, item: "part-2", title: "Special edition"))
        for special in [movie, enhanced] { tree.place(special.id, suggestions[special.id]?.placement) }
        tree.place(omnibus.id, .version(of: id, item: "no-such-part", title: "Lost"))
        let made = try #require(tree.making.documents.first)
        #expect(made.sequences.map(\.id) == ["parts", "broadcast", "omnibus", "special-edition"])
        #expect(
            made.alternatives.map(\.title) == ["As broadcast", "Omnibus", "Special edition"],
            "and none for no item"
        )
    }

    /// A special placed in a listed series the library holds is an entry of that series, referred to
    /// from the season's extras, and the series stays listed; the walked series is no companion.
    @Test func aSpecialIsPlacedInACompanionSeriesTheLibraryHolds() async throws {
        let (database, folder) = Self.clone()
        defer { try? FileManager.default.removeItem(at: folder) }
        let concert = Self.episode(3731, 0, 1, "Doctor Who at the Proms 2008", runtime: 60)
        var (series, seasons, serials, tmdb) = Self.walkedSeries()
        tmdb.seasons["121/0"] = TMDb.Season(id: 50, number: 0, name: "Specials", episodes: [concert])
        var proms = Container(id: ContainerID("00000000000001c1")!, type: .series, title: Title("At the Proms")!)
        proms.sequences = [Sequence(id: "concerts", items: [])]
        let held = HeldLibrary([series, proms] + seasons + serials)
        let (console, home) = try await Self.smddbConsole(held)
        let walking = Walking(console: console, home: home, database: database, tmdb: tmdb)
        let season = seasons[0].id.value

        let companions = try await console.companionSeries(in: "tv", besides: series.id.value, of: home)
        #expect(companions.map(\.id) == [proms.id.value] && companions[0].listed)
        var walk = try await walking.walk(series.id.value)
        try await walking.read(season, in: &walk)
        walk.place(concert.id, .breakout(proms.id.value, from: season, asExtra: true))
        try await walking.confirm(season, in: &walk)
        let plan = try walk.plan()
        #expect(
            plan.steps.map(\.id).first?.hasPrefix("held:tv/\(proms.id)") == true,
            "before the edit that refers to it"
        )
        #expect(try await console.store(walk, of: home, tmdb: tmdb).refusal == nil)

        let filed = try #require(held.container(proms.id))
        #expect(filed.listed && filed.sequences[0].items.map(\.externalRefs) == [[concert.ref]])
        let entry = try #require(filed.sequences[0].items.first?.id)
        #expect(held.container(seasons[0].id)?.extras == [.ref(EntryRef(container: proms.id, item: entry))])
    }

    /// A special placed in a new companion series the operator titles and lists makes the series listed,
    /// holding the special's entry, before the edit that refers to it.
    @Test func aNewCompanionSeriesIsCreatedListedWhenTheOperatorSays() async throws {
        let (database, folder) = Self.clone()
        defer { try? FileManager.default.removeItem(at: folder) }
        let concert = Self.episode(3741, 0, 1, "Doctor Who at the Proms 2010", runtime: 60)
        var (series, seasons, serials, tmdb) = Self.walkedSeries()
        tmdb.seasons["121/0"] = TMDb.Season(id: 50, number: 0, name: "Specials", episodes: [concert])
        let held = HeldLibrary([series] + seasons + serials)
        let (console, home) = try await Self.smddbConsole(held)
        let walking = Walking(console: console, home: home, database: database, tmdb: tmdb)
        let season = seasons[0].id.value
        var proms = Container(id: try await database.provisionalID(), type: .series, title: Title("At the Proms")!)
        proms.sequences = [Sequence(id: "concerts", items: [])]
        #expect(!Container(id: proms.id, type: .series, title: proms.title, listed: false).listed)

        var walk = try await walking.walk(series.id.value)
        try await walking.read(season, in: &walk)
        walk.place(concert.id, .breakout(proms.id.value, from: season, asExtra: false), companion: proms)
        try await walking.confirm(season, in: &walk)
        let plan = try walk.plan()
        #expect(plan.steps.map(\.id) == ["create:\(proms.id)", "edit:\(season)"])
        #expect(plan.steps[0].described == "make At the Proms, a series of its own, at the top of the library")
        #expect(try await console.store(walk, of: home, tmdb: tmdb).refusal == nil)

        let made = try #require(held.container(proms.id))
        #expect(made.listed && made.sequences[0].items.map(\.externalRefs) == [[concert.ref]])
        #expect(held.container(seasons[0].id)?.sequences[0].items.last?.reference?.container == proms.id)
    }
}
