// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import FileServing
import Foundation
import HTTPTypes
import SiloClient
import SiloKit
import SiloLibrary
import SmdKit
import SmdSidecar
import Testing
import WireMVCTesting
@testable import SiloApp

/// A library on disk that the suite points the silo at through its environment: real files, the
/// real index, no doubles.
enum Fixture {
    static let series: Container = {
        var series = Container(id: ContainerID("0000000000000001")!, type: .series, title: "Doctor Who", year: 1963, yearInTitle: true, externalRefs: [ExternalRef(provider: .tvdb, value: "76107")])
        series.sequences = [Sequence(id: "seasons", items: [Entry(id: "s13", type: .container, container: serial.id)])]
        return series
    }()
    static let serial: Container = {
        var serial = Container(id: ContainerID("0000000000000003")!, type: .serial, typeLabel: "Story", title: "Pyramids of Mars")
        serial.alternatives = [Alternative(id: "broadcast", sequence: "parts", title: "Broadcast version")]
        serial.defaultAlternative = "broadcast"
        serial.features = [Feature(id: "commentary1", type: .commentary, title: "Commentary")]
        serial.sequences = [Sequence(id: "parts", items: [Entry(id: "part1", type: .episode, title: "Part One"), Entry(id: "part2", type: .episode, title: "Part Two"), Entry(id: "part3", type: .episode, title: "Part Three")])]
        return serial
    }()
    static let unlisted = Container(id: ContainerID("0000000000000004")!, type: .series, title: "Behind the Sofa", listed: false)

    static let mediaBytes = Data((0..<3000).map { UInt8($0 % 251) })

    /// One library for the one suite: the environment the harness applies is the process's, so
    /// a second suite with its own paths would race the first for what the app reads at boot.
    static let root = build()

    static func build() -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("silo-server-\(UUID().uuidString)")
        let library = root.appendingPathComponent("Library")
        try! FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: root.appendingPathComponent("State"), withIntermediateDirectories: true)
        func place(_ lineage: [Container], item: String, profile: String? = nil, tracks: [TrackMapping] = []) {
            let source = root.appendingPathComponent("\(UUID().uuidString).mkv")
            try! mediaBytes.write(to: source)
            try! Placer.apply(try! Placer.compute(PlacementRequest(library: library, lineage: lineage, item: item, presentation: Presentation(profile: profile, file: "", tracks: tracks), source: source)))
        }
        place([series, serial], item: "part1", tracks: [TrackMapping(feature: "commentary1", audio: 3)])
        place([series, serial], item: "part1", profile: "mobile", tracks: [TrackMapping(feature: "commentary1", audio: 2)])
        try! SidecarFile.data(for: Sidecar(container: unlisted)).write(to: {
            let folder = library.appendingPathComponent("Behind the Sofa")
            try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder.appendingPathComponent("container.smd")
        }())
        return root
    }

    static func environment(_ root: URL) -> [String: String] {
        [
            "SILO_LIBRARIES": "main=\(root.appendingPathComponent("Library").path)",
            "SILO_STATE_DIR": root.appendingPathComponent("State").path,
            "SILO_OPERATOR_TOKEN": "secret",
        ]
    }

    static let household = try! String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Examples/household.xml"), encoding: .utf8)
}

struct RulesetDocumentBody: Codable {
    var name: String
    var version: Int?
    var document: String?
}

@Suite(.wiremvc(.inProcess, environment: { Fixture.environment(Fixture.root) }), .serialized)
struct ServerTests {
    @Test func theLibraryIsBrowsable() async throws {
        try await withClient { client in
            let libraries = try await client.get("/v1/libraries")
            #expect(libraries.status == 200)
            #expect(libraries.bodyText.contains("\"id\":\"main\""))
            #expect(libraries.bodyText.contains("\"presentations\":2"))

            let roots = try await client.get("/v1/containers")
            #expect(roots.status == 200)
            #expect(roots.bodyText.contains("Doctor Who (1963)"))
            #expect(!roots.bodyText.contains("Behind the Sofa"), "unlisted containers are not roots")

            let serial = try await client.get("/v1/containers/0000000000000003")
            #expect(serial.status == 200)
            let text = serial.bodyText
            #expect(text.contains("\"typeLabel\":\"Story\""))
            #expect(text.contains("\"parent\":\"0000000000000001\""))
            #expect(text.contains("\"displayName\":\"mobile\""))
            #expect(text.contains("\"file\":\"Part One.mkv\""))
            #expect(text.contains("\"audio\":3"))

            let mobile = try await client.get("/v1/containers/0000000000000003?profile=mobile")
            #expect(mobile.bodyText.contains("Part One - mobile.mkv"))
            #expect(!mobile.bodyText.contains("\"file\":\"Part One.mkv\""), "a profile filters; it never substitutes")

            let unlisted = try await client.get("/v1/containers/0000000000000004")
            #expect(unlisted.status == 200, "unlisted, but reachable by id")
            #expect(try await client.get("/v1/containers/00000000000000ff").status == 404)
            #expect(try await client.get("/v1/containers/not-an-id").status == 404)

            let lookup = try await client.get("/v1/lookup?provider=tvdb&value=76107")
            #expect(lookup.bodyText.contains("0000000000000001"))
            let search = try await client.get("/v1/search?q=part")
            #expect(search.bodyText.contains("Part Two"))
            #expect(try await client.get("/health").status == 200)
            #expect(try await client.get("/nowhere").status == 404)
        }
    }

    @Test func theSidecarIsServedAsItIs() async throws {
        try await withClient { client in
            let response = try await client.get("/v1/containers/0000000000000003/smd")
            #expect(response.status == 200)
            #expect(response.head?.headerFields[.contentType]?.hasPrefix("application/xml") == true)
            let onDisk = try Data(contentsOf: Fixture.root.appendingPathComponent("Library/Doctor Who (1963)/Pyramids of Mars/container.smd"))
            #expect(response.body == onDisk)
            #expect(try await client.get("/v1/containers/00000000000000ff/smd").status == 404)
        }
    }

    @Test func mediaIsServedWholeAndByRange() async throws {
        try await withClient { client in
            let serial = try await client.get("/v1/containers/0000000000000003")
            let id = try #require(Self.presentationID(in: serial.bodyText, file: "Part One.mkv"))

            let whole = try await client.get("/v1/media/\(id)")
            #expect(whole.status == 200)
            #expect(whole.body == Fixture.mediaBytes)
            #expect(whole.head?.headerFields[.acceptRanges] == "bytes")
            #expect(whole.head?.headerFields[.contentType] == "video/x-matroska")
            #expect(whole.head?.headerFields[.eTag] != nil)

            let part = try await client.get("/v1/media/\(id)", headers: ["Range": "bytes=100-199"])
            #expect(part.status == 206)
            #expect(part.head?.headerFields[.contentRange] == "bytes 100-199/3000")
            #expect(part.body == Fixture.mediaBytes[100...199])

            let tail = try await client.get("/v1/media/\(id)", headers: ["Range": "bytes=2900-"])
            #expect(tail.status == 206)
            #expect(tail.body == Fixture.mediaBytes[2900...])

            let suffix = try await client.get("/v1/media/\(id)", headers: ["Range": "bytes=-10"])
            #expect(suffix.head?.headerFields[.contentRange] == "bytes 2990-2999/3000")

            let beyond = try await client.get("/v1/media/\(id)", headers: ["Range": "bytes=5000-"])
            #expect(beyond.status == 416)
            #expect(beyond.head?.headerFields[.contentRange] == "bytes */3000")

            #expect(try await client.get("/v1/media/0000000000000000").status == 404)
        }
    }

    @Test func rulesetsAreVersionedAndTheOperatorGateHolds() async throws {
        try await withClient { client in
            let body = RulesetDocumentBody(name: "household", document: Fixture.household)
            let refused = try await client.send("PUT", "/v1/rulesets/household", body: try JSONEncoder().encode(body), headers: ["Content-Type": "application/json"])
            #expect(refused.status == 401)
            let wrongToken = try await client.send("PUT", "/v1/rulesets/household", body: try JSONEncoder().encode(body), headers: ["Content-Type": "application/json", "Authorization": "Bearer wrong"])
            #expect(wrongToken.status == 401)

            let operatorHeaders = ["Content-Type": "application/json", "Authorization": "Bearer secret"]
            let first = try await client.send("PUT", "/v1/rulesets/household", body: try JSONEncoder().encode(body), headers: operatorHeaders)
            #expect(first.status == 201)
            #expect(try first.json(RulesetDocumentBody.self).version == 1)
            let second = try await client.send("PUT", "/v1/rulesets/household", body: try JSONEncoder().encode(body), headers: operatorHeaders)
            #expect(try second.json(RulesetDocumentBody.self).version == 2)

            let bad = try await client.send("PUT", "/v1/rulesets/broken", body: try JSONEncoder().encode(RulesetDocumentBody(name: "broken", document: "<ruleset format=\"1\" name=\"b\"><audio><when fact=\"nope\" is=\"1\"/><copy/></audio></ruleset>")), headers: operatorHeaders)
            #expect(bad.status == 400)
            #expect(bad.bodyText.contains("not a fact a rule can test"))

            let list = try await client.get("/v1/rulesets")
            #expect(try list.json([RulesetDocumentBody].self).map { "\($0.name)@\($0.version ?? 0)" } == ["household@2"])
            let latest = try await client.get("/v1/rulesets/household")
            #expect(try latest.json(RulesetDocumentBody.self).version == 2)
            let v1 = try await client.get("/v1/rulesets/household?version=1")
            #expect(try v1.json(RulesetDocumentBody.self).document == Fixture.household)
            #expect(try await client.get("/v1/rulesets/household?version=9").status == 404)
            #expect(try await client.get("/v1/rulesets/nothing").status == 404)

            let facts = SourceFacts(
                kind: .featurette,
                video: VideoFacts(absoluteIndex: 0, codec: "mpeg2video", width: 352, height: 288),
                audio: [
                    AudioFacts(index: 1, absoluteIndex: 1, codec: "flac", lossless: true, channels: 2),
                    AudioFacts(index: 2, absoluteIndex: 2, codec: "ac3", lossless: false, channels: 2, role: .commentary),
                ]
            )
            struct Resolve: Encodable { var facts: SourceFacts; var mappings: [TrackMapping] }
            let resolved = try await client.post("/v1/rulesets/household/resolve", json: Resolve(facts: facts, mappings: [TrackMapping(feature: "c", audio: 2)]))
            #expect(resolved.status == 200)
            let recipe = try resolved.json(Recipe.self)
            #expect(recipe.decisions.map(\.rule) == ["small-extras", "lossless-main", "commentary"])
            #expect(recipe.ruleset.description == "household@2")

            let strict = RulesetDocumentBody(name: "strict", document: "<ruleset format=\"1\" name=\"strict\"><video><copy/></video></ruleset>")
            _ = try await client.send("PUT", "/v1/rulesets/strict", body: try JSONEncoder().encode(strict), headers: operatorHeaders)
            let undecided = try await client.post("/v1/rulesets/strict/resolve", json: Resolve(facts: facts, mappings: []))
            #expect(undecided.status == 422)
            #expect(undecided.bodyText.contains("no rule decides audio 1"))
        }
    }

    @Test func aScanIsAnOperatorsToo() async throws {
        try await withClient { client in
            #expect(try await client.send("POST", "/v1/libraries/main/scan").status == 401)
            let scan = try await client.send("POST", "/v1/libraries/main/scan", headers: ["Authorization": "Bearer secret"])
            #expect(scan.status == 200)
            #expect(scan.bodyText.contains("\"read\":0"))
            #expect(scan.bodyText.contains("\"unchanged\":3"))
            #expect(try await client.send("POST", "/v1/libraries/other/scan", headers: ["Authorization": "Bearer secret"]).status == 404)
        }
    }

    @Test func rangesAreParsedAsTheSpecificationSays() {
        #expect(ByteRange.parse(nil, size: 100) == .whole)
        #expect(ByteRange.parse("bytes=0-49", size: 100) == .part(0, 49))
        #expect(ByteRange.parse("bytes=50-", size: 100) == .part(50, 99))
        #expect(ByteRange.parse("bytes=-10", size: 100) == .part(90, 99))
        #expect(ByteRange.parse("bytes=0-500", size: 100) == .part(0, 99), "an end past the file is clipped")
        #expect(ByteRange.parse("bytes=100-", size: 100) == .unsatisfiable)
        #expect(ByteRange.parse("bytes=0-1,5-6", size: 100) == .whole, "several ranges are served as the whole")
        #expect(ByteRange.parse("items=0-1", size: 100) == .whole)
    }

    struct ContainerJSON: Decodable {
        struct Sequence: Decodable { var items: [Item] }
        struct Item: Decodable { var presentations: [Presentation] }
        struct Presentation: Decodable { var id: String; var file: String }
        var sequences: [Sequence]
    }

    private static func presentationID(in json: String, file: String) -> String? {
        let container = try? JSONDecoder().decode(ContainerJSON.self, from: Data(json.utf8))
        return container?.sequences.flatMap(\.items).flatMap(\.presentations).first { $0.file == file }?.id
    }
}

struct PlaceBody: Encodable {
    var containers: [String]
    var item: String
    var alternative: String?
    var profile: String?
    var tracks: [TrackMapping] = []
    var chapters: [Chapter] = []
    var file: String
    var copy: Bool = false
    var dryRun: Bool = false
}

struct PlacementResultBody: Decodable {
    struct Finding: Decodable { var severity: String; var text: String }
    var applied: Bool
    var destination: String
    var presentation: String?
    var writes: [String]
    var findings: [Finding]
}

extension ServerTests {
    static let documents = [Fixture.series, Fixture.serial].map { String(decoding: ContainerFile.data(for: $0), as: UTF8.self) }
    static let operatorHeaders = ["Content-Type": "application/json", "Authorization": "Bearer secret"]

    /// Last in the suite on purpose: it changes the library the tests above count.
    @Test func zPlacementIsShownThenAppliedAndRefusedTheSecondTime() async throws {
        let file = Fixture.root.appendingPathComponent("part2.mkv")
        try Fixture.mediaBytes.write(to: file)
        try await withClient { client in
            var body = PlaceBody(containers: Self.documents, item: "part2", tracks: [TrackMapping(feature: "commentary1", audio: 2)], chapters: [Chapter(index: 1, title: "Opening")], file: file.path, dryRun: true)
            #expect(try await client.send("POST", "/v1/libraries/main/place", body: try JSONEncoder().encode(body)).status == 401)

            let shown = try await client.send("POST", "/v1/libraries/main/place", body: try JSONEncoder().encode(body), headers: Self.operatorHeaders)
            #expect(shown.status == 200)
            let dry = try shown.json(PlacementResultBody.self)
            #expect(dry.applied == false)
            #expect(dry.presentation == nil)
            #expect(dry.destination == "Doctor Who (1963)/Pyramids of Mars/Part Two.mkv")
            #expect(dry.writes.last == "update   Doctor Who (1963)/Pyramids of Mars/container.smd")
            #expect(FileManager.default.fileExists(atPath: file.path), "a dry run moves nothing")

            body.dryRun = false
            let placed = try await client.send("POST", "/v1/libraries/main/place", body: try JSONEncoder().encode(body), headers: Self.operatorHeaders)
            #expect(placed.status == 200)
            let result = try placed.json(PlacementResultBody.self)
            #expect(result.applied == true)
            #expect(!FileManager.default.fileExists(atPath: file.path), "moved into place")
            let id = try #require(result.presentation)
            let media = try await client.get("/v1/media/\(id)", headers: ["Range": "bytes=0-9"])
            #expect(media.status == 206, "the index learned of it without a scan being asked for")
            let serial = try await client.get("/v1/containers/0000000000000003")
            #expect(serial.bodyText.contains("Part Two.mkv"))
            #expect(serial.bodyText.contains("\"title\":\"Opening\""))

            try Fixture.mediaBytes.write(to: file)
            let again = try await client.send("POST", "/v1/libraries/main/place", body: try JSONEncoder().encode(body), headers: Self.operatorHeaders)
            #expect(again.status == 409)
            let refused = try again.json(PlacementResultBody.self)
            #expect(refused.applied == false)
            #expect(refused.findings.map(\.text).contains("already exists; nothing is overwritten"))
            #expect(FileManager.default.fileExists(atPath: file.path), "a refusal moves nothing")

            let unknownItem = PlaceBody(containers: Self.documents, item: "part9", file: file.path)
            let bad = try await client.send("POST", "/v1/libraries/main/place", body: try JSONEncoder().encode(unknownItem), headers: Self.operatorHeaders)
            #expect(bad.status == 400)
            #expect(bad.bodyText.contains("has no item part9"))
            let unreadable = PlaceBody(containers: ["<nope/>"], item: "part2", file: file.path)
            #expect(try await client.send("POST", "/v1/libraries/main/place", body: try JSONEncoder().encode(unreadable), headers: Self.operatorHeaders).status == 400)
            #expect(try await client.send("POST", "/v1/libraries/other/place", body: try JSONEncoder().encode(body), headers: Self.operatorHeaders).status == 404)
        }
    }
}

/// The job routes, each reaching the transition the service tests cover, over the in-process
/// server and through the client every other participant uses.
extension ServerTests {
    @Test func yJobsAreRegisteredAssignedClaimedAndPlacedOverTheAPI() async throws {
        try await withClient { client in
            let rip = Fixture.root.appendingPathComponent("rip.mkv")
            try Fixture.mediaBytes.write(to: rip)
            let source = FileRef(holder: "laptop", url: rip, path: rip.path, sizeBytes: 3000, secret: "s3cret")
            let newJob = SiloClient.NewJob(source: source, discName: "Disc 1", probe: JobServiceTests.Bench.probe)

            #expect(try await client.post("/v1/jobs", json: newJob).status == 401)
            let created = try await client.post("/v1/jobs", json: newJob, headers: ["Authorization": "Bearer secret"])
            #expect(created.status == 201)
            let job = try SiloClient.decoder.decode(Job.self, from: created.body)
            #expect(job.state == .unassigned)
            #expect(try await client.get("/v1/jobs?state=unassigned").bodyText.contains(job.id))
            #expect(try await client.get("/v1/jobs?state=placed").bodyText == "[]")
            #expect(try await client.get("/v1/jobs/nothing").status == 404)

            let body = RulesetDocumentBody(name: "household", document: Fixture.household)
            _ = try await client.send("PUT", "/v1/rulesets/household", body: try JSONEncoder().encode(body), headers: ["Content-Type": "application/json", "Authorization": "Bearer secret"])

            let assigned = try await client.send("PUT", "/v1/jobs/\(job.id)/assignment", body: try SiloClient.encoder.encode(JobServiceTests.Bench.assignment(item: "part3", profile: "mobile")), headers: ["Content-Type": "application/json", "Authorization": "Bearer secret"])
            #expect(assigned.status == 200)
            let pending = try SiloClient.decoder.decode(Job.self, from: assigned.body)
            #expect(pending.state == .pending)
            #expect(pending.requirements == ["aac", "flac"])

            let strict = try await client.send("PUT", "/v1/jobs/\(job.id)/assignment", body: try SiloClient.encoder.encode({ var a = JobServiceTests.Bench.assignment(); a.ruleset = "strict"; return a }()), headers: ["Content-Type": "application/json", "Authorization": "Bearer secret"])
            #expect(strict.status == 422, "the strict ruleset from the ruleset test decides no audio")

            struct Claim: Encodable { var node: String; var capabilities: [String] }
            let nothing = try await client.post("/v1/jobs/claim", json: Claim(node: "box", capabilities: ["flac"]), headers: ["Authorization": "Bearer secret"])
            #expect(nothing.status == 200)
            #expect(nothing.bodyText == "{}")
            let claim = try await client.post("/v1/jobs/claim", json: Claim(node: "box", capabilities: ["flac", "aac"]), headers: ["Authorization": "Bearer secret"])
            #expect(claim.status == 200)
            #expect(claim.bodyText.contains("s3cret"), "the claiming node is handed the source's secret")

            let progress = try await client.send("POST", "/v1/jobs/\(job.id)/progress", body: try SiloClient.encoder.encode(JobProgress(fraction: 0.25)), headers: ["Content-Type": "application/json", "Authorization": "Bearer secret"])
            #expect(progress.bodyText == "{\"state\":\"encoding\"}")
            #expect(try await client.send("POST", "/v1/jobs/\(job.id)/retry", headers: ["Authorization": "Bearer secret"]).status == 409)

            let output = Fixture.root.appendingPathComponent("encoded-\(job.id).mkv")
            try Fixture.mediaBytes.write(to: output)
            struct Complete: Encodable { var output: FileRef; var result: EncodeResult }
            let completed = try await client.post("/v1/jobs/\(job.id)/complete", json: Complete(output: FileRef(holder: "box", url: output, path: output.path, secret: ""), result: EncodeResult(streams: ["video h264", "audio flac", "audio aac"], layoutMatched: true)), headers: ["Authorization": "Bearer secret"])
            #expect(completed.status == 200)
            #expect(try SiloClient.decoder.decode(Job.self, from: completed.body).state == .encoded)

            let placed = try await client.send("POST", "/v1/jobs/\(job.id)/place", headers: ["Authorization": "Bearer secret"])
            #expect(placed.status == 200)
            let done = try SiloClient.decoder.decode(Job.self, from: placed.body)
            #expect(done.state == .placed)
            #expect(done.placement?.destination == "Doctor Who (1963)/Pyramids of Mars/Part Three - mobile.mkv")
            let id = try #require(done.placement?.presentation)
            #expect(try await client.get("/v1/media/\(id)", headers: ["Range": "bytes=0-9"]).status == 206)
            #expect(try await client.send("POST", "/v1/jobs/\(job.id)/place", headers: ["Authorization": "Bearer secret"]).status == 409)
            #expect(try await client.send("POST", "/v1/jobs/\(job.id)/cancel", headers: ["Authorization": "Bearer secret"]).status == 409)
        }
    }
}

/// The node routes: a node's own two, the operator's three, and the node gate on the job routes.
extension ServerTests {
    @Test func xNodesRegisterAreApprovedAndTakeWorkWithTheirToken() async throws {
        try await withClient { client in
            let registration = NodeRegistration(id: "node-1", secret: "s3cret", name: "box", platform: "Linux", capabilities: ["flac", "aac"], ffmpegVersion: "ffmpeg 7", cores: 4)
            let registered = try await client.post("/v1/nodes", json: registration)
            #expect(registered.status == 201)
            #expect(try SiloClient.decoder.decode(Node.self, from: registered.body).state == .pending)
            #expect(try await client.post("/v1/nodes", json: NodeRegistration(id: "node-1", secret: "wrong", name: "box", platform: "Linux", capabilities: [])).status == 403)

            #expect(try await client.get("/v1/nodes").status == 401)
            let listed = try await client.get("/v1/nodes", headers: ["Authorization": "Bearer secret"])
            #expect(try SiloClient.decoder.decode([Node].self, from: listed.body).map(\.id) == ["node-1"])

            let pending = try await client.get("/v1/nodes/node-1", headers: ["x-silo-node-secret": "s3cret"])
            #expect(pending.status == 200)
            #expect(try SiloClient.decoder.decode(NodeStatus.self, from: pending.body).token == nil)
            #expect(try await client.get("/v1/nodes/node-1", headers: ["x-silo-node-secret": "wrong"]).status == 403)
            #expect(try await client.get("/v1/nodes/node-9", headers: ["x-silo-node-secret": "s3cret"]).status == 404)

            struct Claim: Encodable { var node: String; var capabilities: [String] }
            #expect(try await client.post("/v1/jobs/claim", json: Claim(node: "node-1", capabilities: ["flac"])).status == 401, "no token yet")

            #expect(try await client.send("POST", "/v1/nodes/node-1/approve").status == 401)
            #expect(try await client.send("POST", "/v1/nodes/node-1/approve", headers: ["Authorization": "Bearer secret"]).status == 200)
            let approved = try await client.get("/v1/nodes/node-1", headers: ["x-silo-node-secret": "s3cret"])
            let token = try #require(try SiloClient.decoder.decode(NodeStatus.self, from: approved.body).token)
            #expect(try SiloClient.decoder.decode(NodeStatus.self, from: try await client.get("/v1/nodes/node-1", headers: ["x-silo-node-secret": "s3cret"]).body).token == nil, "once")

            let claim = try await client.post("/v1/jobs/claim", json: Claim(node: "node-1", capabilities: ["flac"]), headers: ["Authorization": "Bearer \(token)"])
            #expect(claim.status == 200, "the node's token passes the node gate")
            #expect(try await client.post("/v1/jobs/claim", json: Claim(node: "node-1", capabilities: ["flac"]), headers: ["Authorization": "Bearer nope"]).status == 401)
            #expect(try await client.send("POST", "/v1/jobs/nothing/cancel", headers: ["Authorization": "Bearer \(token)"]).status == 401, "a node's token does not pass the operator's gate")

            #expect(try await client.send("POST", "/v1/nodes/node-1/revoke", headers: ["Authorization": "Bearer secret"]).status == 200)
            #expect(try await client.post("/v1/jobs/claim", json: Claim(node: "node-1", capabilities: ["flac"]), headers: ["Authorization": "Bearer \(token)"]).status == 401, "revoked at once")
        }
    }
}

/// The server's own route, open to anything that asks: its id, its name and its bootstrap state.
extension ServerTests {
    @Test func theServerRouteAnswersOpenly() async throws {
        try await withClient { client in
            let server = try await client.get("/v1/server")
            #expect(server.status == 200)
            struct Info: Decodable, Equatable { var id: String; var name: String; var bootstrap: Bool }
            let info = try SiloClient.decoder.decode(Info.self, from: server.body)
            #expect(info.id == info.id.lowercased() && UUID(uuidString: info.id) != nil)
            #expect(info.name.hasPrefix("Silo on "))
            #expect(info.bootstrap == false, "the suite's environment sets a token")
            #expect(try SiloClient.decoder.decode(Info.self, from: server.body) == info, "the same boot answers the same")
        }
    }
}

/// The verify-access route: the same answer as the open route, behind the operator's gate, and
/// nothing else. A refusal is the gate's and not the server's — the node list, the jobs, and the
/// library never come into it.
extension ServerTests {
    @Test func theVerifyRouteAnswersOnlyTheOperator() async throws {
        try await withClient { client in
            struct Info: Decodable, Equatable { var id: String; var name: String; var bootstrap: Bool }
            let open = try await client.get("/v1/server")
            let verified = try await client.get("/v1/operator", headers: ["Authorization": "Bearer secret"])
            #expect(verified.status == 200)
            #expect(try SiloClient.decoder.decode(Info.self, from: verified.body) == SiloClient.decoder.decode(Info.self, from: open.body), "the same server as the open route answers")
            #expect(try await client.get("/v1/operator").status == 401, "no bearer is refused")
            #expect(try await client.get("/v1/operator", headers: ["Authorization": "Bearer wrong"]).status == 401, "a refused bearer is refused")
        }
    }
}

/// The setup pair, shut from the very first boot: the suite's environment sets a token, so the
/// server is never in bootstrap, staging is gone for good, and nothing is ever staged to confirm.
/// The open pair's life — six scenarios of it — is pinned at the service in `SetupTests`.
extension ServerTests {
    @Test func theSetupPairStaysShutWhereACredentialStands() async throws {
        try await withClient { client in
            struct Setup: Encodable { var passkey: String }
            let stage = try await client.post("/v1/setup", json: Setup(passkey: "horse-battery"))
            #expect(stage.status == 410, "a token in the environment means staging is gone")
            let confirm = try await client.send("POST", "/v1/setup/confirm", headers: ["Authorization": "Bearer horse-battery"])
            #expect(confirm.status == 404, "nothing was ever staged")
        }
    }
}
