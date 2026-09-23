// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloClient
import SiloKit
import SiloStore
import Testing
@testable import SiloApp
@testable import SiloDiscovery

/// A node's life on the service alone: registered pending, approved, given its token once,
/// authenticated by it, revoked, and approved again with a new one.
struct NodeServiceTests {
    @Test func aNodeIsApprovedAndTakesItsTokenOnce() throws {
        let service = NodeService(nodes: NodeStore())
        let registration = NodeRegistration(id: "n1", secret: "s1", name: "box", platform: "Linux", capabilities: ["flac", "aac"], ffmpegVersion: "ffmpeg 7", cores: 8)
        let node = try service.register(registration)
        #expect(node.state == .pending)
        #expect(service.all().map(\.id) == ["n1"])

        #expect(throws: WrongSecret.self) { try service.register(NodeRegistration(id: "n1", secret: "other", name: "box", platform: "Linux", capabilities: [])) }
        var renamed = registration
        renamed.name = "the box"
        #expect(try service.register(renamed).name == "the box", "a registration that knows the secret brings the record up to date")

        #expect(throws: WrongSecret.self) { try service.status("n1", secret: "other") }
        #expect(try service.status("n1", secret: "s1").token == nil, "nothing until approved")
        #expect(service.authenticate(bearer: "anything") == nil)

        #expect(try service.approve("n1").state == .approved)
        let first = try service.status("n1", secret: "s1")
        let token = try #require(first.token)
        #expect(try service.status("n1", secret: "s1").token == nil, "handed over once")
        #expect(service.authenticate(bearer: token)?.id == "n1")
        #expect(try service.node("n1").lastSeenAt != nil, "seeing the token is the heartbeat")

        #expect(try service.revoke("n1").state == .revoked)
        #expect(service.authenticate(bearer: token) == nil, "revoked at once")
        #expect(try service.approve("n1").state == .approved)
        let again = try #require(try service.status("n1", secret: "s1").token)
        #expect(again != token, "a new token, since the old was revoked")
        #expect(service.authenticate(bearer: token) == nil)
        #expect(service.authenticate(bearer: again)?.id == "n1")
        #expect(throws: NoSuchNode.self) { try service.approve("n9") }
    }

    @Test func nodesSurviveARestart() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("silo-nodes-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let token: String
        do {
            let service = NodeService(nodes: try NodeStore(folder: folder))
            _ = try service.register(NodeRegistration(id: "n1", secret: "s1", name: "box", platform: "macOS", capabilities: []))
            _ = try service.approve("n1")
            token = try #require(try service.status("n1", secret: "s1").token)
        }
        let reopened = NodeService(nodes: try NodeStore(folder: folder))
        #expect(reopened.authenticate(bearer: token)?.name == "box")
        #expect(try reopened.status("n1", secret: "s1").token == nil)
        let stored = String(decoding: try Data(contentsOf: folder.appendingPathComponent("n1.json")), as: UTF8.self)
        #expect(!stored.contains("s1") && !stored.contains(token), "neither the secret nor the token is stored, only their hashes")
    }
}

struct DiscoveryTests {
    @Test func avahiOutputIsParsed() {
        let lines = [
            "+;eth0;IPv6;Living\\032Room\\032Silo;_silo._tcp;local",
            "+;eth0;IPv4;Living\\032Room\\032Silo;_silo._tcp;local",
            "=;eth0;IPv6;Living\\032Room\\032Silo;_silo._tcp;local;nuc.local;fe80::1;8080;\"v=1\" \"name=Living Room Silo\"",
            "=;eth0;IPv4;Living\\032Room\\032Silo;_silo._tcp;local;nuc.local;192.168.1.5;8080;\"v=1\" \"name=Living Room Silo\"",
            "=;eth0;IPv4;Study;_silo._tcp;local;study.local;192.168.1.9;9090;",
        ]
        let found = Discovery.parseAvahi(lines)
        #expect(found == [
            DiscoveredSilo(name: "Living Room Silo", host: "nuc.local", port: 8080, txt: ["v": "1", "name": "Living Room Silo"]),
            DiscoveredSilo(name: "Study", host: "study.local", port: 9090),
        ])
        #expect(found[0].url == URL(string: "http://nuc.local:8080"))
    }

    @Test func dnssdOutputIsParsed() {
        let browse = [
            "Browsing for _silo._tcp",
            "DATE: ---Mon 22 Sep 2026---",
            "15:21:03.123  ...STARTING...",
            "Timestamp     A/R    Flags  if Domain               Service Type         Instance Name",
            "15:21:03.456  Add        3   6 local.               _silo._tcp.          Living Room Silo",
            "15:21:03.457  Add        2   6 local.               _silo._tcp.          Study",
            "15:21:05.000  Rmv        0   6 local.               _silo._tcp.          Study",
        ]
        #expect(Discovery.parseDNSSDBrowse(browse) == ["Living Room Silo", "Study"])
        let lookup = [
            "Lookup Living Room Silo._silo._tcp.local.",
            "DATE: ---Mon 22 Sep 2026---",
            "15:21:06.000  ...STARTING...",
            "15:21:06.010  Living\\032Room\\032Silo._silo._tcp.local. can be reached at nuc.local.:8080 (interface 6)",
            " v=1 name=Living\\032Room\\032Silo",
        ]
        #expect(Discovery.parseDNSSDLookup(lookup, name: "Living Room Silo") == DiscoveredSilo(name: "Living Room Silo", host: "nuc.local", port: 8080, txt: ["v": "1", "name": "Living\\032Room\\032Silo"]))
        #expect(Discovery.parseDNSSDLookup(["nothing"], name: "x") == nil)
    }

    /// The real thing, where the platform's tool is present: advertise on a port, and find it.
    /// Skipped on a machine without a responder to talk to.
    /// On macOS the responder is always there; on Linux a daemon has to be, so it is opted into.
    static var liveBonjour: Bool {
        #if os(macOS)
        Discovery.isAvailable && ProcessInfo.processInfo.environment["SILO_TEST_BONJOUR"] != "0"
        #else
        Discovery.isAvailable && ProcessInfo.processInfo.environment["SILO_TEST_BONJOUR"] == "1"
        #endif
    }

    @Test(.enabled(if: DiscoveryTests.liveBonjour, "a Bonjour responder is needed"))
    func anAdvertisedSiloIsFound() async throws {
        let name = "Silo test \(UUID().uuidString.prefix(8))"
        let advertisement = try Discovery.advertise(name: name, port: 18765, txt: ["v": "1"])
        defer { advertisement.stop() }
        try await Task.sleep(for: .seconds(1))
        let found = try await Discovery.browse(timeout: .seconds(3))
        let silo = try #require(found.first { $0.name == name })
        #expect(silo.port == 18765)
        #expect(silo.txt["v"] == "1")
        #expect(!silo.host.isEmpty)
    }
}
