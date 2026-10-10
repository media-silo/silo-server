// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import FileServing
import Foundation
import HTTPTypes
import SiloClient
import SiloKit
import SiloLibrary
import SiloStore
import SmdKit
import SmdSidecar
import Testing
import WireMVCTesting
@testable import SiloApp

/// A library on disk and a state directory that names it: real files, the real index, no doubles. The
/// silo arrives configured the way an owner would configure it before a first boot — the library in
/// `settings.json`, the operator's token in `operator-credential.reset` — and its environment is
/// `SILO_STATE_DIR` alone.
enum Fixture {
    static let series: Container = {
        var series = Container(id: ContainerID("0000000000000001")!, type: .series, title: Title("Doctor Who")!, year: 1963, yearInTitle: true, externalRefs: [ExternalRef(provider: .tvdb, value: "76107")])
        series.sequences = [Sequence(id: "seasons", items: [.child(Entry.Child(id: ItemID("s13")!, container: serial.id))])]
        return series
    }()
    static let serial: Container = {
        var serial = Container(id: ContainerID("0000000000000003")!, type: .serial, typeLabel: "Story", title: Title("Pyramids of Mars")!)
        serial.alternatives = [Alternative(id: "broadcast", sequence: "parts", title: "Broadcast version")]
        serial.defaultAlternative = "broadcast"
        serial.features = [Feature(id: "commentary1", type: .commentary, title: "Commentary")]
        serial.sequences = [Sequence(id: "parts", items: [.leaf(Entry.Leaf(id: ItemID("part1")!, type: .episode, title: "Part One")), .leaf(Entry.Leaf(id: ItemID("part2")!, type: .episode, title: "Part Two")), .leaf(Entry.Leaf(id: ItemID("part3")!, type: .episode, title: "Part Three"))])]
        return serial
    }()
    static let unlisted = Container(id: ContainerID("0000000000000004")!, type: .series, title: Title("Behind the Sofa")!, listed: false)

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
        let state = root.appendingPathComponent("State")
        try! Data("""
            {"libraries": [{"id": "main", "path": "\(library.path)"}]}
            """.utf8).write(to: state.appendingPathComponent("settings.json"))
        try! Data("secret\n".utf8).write(to: state.appendingPathComponent("operator-credential.reset"))
        return root
    }

    static func environment(_ root: URL) -> [String: String] {
        ["SILO_STATE_DIR": root.appendingPathComponent("State").path]
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

            let featurette = InputSpec(streams: [
                InputSpec.Stream(index: 0, kind: .video, codec: "mpeg2video", width: 352, height: 288),
                InputSpec.Stream(index: 1, kind: .audio, codec: "flac", channels: 2),
                InputSpec.Stream(index: 2, kind: .audio, codec: "ac3", channels: 2, marks: [.commentary]),
            ])
            struct Resolve: Encodable { var inputs: [InputSpec]; var kind: String?; var mappings: [TrackMapping] }
            let resolved = try await client.post("/v1/rulesets/household/resolve", json: Resolve(inputs: [featurette], kind: "featurette", mappings: [TrackMapping(feature: "c", audio: 2)]))
            #expect(resolved.status == 200)
            let recipes = try resolved.json([Recipe].self)
            #expect(recipes.count == 1, "a recipe for each of the ruleset's outputs")
            #expect(recipes[0].decisions.map(\.rule) == ["small-extras", "lossless-main", "commentary"])
            #expect(recipes[0].ruleset.description == "household@2")
            let newer = try await client.send("POST", "/v1/rulesets/household/resolve", body: Data(#"{ "inputs": [ { "format": 2, "streams": [] } ] }"#.utf8), headers: ["Content-Type": "application/json"])
            #expect(newer.status == 400)
            #expect(newer.bodyText.contains("input 1: input spec format 2 is newer than this silo reads (1)"))

            let strict = RulesetDocumentBody(name: "strict", document: "<ruleset format=\"1\" name=\"strict\"><video><copy/></video></ruleset>")
            _ = try await client.send("PUT", "/v1/rulesets/strict", body: try JSONEncoder().encode(strict), headers: operatorHeaders)
            let undecided = try await client.post("/v1/rulesets/strict/resolve", json: Resolve(inputs: [featurette], kind: "featurette", mappings: []))
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
    @Test func yJobsAreMadeFromRecipesClaimedAndPlacedOverTheAPI() async throws {
        try await withClient { client in
            let rip = Fixture.root.appendingPathComponent("rip.mkv")
            try Fixture.mediaBytes.write(to: rip)
            let copy = FileRef(holder: "laptop", url: rip, path: rip.path, sizeBytes: 3000, secret: "s3cret")
            let ruleset = RulesetDocumentBody(name: "household", document: JobServiceTests.Bench.household)
            _ = try await client.send("PUT", "/v1/rulesets/household", body: try JSONEncoder().encode(ruleset), headers: Self.operatorHeaders)

            /// A draft for part three of the serial, made from a source with the copy given.
            func draft(copy: FileRef?) async throws -> StoredRecipeBody {
                let source = try await client.post("/v1/sources", json: SiloClient.NewSource(input: JobServiceTests.Bench.input, copy: copy), headers: Self.operatorHeaders).json(SourceBody.self)
                let binding = try await client.post("/v1/bindings", json: SiloClient.NewBinding(
                    library: "main", containers: Self.documents, item: "part3", tracks: [TrackMapping(feature: "commentary1", audio: 2)],
                    segments: [Binding.Segment(source: source.id)]
                ), headers: Self.operatorHeaders).json(BindingBody.self)
                let application = Application(ruleset: "household", outputs: [Application.OutputChoice(profile: "mobile")])
                return try #require(try await client.post("/v1/bindings/\(binding.id)/recipes", json: application, headers: Self.operatorHeaders).json([StoredRecipeBody].self).first)
            }
            let recipe = try await draft(copy: copy)
            struct NewJob: Encodable { var recipe: String }

            #expect(try await client.post("/v1/jobs", json: NewJob(recipe: recipe.id)).status == 401)
            #expect(try await client.post("/v1/jobs", json: NewJob(recipe: "nothing"), headers: Self.operatorHeaders).status == 404)
            let created = try await client.post("/v1/jobs", json: NewJob(recipe: recipe.id), headers: Self.operatorHeaders)
            #expect(created.status == 201)
            let job = try SiloClient.decoder.decode(Job.self, from: created.body)
            #expect(job.state == .pending)
            #expect(job.recipe == recipe.id)
            #expect(job.requirements == ["aac", "flac"])
            #expect(try await client.get("/v1/recipes/\(recipe.id)").json(StoredRecipeBody.self).state == "committed")
            #expect(try await client.post("/v1/jobs", json: NewJob(recipe: recipe.id), headers: Self.operatorHeaders).status == 409, "one recipe, one job")
            #expect(try await client.get("/v1/jobs?state=pending").bodyText.contains(job.id))
            #expect(try await client.get("/v1/jobs?state=placed").bodyText == "[]")
            #expect(try await client.get("/v1/jobs/nothing").status == 404)

            let unheld = try await draft(copy: nil)
            let refused = try await client.post("/v1/jobs", json: NewJob(recipe: unheld.id), headers: Self.operatorHeaders)
            #expect(refused.status == 409)
            #expect(refused.bodyText.contains("has no copy; no node could fetch it"))
            #expect(try await client.get("/v1/recipes/\(unheld.id)").json(StoredRecipeBody.self).state == "draft")

            struct Claim: Encodable { var node: String; var capabilities: [String] }
            let nothing = try await client.post("/v1/jobs/claim", json: Claim(node: "box", capabilities: ["flac"]), headers: ["Authorization": "Bearer secret"])
            #expect(nothing.status == 200)
            #expect(nothing.bodyText == "{}")
            let claim = try await client.post("/v1/jobs/claim", json: Claim(node: "box", capabilities: ["flac", "aac"]), headers: ["Authorization": "Bearer secret"])
            #expect(claim.status == 200)
            #expect(claim.bodyText.contains("s3cret"), "the claiming node is handed the source's secret")
            struct ClaimBody: Decodable { var job: Job; var recipe: StoredRecipeBody; var segments: [ClaimedSegment] }
            let claimed = try SiloClient.decoder.decode(ClaimBody.self, from: claim.body)
            #expect(claimed.job.id == job.id)
            #expect(claimed.recipe.id == recipe.id)
            #expect(claimed.segments.map(\.copy) == [copy], "the segment's copy, whole")

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
            #expect(info.bootstrap == false, "the suite's state directory arrives with a credential")
            #expect(try SiloClient.decoder.decode(Info.self, from: server.body) == info, "the same boot answers the same")
        }
    }

    @Test func theSettingsAreReportedAndPatchedWhole() async throws {
        struct Report: Decodable {
            struct Editable: Decodable, Equatable { var name: String; var embeddedNode: Bool; var advertise: Bool }
            struct Library: Decodable, Equatable { var id: String; var path: String }
            struct ReadOnly: Decodable { var serverID: String; var host: String; var port: Int; var stateDirectory: String; var libraries: [Library] }
            var editable: Editable
            var readOnly: ReadOnly
        }
        let state = Fixture.root.appendingPathComponent("State")
        try await withClient { client in
            #expect(try await client.get("/v1/settings").status == 401)
            let operatorHeaders = ["Content-Type": "application/json", "Authorization": "Bearer secret"]

            let read = try await client.send("GET", "/v1/settings", headers: operatorHeaders)
            #expect(read.status == 200)
            let before = try read.json(Report.self)
            #expect(before.editable.name.hasPrefix("Silo on "))
            #expect(before.editable.embeddedNode == false)
            #expect(before.readOnly.stateDirectory == state.path, "where the reset file goes")
            #expect(before.readOnly.port == 8742)
            struct Info: Decodable { var id: String; var name: String }
            #expect(before.readOnly.serverID == (try await client.get("/v1/server").json(Info.self)).id)
            #expect(before.readOnly.libraries == [Report.Library(id: "main", path: Fixture.root.appendingPathComponent("Library").path)])

            let refused = try await client.send("PATCH", "/v1/settings", body: Data(#"{"name": "  ", "advertise": false}"#.utf8), headers: operatorHeaders)
            #expect(refused.status == 400)
            #expect(refused.bodyText.contains("the name cannot be empty"))
            let unchanged = try await client.send("GET", "/v1/settings", headers: operatorHeaders).json(Report.self)
            #expect(unchanged.editable == before.editable, "a refused patch changes nothing")

            let patched = try await client.send("PATCH", "/v1/settings", body: Data(#"{"name": "Living Room Silo"}"#.utf8), headers: operatorHeaders)
            #expect(patched.status == 200)
            #expect(try patched.json(Report.self).editable == Report.Editable(name: "Living Room Silo", embeddedNode: false, advertise: before.editable.advertise))
            #expect(try await client.get("/v1/server").json(Info.self).name == "Living Room Silo", "the server goes by it at once")
            let onDisk = try JSONDecoder().decode([String: JSONValue].self, from: Data(contentsOf: state.appendingPathComponent("settings.json")))
            #expect(onDisk["name"] == .string("Living Room Silo"), "written to settings.json, so it survives a restart")

            let restored = try await client.send("PATCH", "/v1/settings", body: try JSONEncoder().encode(["name": before.editable.name]), headers: operatorHeaders)
            #expect(restored.status == 200)
        }
    }
}

/// The verify-access route: it names what its bearer amounts to and nothing else — 401 for
/// anything that is neither, with an empty body, and never the id, the name, or the subsystem's
/// health. The suite's environment sets a token, so no staged passkey exists here to ask after:
/// the pending answer is pinned at the service in `SetupTests`.
extension ServerTests {
    @Test func theVerifyRouteAnswersOnlyTheOperator() async throws {
        try await withClient { client in
            let verified = try await client.get("/v1/operator", headers: ["Authorization": "Bearer secret"])
            #expect(verified.status == 200)
            #expect(verified.bodyText == #"{"phase":"active"}"#, "the bearer's standing, and none of the server's")

            let refused = try await client.get("/v1/operator")
            #expect(refused.status == 401, "no bearer is refused")
            #expect(refused.body.isEmpty, "a refusal tells nothing")
            let wrong = try await client.get("/v1/operator", headers: ["Authorization": "Bearer wrong"])
            #expect(wrong.status == 401, "a refused bearer is refused")
            #expect(wrong.body.isEmpty)
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

extension ServerTests {
    /// A source as the API renders it, enough to check what came back.
    struct SourceBody: Decodable {
        struct Copy: Decodable { var holder: String; var url: String; var secret: String? }
        var id: String
        var copies: [Copy]
    }

    static func registration(key: String?, copyOn node: String?, extraAudio: Bool = false) -> Data {
        let audio = extraAudio ? #", { "index": 2, "kind": "audio", "codec": "ac3", "channels": 2 }"# : ""
        let keyJSON = key.map { #", "key": { "scheme": "discTitle", "value": "\#($0)" }"# } ?? ""
        let copyJSON = node.map { #", "copy": { "holder": "\#($0)", "url": "http://\#($0).local:8743/files/t.mkv", "secret": "s-\#($0)" }"# } ?? ""
        return Data("""
        { "input": { "format": 1, "streams": [
            { "index": 0, "kind": "video", "codec": "h264", "width": 1920, "height": 1080, "frameRate": "24000/1001" },
            { "index": 1, "kind": "audio", "codec": "truehd", "channels": 8, "language": "en" }\(audio)
        ] }\(keyJSON)\(copyJSON) }
        """.utf8)
    }

    @Test func sourcesAreRegisteredOnceAndTheirCopiesKept() async throws {
        try await withClient { client in
            let json = ["Content-Type": "application/json"]
            let refused = try await client.send("POST", "/v1/sources", body: Self.registration(key: nil, copyOn: nil), headers: json)
            #expect(refused.status == 401, "registering is the operator's")

            let first = try await client.send("POST", "/v1/sources", body: Self.registration(key: "3F1AC2E9/00004", copyOn: "ripper"), headers: Self.operatorHeaders)
            #expect(first.status == 201)
            let source = try first.json(SourceBody.self)
            #expect(source.copies.map(\.holder) == ["ripper"])
            #expect(first.bodyText.contains("\"frameRate\":\"24000\\/1001\"") || first.bodyText.contains("\"frameRate\":\"24000/1001\""))

            let again = try await client.send("POST", "/v1/sources", body: Self.registration(key: "3F1AC2E9/00004", copyOn: "laptop"), headers: Self.operatorHeaders)
            #expect(again.status == 200, "the natural key finds the source already registered")
            #expect(try again.json(SourceBody.self).id == source.id)
            #expect(Set(try again.json(SourceBody.self).copies.map(\.holder)) == ["ripper", "laptop"])

            let otherwise = try await client.send("POST", "/v1/sources", body: Self.registration(key: "3F1AC2E9/00004", copyOn: nil, extraAudio: true), headers: Self.operatorHeaders)
            #expect(otherwise.status == 409)
            #expect(otherwise.bodyText.contains("with a different input spec"))

            let misspelt = Data(#"{ "input": { "format": 1, "streams": [ { "index": 0, "kind": "video", "codec": "h264", "width": 1, "height": 1, "intelaced": true } ] } }"#.utf8)
            let bad = try await client.send("POST", "/v1/sources", body: misspelt, headers: Self.operatorHeaders)
            #expect(bad.status == 400)
            #expect(bad.bodyText.contains("streams[0].intelaced is not a field of an input spec"))
            let newer = try await client.send("POST", "/v1/sources", body: Data(#"{ "input": { "format": 2, "streams": [], "segments": [] } }"#.utf8), headers: Self.operatorHeaders)
            #expect(newer.status == 400)
            #expect(newer.bodyText.contains("input spec format 2 is newer than this silo reads (1)"), "newer, not unknown field")

            let read = try await client.get("/v1/sources/\(source.id)")
            #expect(read.status == 200, "sources are read openly")
            #expect(try read.json(SourceBody.self).copies.allSatisfy { $0.secret == nil }, "and never with a copy's secret")
            #expect(!read.bodyText.contains("s-ripper"))
            #expect(try await client.get("/v1/sources").json([SourceBody].self).contains { $0.id == source.id })
            #expect(try await client.get("/v1/sources/nothing").status == 404)

            let gone = try await client.send("DELETE", "/v1/sources/\(source.id)/copies/ripper", headers: Self.operatorHeaders)
            #expect(gone.status == 200)
            #expect(try gone.json(SourceBody.self).copies.map(\.holder) == ["laptop"])
            let last = try await client.send("DELETE", "/v1/sources/\(source.id)/copies/laptop", headers: Self.operatorHeaders)
            #expect(try last.json(SourceBody.self).copies.isEmpty)
            #expect(try await client.get("/v1/sources/\(source.id)").status == 200, "a source whose last copy goes is kept")

            let copy = Data(#"{ "holder": "ripper", "url": "http://ripper.local:8743/files/t.mkv", "secret": "s2" }"#.utf8)
            let held = try await client.send("POST", "/v1/sources/\(source.id)/copies", body: copy, headers: Self.operatorHeaders)
            #expect(held.status == 200)
            #expect(try held.json(SourceBody.self).copies.map(\.holder) == ["ripper"])
            #expect(try await client.send("POST", "/v1/sources/nothing/copies", body: copy, headers: Self.operatorHeaders).status == 404)
            #expect(try await client.send("POST", "/v1/sources/\(source.id)/copies", body: copy, headers: json).status == 401)
        }
    }
}

extension ServerTests {
    struct BindingBody: Decodable {
        var id: String
        var segments: [Binding.Segment]
        var recipes: [String]
    }
    struct StoredRecipeBody: Decodable {
        var id: String
        var binding: String
        var state: String
        var recipe: Recipe
    }
    struct BindingRulesBody: Decodable {
        var activeVersion: Int?
        var document: String?
        var versions: [Int]
    }

    /// A ruleset of two outputs, whose mobile output scales its video.
    static let twoOutputs = """
    <ruleset format="1" name="two">
        <video id="mobile-video"><when fact="profile" is="mobile"/><encode codec="libx264"><scale height="720"/></encode></video>
        <video><copy/></video>
        <audio id="lossless-main"><when fact="audio.lossless" is="true"/><encode codec="flac"/></audio>
        <audio><copy/></audio>
        <output container="mkv"/>
        <output profile="mobile" container="mp4"/>
    </ruleset>
    """

    static func bindingBody(source: String, chapters: (Int, Int)? = nil, item: String = "part2") -> Data {
        let documents = String(decoding: try! JSONEncoder().encode(Self.documents), as: UTF8.self)
        let span = chapters.map { #", "chapters": { "from": \#($0.0), "to": \#($0.1) }"# } ?? ""
        return Data("""
        { "library": "main", "containers": \(documents), "item": "\(item)",
          "tracks": [ { "feature": "commentary1", "audio": 2 } ],
          "segments": [ { "source": "\(source)"\(span) } ] }
        """.utf8)
    }

    static func application(_ ruleset: String, version: Int? = nil, outputs: String? = nil) -> Data {
        Data(#"{ "ruleset": "\#(ruleset)"\#(version.map { ", \"version\": \($0)" } ?? "")\#(outputs.map { ", \"outputs\": \($0)" } ?? "") }"#.utf8)
    }

    @Test func entriesAreBoundAndRulesetsAppliedToThem() async throws {
        try await withClient { client in
            let ruleset = RulesetDocumentBody(name: "two", document: Self.twoOutputs)
            let stored = try await client.send("PUT", "/v1/rulesets/two", body: try JSONEncoder().encode(ruleset), headers: Self.operatorHeaders)
            let version = try stored.json(RulesetDocumentBody.self).version!
            let spec = #"""
            { "input": { "format": 1, "duration": 5990.4,
              "chapters": [ { "index": 1, "start": 0 }, { "index": 2, "start": 1497.6 }, { "index": 3, "start": 2995.2 } ],
              "streams": [
                { "index": 0, "kind": "video", "codec": "mpeg2video", "width": 720, "height": 576 },
                { "index": 1, "kind": "audio", "codec": "pcm_s16le", "channels": 2, "language": "en" },
                { "index": 2, "kind": "audio", "codec": "ac3", "channels": 2, "language": "en" } ] } }
            """#
            let source = try await client.send("POST", "/v1/sources", body: Data(spec.utf8), headers: Self.operatorHeaders).json(SourceBody.self)

            let refused = try await client.send("POST", "/v1/bindings", body: Self.bindingBody(source: source.id, chapters: (2, 2)), headers: ["Content-Type": "application/json"])
            #expect(refused.status == 401, "binding is the operator's")

            let made = try await client.send("POST", "/v1/bindings", body: Self.bindingBody(source: source.id, chapters: (2, 2)), headers: Self.operatorHeaders)
            #expect(made.status == 201)
            let binding = try made.json(BindingBody.self)
            #expect(binding.segments == [Binding.Segment(source: source.id, chapters: Binding.ChapterSpan(from: 2, to: 2))])
            #expect(binding.recipes.isEmpty, "making a binding resolves nothing")

            let applied = try await client.send("POST", "/v1/bindings/\(binding.id)/recipes", body: Self.application("two"), headers: Self.operatorHeaders)
            #expect(applied.status == 201)
            let drafts = try applied.json([StoredRecipeBody].self)
            #expect(drafts.map(\.state) == ["draft", "draft"])
            #expect(drafts.map(\.recipe.output) == [OutputPolicy(container: "mkv"), OutputPolicy(profile: "mobile", container: "mp4")])
            #expect(drafts.map(\.recipe.ruleset.description) == ["two@\(version)", "two@\(version)"], "each recipe records what made it")
            #expect(drafts[0].recipe.video?.action == .copy)
            #expect(drafts[1].recipe.video?.rule == "mobile-video", "the mobile output is resolved with its profile")

            let read = try await client.get("/v1/bindings/\(binding.id)")
            #expect(try read.json(BindingBody.self).recipes == drafts.map(\.id), "a binding is read with the ids of its recipes")
            #expect(try await client.get("/v1/bindings/nothing").status == 404)
            #expect(try await client.get("/v1/recipes/\(drafts[0].id)").json(StoredRecipeBody.self).recipe.audio.first?.rule == "lossless-main")

            // The producer's last word: keep the PCM, not FLAC — as the binding's own rules.
            let keepPCM = Data(#"{ "document": "<rules><audio id=\"keep-the-pcm\"><when fact=\"audio.index\" is=\"1\"/><copy/></audio></rules>" }"#.utf8)
            #expect(try await client.send("PUT", "/v1/bindings/\(binding.id)/rules", body: keepPCM, headers: ["Content-Type": "application/json"]).status == 401)
            #expect(try await client.send("PUT", "/v1/bindings/nothing/rules", body: keepPCM, headers: Self.operatorHeaders).status == 404)
            let refusedRules = try await client.send("PUT", "/v1/bindings/\(binding.id)/rules", body: Data(#"{ "document": "<rules><output container=\"mp4\"/></rules>" }"#.utf8), headers: Self.operatorHeaders)
            #expect(refusedRules.status == 400)
            #expect(refusedRules.bodyText.contains("is not an element of a container's or a binding's rules"))
            let storedRules = try await client.send("PUT", "/v1/bindings/\(binding.id)/rules", body: keepPCM, headers: Self.operatorHeaders)
            #expect(storedRules.status == 200)
            #expect(try storedRules.json(BindingRulesBody.self).activeVersion == 1)
            let rules = try await client.get("/v1/bindings/\(binding.id)/rules")
            #expect(rules.status == 200, "a binding's rules are read openly")
            #expect(try rules.json(BindingRulesBody.self).versions == [1])
            #expect(try rules.json(BindingRulesBody.self).document?.contains("keep-the-pcm") == true)
            #expect(try await client.get("/v1/recipes/\(drafts[0].id)").json(StoredRecipeBody.self).recipe.audio.first?.rule == "lossless-main", "storing them changes no recipe")
            #expect(try await client.send("PUT", "/v1/recipes/\(drafts[0].id)/adjustments", body: Data("[]".utf8), headers: Self.operatorHeaders).status != 200, "and a draft is no longer adjusted")
            let reapplied = try await client.send("POST", "/v1/bindings/\(binding.id)/recipes", body: Self.application("two", version: version, outputs: #"[ {} ]"#), headers: Self.operatorHeaders)
            let decided = try #require(try reapplied.json([StoredRecipeBody].self).first?.recipe.audio.first)
            #expect(decided.action == .copy)
            #expect(decided.rule == "keep-the-pcm")
            #expect(decided.layer == .layer(.binding(binding.id)), "the decision names the binding's rules")

            #expect(try await client.send("DELETE", "/v1/recipes/\(drafts[1].id)", headers: Self.operatorHeaders).status == 204)
            #expect(try await client.get("/v1/recipes/\(drafts[1].id)").status == 404)

            // The same ruleset again, and another: the same act, adding drafts and leaving the rest.
            let mobileOnly = try await client.send("POST", "/v1/bindings/\(binding.id)/recipes", body: Self.application("two", version: version, outputs: #"[ { "profile": "mobile" } ]"#), headers: Self.operatorHeaders)
            #expect(mobileOnly.status == 201)
            #expect(try mobileOnly.json([StoredRecipeBody].self).map(\.recipe.output.profile) == ["mobile"])
            let copyAll = RulesetDocumentBody(name: "copyall", document: #"<ruleset format="1" name="copyall"><video><copy/></video><audio><copy/></audio></ruleset>"#)
            _ = try await client.send("PUT", "/v1/rulesets/copyall", body: try JSONEncoder().encode(copyAll), headers: Self.operatorHeaders)
            let other = try await client.send("POST", "/v1/bindings/\(binding.id)/recipes", body: Self.application("copyall"), headers: Self.operatorHeaders)
            #expect(try other.json([StoredRecipeBody].self).map(\.recipe.ruleset.name) == ["copyall"], "another ruleset applied to the same binding")
            #expect(try await client.get("/v1/recipes/\(drafts[0].id)").json(StoredRecipeBody.self).recipe.audio.first?.rule == "lossless-main", "and the earlier draft as it was")
            #expect(try await client.get("/v1/bindings/\(binding.id)").json(BindingBody.self).recipes.count == 4)
        }
    }

    @Test func aBindingOrAnApplicationThatCannotBeMadeKeepsNothing() async throws {
        try await withClient { client in
            let ruleset = RulesetDocumentBody(name: "two", document: Self.twoOutputs)
            _ = try await client.send("PUT", "/v1/rulesets/two", body: try JSONEncoder().encode(ruleset), headers: Self.operatorHeaders)
            let spec = #"""
            { "input": { "format": 1, "chapters": [ { "index": 1, "start": 0 }, { "index": 2, "start": 10 } ],
              "streams": [ { "index": 0, "kind": "video", "codec": "h264", "width": 1, "height": 1 },
                           { "index": 1, "kind": "audio", "codec": "ac3", "channels": 2 }, { "index": 2, "kind": "audio", "codec": "ac3", "channels": 2 } ] } }
            """#
            let source = try await client.send("POST", "/v1/sources", body: Data(spec.utf8), headers: Self.operatorHeaders).json(SourceBody.self)

            func answer(_ path: String, _ body: Data) async throws -> (Int, String) {
                let answer = try await client.send("POST", path, body: body, headers: Self.operatorHeaders)
                return (answer.status, answer.bodyText)
            }
            let past = try await answer("/v1/bindings", Self.bindingBody(source: source.id, chapters: (2, 5)))
            #expect(past.0 == 400)
            #expect(past.1.contains("has no chapter 5"))
            #expect(try await answer("/v1/bindings", Self.bindingBody(source: "nothing")).1.contains("no source nothing"))
            #expect(try await answer("/v1/bindings", Self.bindingBody(source: source.id, item: "part9")).1.contains("has no item part9"))

            let binding = try await client.send("POST", "/v1/bindings", body: Self.bindingBody(source: source.id), headers: Self.operatorHeaders).json(BindingBody.self)
            let nope = try await answer("/v1/bindings/\(binding.id)/recipes", Self.application("nope"))
            #expect(nope.0 == 400)
            #expect(nope.1.contains("no ruleset nope"))
            #expect(try await answer("/v1/bindings/\(binding.id)/recipes", Self.application("two", outputs: #"[ { "profile": "hdr" } ]"#)).1.contains("two makes no output for the profile hdr"))
            #expect(try await answer("/v1/bindings/nothing/recipes", Self.application("two")).0 == 404)

            let videoOnly = RulesetDocumentBody(name: "videoonly", document: #"<ruleset format="1" name="videoonly"><video><copy/></video></ruleset>"#)
            _ = try await client.send("PUT", "/v1/rulesets/videoonly", body: try JSONEncoder().encode(videoOnly), headers: Self.operatorHeaders)
            let undecided = try await answer("/v1/bindings/\(binding.id)/recipes", Self.application("videoonly"))
            #expect(undecided.0 == 422)
            #expect(undecided.1.contains("the unqualified output: no rule decides audio 1"))
            let kept = try await client.get("/v1/bindings/\(binding.id)")
            #expect(kept.status == 200, "the binding was never wrong; the rules were incomplete")
            #expect(try kept.json(BindingBody.self).recipes.isEmpty, "and nothing of the failed application is kept")
        }
    }
}

/// A library's standard, set over the API. Last, because it stores a ruleset of its own and the
/// listing of rulesets earlier in the suite counts them.
extension ServerTests {
    @Test func aLibraryNamesItsStandardRuleset() async throws {
        try await withClient { client in
            // A ruleset of its own, so that no other test's versions move.
            let document = Fixture.household.replacingOccurrences(of: #"name="household""#, with: #"name="standard""#)
            let ruleset = RulesetDocumentBody(name: "standard", document: document)
            _ = try await client.send("PUT", "/v1/rulesets/standard", body: try JSONEncoder().encode(ruleset), headers: ["Content-Type": "application/json", "Authorization": "Bearer secret"])
            let headers = ["Content-Type": "application/json", "Authorization": "Bearer secret"]

            #expect(try await client.send("PUT", "/v1/libraries/main/ruleset", body: Data(#"{"ruleset":"standard"}"#.utf8), headers: ["Content-Type": "application/json"]).status == 401)
            #expect(try await client.send("PUT", "/v1/libraries/other/ruleset", body: Data(#"{"ruleset":"standard"}"#.utf8), headers: headers).status == 404)
            let unknown = try await client.send("PUT", "/v1/libraries/main/ruleset", body: Data(#"{"ruleset":"nothing"}"#.utf8), headers: headers)
            #expect(unknown.status == 404, "a ruleset the silo does not hold")
            #expect(!(try await client.get("/v1/libraries").bodyText.contains("\"ruleset\"")), "and nothing changed")

            let set = try await client.send("PUT", "/v1/libraries/main/ruleset", body: Data(#"{"ruleset":"standard"}"#.utf8), headers: headers)
            #expect(set.status == 200)
            #expect(set.bodyText.contains("\"ruleset\":\"standard\""))
            #expect(try await client.get("/v1/libraries").bodyText.contains("\"ruleset\":\"standard\""), "the listing names it")

            let cleared = try await client.send("PUT", "/v1/libraries/main/ruleset", body: Data(#"{"ruleset":null}"#.utf8), headers: headers)
            #expect(cleared.status == 200)
            #expect(!(try await client.get("/v1/libraries").bodyText.contains("\"ruleset\"")))
        }
    }

    @Test func aBranchIsStartedStoredOnAndPromoted() async throws {
        try await withClient { client in
            let headers = ["Content-Type": "application/json", "Authorization": "Bearer secret"]
            let document = Fixture.household.replacingOccurrences(of: #"name="household""#, with: #"name="trialset""#)
            func store(_ branch: String? = nil, upToDateWith: Int? = nil) async throws -> (Int, Int?) {
                struct Body: Encodable { var name: String; var branch: String?; var upToDateWith: Int?; var document: String }
                let answer = try await client.send("PUT", "/v1/rulesets/trialset", body: try JSONEncoder().encode(Body(name: "trialset", branch: branch, upToDateWith: upToDateWith, document: document)), headers: headers)
                return (answer.status, try? answer.json(RulesetDocumentBody.self).version)
            }
            #expect(try await store().1 == 1)

            #expect(try await client.send("POST", "/v1/rulesets/trialset/branches", body: Data(#"{"name":"trial","from":1}"#.utf8), headers: ["Content-Type": "application/json"]).status == 401)
            let started = try await client.send("POST", "/v1/rulesets/trialset/branches", body: Data(#"{"name":"trial","from":1}"#.utf8), headers: headers)
            #expect(started.status == 201)
            #expect(try await client.send("POST", "/v1/rulesets/trialset/branches", body: Data(#"{"name":"trial","from":1}"#.utf8), headers: headers).status == 409, "a name taken")
            #expect(try await client.send("POST", "/v1/rulesets/trialset/branches", body: Data(#"{"name":"other","from":9}"#.utf8), headers: headers).status == 400, "a version not on the standard")
            #expect(try await store("trial").1 == 2)

            // The standard moves on; promotion would lose it, until the branch takes it in.
            #expect(try await store().1 == 3)
            let refused = try await client.send("POST", "/v1/rulesets/trialset/branches/trial/promote", headers: headers)
            #expect(refused.status == 409)
            #expect(refused.bodyText.contains("has not taken in trialset@3"))
            #expect(try await store("trial", upToDateWith: 3).1 == 4)
            let promoted = try await client.send("POST", "/v1/rulesets/trialset/branches/trial/promote", headers: headers)
            #expect(promoted.status == 201)
            #expect(promoted.bodyText.contains("\"version\":5"))

            struct BranchBody: Decodable { var name: String; var base: Int?; var head: Int?; var closed: Bool }
            let branches = try await client.get("/v1/rulesets/trialset/branches").json([BranchBody].self)
            #expect(branches.map(\.name) == ["standard", "trial"])
            #expect(branches[0].head == 5 && branches[1].closed && branches[1].base == 1)
            #expect(try await store("trial").0 == 409, "a closed branch takes no store")
            #expect(try await client.send("POST", "/v1/rulesets/trialset/branches/nowhere/promote", headers: headers).status == 404)
            #expect(try await client.get("/v1/rulesets/nothing/branches").status == 404)
        }
    }

    @Test func theOutOfDateReportAndABranchsImpactAreReadOpenly() async throws {
        try await withClient { client in
            let report = try await client.get("/v1/libraries/main/out-of-date")
            #expect(report.status == 200)
            struct ReportBody: Decodable { var presentations: [OutOfDateBody]; var pending: Int; var placedWithoutJob: Int }
            struct OutOfDateBody: Decodable { var recipe: String; var outcome: String }
            let body = try report.json(ReportBody.self)
            #expect(body.placedWithoutJob >= 2, "the fixture's presentations were placed by hand")
            #expect(try await client.get("/v1/libraries/other/out-of-date").status == 404)
            #expect(try await client.get("/v1/rulesets/trialset/branches/trial/impact").status == 200)
            #expect(try await client.get("/v1/rulesets/trialset/branches/nowhere/impact").status == 404)
            #expect(try await client.get("/v1/rulesets/nothing/branches/trial/impact").status == 404)
        }
    }
}

extension ServerTests {
    /// Commentary first, then four rules, the fifth a condition-less copy: a ruleset read as a recipe
    /// names its rules.
    static let drafted = """
        <ruleset format="1" name="something-else">
          <video><copy/></video>
          <audio id="commentary"><when fact="audio.role" is="commentary"/><encode codec="aac" bitrate="96k" channels="2"/></audio>
          <audio><when fact="audio.lossless" is="true"/><when fact="audio.channels" ge="6"/><copy/></audio>
          <subtitle><when fact="subtitle.language" in="eng, fra"/><copy/></subtitle>
          <audio><copy/></audio>
          <subtitle><drop/></subtitle>
          <output container="mkv"/>
        </ruleset>
        """

    /// A ruleset's versions and reading, a draft checked without a store, and a store based on a head;
    /// under a name of their own, so that no other test's versions move.
    @Test func aRulesetIsReadWholeADraftCheckedAndAStoreBasedOnItsHead() async throws {
        try await withClient { client in
            struct Store: Encodable { var name = "drafted"; var basedOn: Int?; var document: String }
            func store(basedOn: Int?, _ document: String = Self.drafted) async throws -> (status: Int, text: String) {
                let answer = try await client.send("PUT", "/v1/rulesets/drafted", body: try JSONEncoder().encode(Store(basedOn: basedOn, document: document)), headers: Self.operatorHeaders)
                return (Int(answer.status), answer.bodyText)
            }
            #expect(try await store(basedOn: 0).status == 201, "a new name, based on zero")
            #expect(try await store(basedOn: 0).status == 409, "and the name is no longer new")
            #expect(try await store(basedOn: 1).status == 201)
            let stale = try await store(basedOn: 1)
            #expect(stale.status == 409, "a second editor from the same base")
            #expect(stale.text.contains("drafted@2"), "naming the head")
            #expect(try await store(basedOn: nil).status == 201, "without a base, whatever the head")

            struct Version: Decodable, Equatable { var version: Int; var branch: String; var parent: Int?; var presentations: Int }
            struct Summary: Decodable { var name: String; var version: Int; var standard: Int?; var versions: [Version]? }
            let summary = try #require(try await client.get("/v1/rulesets").json([Summary].self).first { $0.name == "drafted" })
            #expect(summary.version == 3 && summary.standard == 3)
            #expect(summary.versions == [
                Version(version: 1, branch: "standard", parent: nil, presentations: 0),
                Version(version: 2, branch: "standard", parent: 1, presentations: 0),
                Version(version: 3, branch: "standard", parent: 2, presentations: 0),
            ])

            struct Condition: Decodable, Equatable { var fact: String; var test: String; var value: String }
            struct Rule: Decodable { var name: String; var scope: String; var conditions: [Condition]; var action: [String: Anything] }
            struct Anything: Decodable { init(from decoder: any Decoder) {} }
            struct Reading: Decodable { var name: String; var rules: [Rule]; var outputs: [[String: String]] }
            struct Document: Decodable { var version: Int; var document: String; var reading: Reading? }
            let read = try await client.get("/v1/rulesets/drafted?version=1").json(Document.self)
            #expect(read.document == Self.drafted, "the document as it was stored")
            let reading = try #require(read.reading)
            #expect(reading.name == "drafted", "named by where it is stored, not by its own name attribute")
            #expect(reading.rules.map(\.name) == ["#1", "commentary", "#3", "#4", "#5", "#6"])
            #expect(reading.rules[1].scope == "audio" && reading.rules[1].conditions == [Condition(fact: "audio.role", test: "is", value: "commentary")])
            #expect(reading.rules[1].action.keys.sorted() == ["encode"])
            #expect(reading.rules[2].conditions.map(\.test) == ["is", "ge"])
            #expect(reading.rules[3].conditions == [Condition(fact: "subtitle.language", test: "in", value: "eng,fra")])
            #expect(reading.rules[4].scope == "audio" && reading.rules[4].conditions.isEmpty && reading.rules[4].action.keys.sorted() == ["copy"])

            // A check reads as a store reads, refuses as a store refuses, and stores nothing.
            let mistyped = Self.drafted.replacingOccurrences(of: #"fact="audio.role""#, with: #"fact="subtitle.forcd""#)
            let checked = try await client.post("/v1/rulesets/drafted/check", json: Store(document: mistyped))
            #expect(checked.status == 400)
            let refusal = try await store(basedOn: nil, mistyped)
            #expect(refusal.status == 400)
            #expect(checked.bodyText == refusal.text, "the detail a store would give")
            let good = try await client.post("/v1/rulesets/drafted/check", json: Store(document: Self.drafted))
            #expect(good.status == 200)
            #expect(try good.json(Reading.self).rules.count == 6, "the reading a read of it would carry")
            #expect(try await client.get("/v1/rulesets").json([Summary].self).first { $0.name == "drafted" }?.version == 3, "no version is added")

            // A draft's impact, openly: nothing placed was made by this ruleset, so nothing changes.
            struct Impact: Encodable { var document: String; var basedOn: Int }
            let impact = try await client.post("/v1/rulesets/drafted/impact", json: Impact(document: Self.drafted, basedOn: 3))
            #expect(impact.status == 200)
            #expect(impact.bodyText == "[]")
            #expect(try await client.post("/v1/rulesets/drafted/impact", json: Impact(document: mistyped, basedOn: 3)).status == 400)
            #expect(try await client.post("/v1/rulesets/drafted/impact", json: Impact(document: Self.drafted, basedOn: 9)).status == 404)
            #expect(try await client.post("/v1/rulesets/nothing/impact", json: Impact(document: Self.drafted, basedOn: 1)).status == 404)
        }
    }
}
