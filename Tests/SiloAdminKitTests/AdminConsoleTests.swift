// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloAdminKit
import SiloClient
import SiloDiscovery
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

    private static let clock = Date(timeIntervalSince1970: 1_790_000_000)

    /// The verify probe's admission: OperatorStatus, not ServerInfo, is what /v1/operator serves.
    private static let active = #"{"phase":"active"}"#

    private static func serverInfo(_ id: String, _ name: String, bootstrap: Bool) -> String {
        #"{"id":"\#(id)","name":"\#(name)","bootstrap":\#(bootstrap)}"#
    }

    /// A console wired to the stub, its clock stopped at `clock` and its browse fixed.
    private static func console(
        registry: SiloRegistry = SiloRegistry(),
        passkeys: InMemoryPasskeyStore = InMemoryPasskeyStore(),
        discovered: [DiscoveredSilo] = [],
        answering handler: @escaping @Sendable (URLRequest) throws -> (Int, Data)?
    ) -> AdminConsole {
        answer(with: handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Stub.self]
        return AdminConsole(
            registry: registry,
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

    private func row(_ id: String, in rows: [AdminConsole.Silo], fileID: String = #fileID, filePath: String = #filePath, line: Int = #line, column: Int = #column) throws -> AdminConsole.Silo {
        try #require(rows.first { $0.id == id }, "no row for \(id)", sourceLocation: SourceLocation(fileID: fileID, filePath: filePath, line: line, column: column))
    }

    // MARK: - The registry

    @Test func browsingRefreshesNeverForgets() async throws {
        let registry = SiloRegistry()
        let lastSeen = Date(timeIntervalSince1970: 1_700_000_000)
        try registry.merge(RegisteredSilo(id: "attic", name: "Attic Silo", url: URL(string: "http://attic.local:8080")!, lastSeen: lastSeen, hasStoredPasskey: false))
        let wire = Mutex<[String]>([])
        let console = Self.console(registry: registry, discovered: [DiscoveredSilo(name: "Living Room Silo", host: "living.local", port: 8080)]) { request in
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
            try registry.merge(RegisteredSilo(id: id, name: id, url: URL(string: "http://\(id).local:8080")!, lastSeen: Self.clock, hasStoredPasskey: id != "nohands"))
        }
        let passkeys = InMemoryPasskeyStore()
        passkeys.store("key-a", for: "access")
        passkeys.store("key-b", for: "locked")
        let noderequests = Mutex<[String?]>([])
        // nohands is registered but not discovered: it is the row that has gone quiet.
        let console = Self.console(registry: registry, passkeys: passkeys, discovered: ["boot", "newbie", "access", "locked"].map { DiscoveredSilo(name: $0, host: "\($0).local", port: 8080) }) { request in
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
                return request.value(forHTTPHeaderField: "Authorization") == "Bearer key-a" ? (200, Data(Self.active.utf8)) : (401, Data())
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
        #expect(noderequests.withLock { $0 }.map { $0 ?? "(none)" }.sorted() == ["Bearer key-a", "Bearer key-b"], "the probe asks only reachable silos with a passkey, with that passkey as bearer")
    }

    @Test func theProbeDecides() async throws {
        let registry = SiloRegistry()
        try registry.merge(RegisteredSilo(id: "probe", name: "Probe", url: URL(string: "http://probe.local:8080")!, lastSeen: Self.clock, hasStoredPasskey: true))
        let passkeys = InMemoryPasskeyStore()
        passkeys.store("held", for: "probe")
        let accepts = Mutex("held")
        let console = Self.console(registry: registry, passkeys: passkeys, discovered: [DiscoveredSilo(name: "Probe", host: "probe.local", port: 8080)]) { request in
            guard let url = request.url else { return nil }
            switch url.path {
            case "/v1/server": return (200, Data(Self.serverInfo("probe", "Probe", bootstrap: false).utf8))
            case "/v1/operator": return request.value(forHTTPHeaderField: "Authorization") == "Bearer \(accepts.withLock { $0 })" ? (200, Data(Self.active.utf8)) : (401, Data())
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
        try registry.merge(RegisteredSilo(id: "home", name: "Home Silo", url: URL(string: "http://home.local:8080")!, lastSeen: Self.clock, hasStoredPasskey: true))
        let passkeys = InMemoryPasskeyStore()
        passkeys.store("key", for: "home")
        let alive = Mutex(true)
        let probed = Mutex(0)
        let console = Self.console(registry: registry, passkeys: passkeys, discovered: [DiscoveredSilo(name: "Home Silo", host: "home.local", port: 8080)]) { request in
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
        let console = Self.console(discovered: [DiscoveredSilo(name: "Attic Silo", host: "attic.local", port: 8080)]) { request in
            guard alive.withLock({ $0 }), let url = request.url, url.host == "attic.local", url.path == "/v1/server" else { return nil }
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
        try registry.merge(RegisteredSilo(id: "probe", name: "Probe", url: URL(string: "http://probe.local:8080")!, lastSeen: Self.clock, hasStoredPasskey: true))
        let passkeys = InMemoryPasskeyStore()
        passkeys.store("held", for: "probe")
        let alive = Mutex(true)
        let accepts = Mutex("held")
        let console = Self.console(registry: registry, passkeys: passkeys, discovered: [DiscoveredSilo(name: "Probe", host: "probe.local", port: 8080)]) { request in
            guard alive.withLock({ $0 }), let url = request.url else { return nil }
            switch url.path {
            case "/v1/server": return (200, Data(Self.serverInfo("probe", "Probe", bootstrap: false).utf8))
            case "/v1/operator": return request.value(forHTTPHeaderField: "Authorization") == "Bearer \(accepts.withLock { $0 })" ? (200, Data(Self.active.utf8)) : (401, Data())
            default: return nil
            }
        }

        #expect(try row("probe", in: await console.refresh()).classification == .withAccess)

        alive.withLock { $0 = false }
        #expect(try row("probe", in: await console.refresh()).classification == .withAccess, "one miss holds the last verified class")

        accepts.withLock { $0 = "rotated" }
        alive.withLock { $0 = true }
        let healed = try row("probe", in: await console.refresh())
        #expect(healed.classification == .withoutAccess, "contact renders this sweep's verdict at once, whatever it is")
        #expect(healed.lastKnownAccess == false, "the refusal is what is now known")
    }

    @Test func launchedIntoSilenceReadsTheRegistrysVerdicts() async throws {
        let registry = SiloRegistry()
        try registry.merge(RegisteredSilo(id: "home", name: "Home Silo", url: URL(string: "http://home.local:8080")!, lastSeen: Self.clock, hasStoredPasskey: true, lastKnownAccess: true))
        try registry.merge(RegisteredSilo(id: "attic", name: "Attic Silo", url: URL(string: "http://attic.local:8080")!, lastSeen: Self.clock, hasStoredPasskey: false))
        let passkeys = InMemoryPasskeyStore()
        passkeys.store("key", for: "home")
        let probed = Mutex(0)
        let console = Self.console(registry: registry, passkeys: passkeys, discovered: [DiscoveredSilo(name: "Home Silo", host: "home.local", port: 8080)]) { request in
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
        let console = Self.console(discovered: [DiscoveredSilo(name: "Hall Silo", host: "hall.local", port: 8080)]) { request in
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
        let console = Self.console(registry: registry, passkeys: store, discovered: [DiscoveredSilo(name: "Fresh Silo", host: "fresh.local", port: 8080)]) { request in
            guard let url = request.url else { return nil }
            switch url.path {
            case "/v1/server":
                return request.httpMethod == "GET" ? (200, Data(Self.serverInfo("s1", "Fresh Silo", bootstrap: true).utf8)) : nil
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
        #expect(try row("s1", in: await console.silos).classification == .withAccess, "the rendered list moves with the flow")
    }

    @Test func aLiveStageIsFinishedByConsent() async throws {
        let store = InMemoryPasskeyStore()
        store.store("kept-from-attempt-one", for: "s7")
        let wire = Mutex<[String]>([])
        let console = Self.console(passkeys: store, discovered: [DiscoveredSilo(name: "Fresh Silo", host: "fresh.local", port: 8080)]) { request in
            guard let url = request.url else { return nil }
            wire.withLock { $0.append("\(request.httpMethod ?? "?") \(url.path)") }
            switch url.path {
            case "/v1/server":
                return request.httpMethod == "GET" ? (200, Data(Self.serverInfo("s7", "Fresh Silo", bootstrap: true).utf8)) : nil
            case "/v1/operator":
                return request.value(forHTTPHeaderField: "Authorization") == "Bearer kept-from-attempt-one"
                    ? (200, Data(#"{"phase":"pending","confirmBy":"2026-09-24T10:10:00Z"}"#.utf8))
                    : (401, Data())
            case "/v1/setup":
                Issue.record("a resumed stage re-stages nothing")
                return nil
            case "/v1/setup/confirm":
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer kept-from-attempt-one", "the confirm spends the residue, not something minted")
                return (201, Data(Self.serverInfo("s7", "Fresh Silo", bootstrap: false).utf8))
            default:
                return nil
            }
        }

        let fresh = try row("s7", in: await console.refresh())
        let prepared = try await console.prepareSetup(fresh)
        #expect(prepared.presentation == .reused, "the residue is never shown again")
        #expect(prepared.resumingUntil?.timeIntervalSince1970 == 1_790_244_600, "the sheet learns when the standing window shuts")

        let rendered = try await console.runSetup(prepared, name: nil)

        #expect(rendered.classification == .withAccess)
        #expect(rendered.lastKnownAccess == true)
        #expect(wire.withLock { $0 } == ["GET /v1/server", "GET /v1/operator", "POST /v1/setup/confirm"], "probe first; consent sends the confirm alone")
    }

    @Test func aDeadResidueIsReplaced() async throws {
        let store = InMemoryPasskeyStore()
        store.store("dead-key", for: "s8")
        let staged = Mutex<String?>(nil)
        let heldAtConfirm = Mutex<String?>(nil)
        let wire = Mutex<[String]>([])
        let console = Self.console(passkeys: store, discovered: [DiscoveredSilo(name: "Fresh Silo", host: "fresh.local", port: 8080)]) { request in
            guard let url = request.url else { return nil }
            wire.withLock { $0.append("\(request.httpMethod ?? "?") \(url.path)") }
            switch url.path {
            case "/v1/server":
                return request.httpMethod == "GET" ? (200, Data(Self.serverInfo("s8", "Fresh Silo", bootstrap: true).utf8)) : nil
            case "/v1/operator":
                return (401, Data())
            case "/v1/setup":
                let body = Self.body(of: request).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] }
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
        #expect(wire.withLock { $0 } == ["GET /v1/server", "GET /v1/operator", "POST /v1/setup", "POST /v1/setup/confirm"], "probe first, then the pair in full")
    }

    @Test func someoneElseGotThereFirst() async throws {
        let store = InMemoryPasskeyStore()
        store.store("stay-key", for: "residue")
        let console = Self.console(passkeys: store, discovered: [
            DiscoveredSilo(name: "Fresh", host: "fresh.local", port: 8080),
            DiscoveredSilo(name: "Residue", host: "residue.local", port: 8080),
        ]) { request in
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
        guard case .minted(let minted) = fresh.presentation else { Issue.record("nothing held, so minted"); return }
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
        let console = Self.console(registry: registry, passkeys: store, discovered: [DiscoveredSilo(name: "Busy Silo", host: "busy.local", port: 8080)]) { request in
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
        try registry.merge(RegisteredSilo(id: "known", name: "Known Silo", url: URL(string: "http://known.local:8080")!, lastSeen: Self.clock, hasStoredPasskey: false))
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
                return request.value(forHTTPHeaderField: "Authorization") == "Bearer filed" ? (200, Data(Self.active.utf8)) : (401, Data())
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

    // MARK: - Forget

    @Test func forgetPurgesTheRegistryAndThePasskey() async throws {
        let registry = SiloRegistry()
        try registry.merge(RegisteredSilo(id: "quiet", name: "Quiet Silo", url: URL(string: "http://quiet.local:8080")!, lastSeen: Self.clock, hasStoredPasskey: true, lastKnownAccess: true))
        let store = InMemoryPasskeyStore()
        store.store("old-key", for: "quiet")
        let console = Self.console(registry: registry, passkeys: store) { _ in nil }

        _ = await console.refresh()
        let quiet = try row("quiet", in: await console.refresh())
        #expect(quiet.classification == .unreachable, "gone quiet — twice — is the moment to forget")

        await console.forget(quiet)

        #expect(store.passkey(for: "quiet") == nil, "this Mac no longer holds the passkey")
        #expect(registry.entry(for: "quiet") == nil, "the registry keeps nothing of it")
        #expect(await console.silos.isEmpty, "the row leaves the rendered list")
    }

    @Test func aRediscoveryRestartsHistory() async throws {
        let registry = SiloRegistry()
        try registry.merge(RegisteredSilo(id: "quiet", name: "Quiet Silo", url: URL(string: "http://quiet.local:8080")!, lastSeen: Self.clock, hasStoredPasskey: true, lastKnownAccess: true))
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
