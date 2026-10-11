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

    /// A silo with access whose `household` standard is at `head`, answering checks, impacts, stores,
    /// promotions and library standards as the silo would, and counting the checks it is asked.
    /// The changing silo's state: its standard's head, and how many checks it has been asked.
    private final class SiloState: Sendable {
        let head: Mutex<Int>
        let checks = Mutex(0)

        init(head: Int) { self.head = Mutex(head) }
    }

    private nonisolated static func changingSilo(_ state: SiloState) -> @Sendable (URLRequest) -> (Int, Data)? {
        { request in
            let current = state.head.withLock { $0 }
            let body = request.httpBodyStream.map { stream -> String in
                stream.open()
                defer { stream.close() }
                var data = Data()
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let read = stream.read(&buffer, maxLength: buffer.count)
                    guard read > 0 else { break }
                    data.append(buffer, count: read)
                }
                return String(decoding: data, as: UTF8.self)
            } ?? String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            let commentary = #"<ruleset format=\"1\" name=\"household\">\n<audio id=\"commentary\"><encode codec=\"aac\" bitrate=\"160k\"/></audio>\n</ruleset>"#
            switch (request.httpMethod ?? "GET", request.url?.path ?? "") {
            case (_, "/v1/server"): return (200, Self.serverInfo(bootstrap: false))
            case (_, "/v1/operator"): return (200, Data(#"{"phase":"active"}"#.utf8))
            case ("POST", "/v1/rulesets/household/check"):
                state.checks.withLock { $0 += 1 }
                if body.contains("subtitle.forcd") { return (400, Data(#"{"detail":"subtitle.forcd is not a fact a rule can test"}"#.utf8)) }
                return (200, Data(#"{"name":"household","extraction":{"includeEmbeddedAudioTracks":false,"includeSubtitles":true,"includeEmbeddedSubtitleTracks":true},"rules":[],"outputs":[{"container":"mkv"}]}"#.utf8))
            case ("POST", "/v1/rulesets/household/impact"):
                let one = #"{"recipe":"r%d","outcome":"outOfDate","madeBy":{"ruleset":{"name":"household","version":3},"layers":[]},"checkedAgainst":{"ruleset":{"name":"household"},"layers":[]},"changes":[{"kind":"audio","index":2,"was":{"encode":{"_0":{"codec":"aac","bitrate":"160k","filters":[],"options":{}}}},"now":{"encode":{"_0":{"codec":"aac","bitrate":"96k","filters":[],"options":{}}}}}],"sources":[]}"#
                return (200, Data(("[" + (1...12).map { String(format: one, $0) }.joined(separator: ",") + "]").utf8))
            case ("PUT", "/v1/rulesets/household"):
                if body.contains(#""basedOn":"#) && !body.contains(#""basedOn":\#(current)"#) {
                    return (409, Data(#"{"detail":"household's standard is at household@\#(current)"}"#.utf8))
                }
                return (201, Data(#"{"name":"household","version":\#(current + 1),"branch":"standard","document":"<stored/>"}"#.utf8))
            case (_, "/v1/rulesets"):
                let later = (3...max(3, current)).map { #"{"version":\#($0),"branch":"standard","presentations":0}"# }.joined(separator: ",")
                return (200, Data(#"[{"name":"household","version":\#(current),"standard":\#(current),"versions":[{"version":1,"branch":"standard","presentations":41},{"version":2,"branch":"trial","parent":1,"presentations":0},\#(later)]}]"#.utf8))
            case (_, "/v1/rulesets/household/branches"): return (200, Data(#"[{"name":"standard","head":\#(current),"closed":false},{"name":"trial","base":1,"head":2,"upToDateWith":1,"closed":false}]"#.utf8))
            case (_, "/v1/rulesets/household"):
                let version = request.url?.query?.split(separator: "=").last.flatMap { Int($0) } ?? current
                return (200, Data(#"{"name":"household","version":\#(version),"branch":"\#(version == 2 ? "trial" : "standard")","document":"\#(commentary)"}"#.utf8))
            case (_, "/v1/rulesets/household/branches/trial/impact"): return (200, Data("[]".utf8))
            case ("POST", "/v1/rulesets/household/branches/trial/promote"): return (409, Data(#"{"detail":"household's branch trial has not taken in household@\#(current) from the standard"}"#.utf8))
            case ("PUT", "/v1/libraries/films/ruleset"): return (200, Data(#"{"id":"films","ruleset":"household","containers":1,"presentations":41}"#.utf8))
            case (_, "/v1/libraries"): return (200, Data(#"[{"id":"films","containers":1,"presentations":41}]"#.utf8))
            default: return nil
            }
        }
    }

    private func changingModel(_ state: SiloState) async throws -> (ConsoleModel, AdminConsole.Silo) {
        let store = InMemoryPasskeyStore()
        store.store("held", for: "s1")
        Stub.handler.withLock { $0 = Self.changingSilo(state) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Stub.self]
        let model = ConsoleModel(console: AdminConsole(
            registry: SiloRegistry(),
            passkeys: store,
            session: URLSession(configuration: configuration),
            browse: { [DiscoveredSilo(name: "Fresh Silo", host: "fresh.local", port: 8080)] }
        ), checkDelay: .milliseconds(50))
        await model.refresh()
        let silo = try #require(model.silos.first { $0.id == "s1" })
        model.selected = [silo.id]
        model.section = .rulesets
        await model.loadRulesets(for: silo)
        await model.open(ruleset: "household", of: silo)
        return (model, silo)
    }

    @Test func aDraftIsCheckedAsItIsTypedAndOutlivesItsSection() async throws {
        let state = SiloState(head: 3)
        let (model, silo) = try await changingModel(state)
        let opened = try #require(model.opened[silo.id])
        model.startDraft(.change(opened.document), for: silo)
        await model.settleCheck(for: silo)
        guard case .reading? = model.draftChecks[silo.id] else { Issue.record("a fresh draft is read"); return }

        let base = try #require(model.drafts[silo.id]).text
        model.editDraft(base + "<subtitle><when fact=\"subtitle.forc", for: silo)
        model.editDraft(base + #"<subtitle><when fact="subtitle.forcd" is="true"/><copy/></subtitle>"#, for: silo)
        await model.settleCheck(for: silo)
        #expect(model.draftChecks[silo.id] == .refused("subtitle.forcd is not a fact a rule can test"), "the reading gives way to the silo's refusal")
        #expect(state.checks.withLock { $0 } == 2, "the first draft, then only the text the typing stopped on")

        model.section = .outOfDate
        model.section = .rulesets
        await model.refresh()
        #expect(model.drafts[silo.id]?.text.contains("subtitle.forcd") == true, "the draft outlives its section closing and refreshing")
    }

    @Test func aReviewShowsTheChangeAndImpactAndALandedVersionKeepsTheDraft() async throws {
        let state = SiloState(head: 3)
        let (model, silo) = try await changingModel(state)
        var draft = Draft.change(try #require(model.opened[silo.id]).document)
        draft.text = draft.text.replacingOccurrences(of: #"bitrate="160k""#, with: #"bitrate="96k""#)
        model.startDraft(draft, for: silo)
        await model.settleCheck(for: silo)

        await model.beginReview(for: silo)
        let review = try #require(model.review)
        #expect(review.draft.difference.filter { $0.kind != .same }.map(\.kind) == [.removed, .added], "the one line that changed")
        #expect(review.impact.count == 12, "the twelve with a commentary, each with its encode before and after")
        #expect(review.impact.allSatisfy { $0.changes.first?.was != $0.changes.first?.now })

        state.head.withLock { $0 = 4 }
        await model.store(to: .baseBranch)
        #expect(model.review?.landed?.version == 4, "version 4 is shown")
        #expect(model.drafts[silo.id]?.base == 3, "and the draft is kept")

        model.rebase(on: try #require(model.review?.landed), for: silo)
        #expect(model.drafts[silo.id]?.base == 4 && model.review == nil, "re-based on 4")
        await model.beginReview(for: silo)
        await model.store(to: .baseBranch)
        #expect(model.drafts[silo.id] == nil, "stored, the draft ends")
        #expect(model.opened[silo.id]?.document.version == 5, "and the new version is shown")
    }

    @Test func aRefusedPromotionLeadsToADraftTakingTheStandardIn() async throws {
        let (model, silo) = try await changingModel(SiloState(head: 9))
        await model.beginPromotion(of: "trial", of: "household", on: silo)
        await model.promote()
        let refused = try #require(model.promotion?.refused)
        #expect(refused.notTakenIn.last?.version == 9, "the refusal names version 9")
        #expect(refused.base?.version == 1)

        await model.takeIn(9, on: try #require(model.promotion))
        let draft = try #require(model.drafts[silo.id])
        #expect(draft.base == 2 && draft.baseBranch == "trial" && draft.upToDateWith == 9, "on the branch, from its head, taking 9 in")
    }

    @Test func aLibrarysStandardShowsWhatTheSiloAnswered() async throws {
        let (model, silo) = try await changingModel(SiloState(head: 3))
        await model.loadLibraries(for: silo)
        #expect(model.libraries[silo.id]?.first?.ruleset == nil)
        await model.setStandard("household", of: "films", on: silo)
        #expect(model.libraries[silo.id]?.first?.ruleset == "household")
    }
}
#endif
