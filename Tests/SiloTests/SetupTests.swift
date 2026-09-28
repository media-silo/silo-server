// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloStore
import Synchronization
import Testing
@testable import SiloApp

/// The setup pair's life at the service: stage, confirm, and every way the window shuts. The
/// clock is a seam (`stageWindow`, `now`) so the 202→201→410 arc, the collision, the expiry and
/// the restart run without a wait; the routes over this are pinned in `ServerTests`.
struct SetupTests {
    private static func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("silo-setup-\(UUID().uuidString)")
    }

    /// The settings a boot over `state` would open: `settings.json`, created there at first.
    private func settings(at state: URL) -> SettingsStore {
        try! SettingsStore.open(in: state, defaultName: "Silo on attic").0
    }

    @Test func aConfirmedSetupEndsBootstrapAndTheRouteIsGoneThereafter() throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let credential = OperatorCredential(file: folder.appendingPathComponent("operator-credential.json"))
        let service = ServerService(identity: ServerIdentity(id: "s1"), settings: settings(at: folder), credential: credential, stageWindow: 600, now: { .now })

        let staged = try service.stageSetup(passkey: "horse-battery", name: "Living Room Silo")
        #expect(staged.name == "Living Room Silo")
        #expect(staged.confirmBy.timeIntervalSinceNow > 590 && staged.confirmBy.timeIntervalSinceNow <= 600, "the ten-minute window")
        #expect(service.isInBootstrap, "a staged setup ends nothing")
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("operator-credential.json").path), "staging writes nothing")

        try service.confirmSetup(bearer: "horse-battery")

        #expect(!service.isInBootstrap)
        #expect(service.name == "Living Room Silo")
        let (reopened, _) = try SettingsStore.open(in: folder, defaultName: "ignored")
        #expect(reopened.current.name == "Living Room Silo", "a confirm lands the name in settings.json")
        #expect(service.identity.id == "s1", "and re-mints nothing")
        let identity = service.identity
        let onDisk = String(decoding: try Data(contentsOf: folder.appendingPathComponent("operator-credential.json")), as: UTF8.self)
        #expect(onDisk.contains(NodeStore.hash("horse-battery")))
        #expect(!onDisk.contains("horse-battery"), "the hash, and never the passkey")

        #expect(throws: SetupGone.self) { try service.stageSetup(passkey: "again", name: nil) }
        let rebooted = ServerService(identity: identity, settings: settings(at: folder), credential: OperatorCredential(file: folder.appendingPathComponent("operator-credential.json")), stageWindow: 600, now: { .now })
        #expect(!rebooted.isInBootstrap, "gone across restarts")
        #expect(throws: SetupGone.self) { try rebooted.stageSetup(passkey: "again", name: nil) }
    }

    @Test func anEmptyPasskeyIsRefused() throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let service = ServerService(identity: ServerIdentity(id: "s1"), settings: settings(at: folder), credential: OperatorCredential(), stageWindow: 600, now: { .now })

        #expect(throws: EmptyPasskey.self) { try service.stageSetup(passkey: "", name: nil) }
        #expect(service.isInBootstrap, "nothing is staged and bootstrap stands")
        #expect(throws: NothingStaged.self) { try service.confirmSetup(bearer: "") }
    }

    @Test func twoStagesCollideAndTheFirstStillConfirms() throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let credential = OperatorCredential()
        let service = ServerService(identity: ServerIdentity(id: "s1"), settings: settings(at: folder), credential: credential, stageWindow: 600, now: { .now })

        let stage = try service.stageSetup(passkey: "horse-battery", name: nil)
        do {
            _ = try service.stageSetup(passkey: "interloper", name: nil)
            Issue.record("a second stage inside the window")
        } catch let pending as StagePending {
            #expect(pending.confirmBy == stage.confirmBy, "the refusal carries the standing stage's window, none of its own")
        }

        try service.confirmSetup(bearer: "horse-battery")
        #expect(!service.isInBootstrap, "the first stage, not the refused second, is what confirmed")
    }

    @Test func anUnconfirmedStageExpires() throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let clock = Mutex(Date(timeIntervalSince1970: 1_800_000_000))
        let service = ServerService(identity: ServerIdentity(id: "s1"), settings: settings(at: folder), credential: OperatorCredential(), stageWindow: 600, now: { clock.withLock { $0 } })

        let staged = try service.stageSetup(passkey: "horse-battery", name: nil)
        #expect(staged.confirmBy == Date(timeIntervalSince1970: 1_800_000_600))

        clock.withLock { $0 += 601 }
        #expect(throws: NothingStaged.self) { try service.confirmSetup(bearer: "horse-battery") }

        _ = try service.stageSetup(passkey: "second-chance", name: nil)
        try service.confirmSetup(bearer: "second-chance")
        #expect(!service.isInBootstrap, "a fresh stage after the void one confirms")
    }

    @Test func aWrongConfirmDoesNoDamage() throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let service = ServerService(identity: ServerIdentity(id: "s1"), settings: settings(at: folder), credential: OperatorCredential(), stageWindow: 600, now: { .now })

        _ = try service.stageSetup(passkey: "horse-battery", name: nil)
        #expect(throws: ConfirmRefused.self) { try service.confirmSetup(bearer: "wrong") }
        #expect(throws: ConfirmRefused.self) { try service.confirmSetup(bearer: nil) }
        #expect(service.isInBootstrap, "a miss spends nothing")

        try service.confirmSetup(bearer: "horse-battery")
        #expect(!service.isInBootstrap, "the stage stood through the misses")
    }

    @Test func aLiveStageAnswersItsOwnBearerPending() throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let clock = Mutex(Date(timeIntervalSince1970: 1_800_000_000))
        let service = ServerService(identity: ServerIdentity(id: "s1"), settings: settings(at: folder), credential: OperatorCredential(), stageWindow: 600, now: { clock.withLock { $0 } })

        _ = try service.stageSetup(passkey: "horse-battery", name: nil)

        do {
            try service.pendingConfirmBy(bearer: "horse-battery")
            Issue.record("a live staged passkey is pending, not nothing")
        } catch let pending as PendingStage {
            #expect(pending.confirmBy == Date(timeIntervalSince1970: 1_800_000_600), "its own deadline is what it is told")
        }

        #expect(throws: Never.self) { try service.pendingConfirmBy(bearer: "someone-else") }
        #expect(throws: Never.self) { try service.pendingConfirmBy(bearer: nil) }
        #expect(throws: Never.self) { try service.pendingConfirmBy(bearer: "") }

        clock.withLock { $0 += 601 }
        #expect(throws: Never.self) { try service.pendingConfirmBy(bearer: "horse-battery") }

        _ = try service.stageSetup(passkey: "second-chance", name: nil)
        try service.confirmSetup(bearer: "second-chance")
        #expect(!service.isInBootstrap, "expiry voided the old stage; the fresh one confirmed")
    }

    @Test func aConfirmedStageStopsAnsweringItsPasskey() throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let service = ServerService(identity: ServerIdentity(id: "s1"), settings: settings(at: folder), credential: OperatorCredential(), stageWindow: 600, now: { .now })

        _ = try service.stageSetup(passkey: "horse-battery", name: nil)
        #expect(throws: PendingStage.self) { try service.pendingConfirmBy(bearer: "horse-battery") }

        try service.confirmSetup(bearer: "horse-battery")
        #expect(throws: Never.self) { try service.pendingConfirmBy(bearer: "horse-battery") }
    }

    @Test func aRestartForgetsTheStage() throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let identity = ServerIdentity(id: "s1")
        let first = ServerService(identity: identity, settings: settings(at: folder), credential: OperatorCredential(), stageWindow: 600, now: { .now })
        _ = try first.stageSetup(passkey: "horse-battery", name: nil)

        let rebootedCredential = OperatorCredential(file: folder.appendingPathComponent("operator-credential.json"))
        let rebooted = ServerService(identity: identity, settings: settings(at: folder), credential: rebootedCredential, stageWindow: 600, now: { .now })
        #expect(rebootedCredential.current == nil, "the state directory holds no credential")
        #expect(rebooted.isInBootstrap)
        #expect(throws: NothingStaged.self) { try rebooted.confirmSetup(bearer: "horse-battery") }

        _ = try rebooted.stageSetup(passkey: "second-chance", name: nil)
        try rebooted.confirmSetup(bearer: "second-chance")
        #expect(!rebooted.isInBootstrap, "the reboot stages anew and confirms")
    }
}
