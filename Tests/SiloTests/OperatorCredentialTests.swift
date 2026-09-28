// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloStore
import Testing
@testable import SiloApp

/// Bootstrap is computable from the state directory alone, and the gate takes the stored
/// credential's hash and nothing else.
struct OperatorCredentialTests {
    private let settings = SettingsStore(Settings(name: "Study"))

    @Test func bootstrapIsTheAbsenceOfACredential() throws {
        let credential = OperatorCredential()
        #expect(credential.current == nil)
        let service = ServerService(identity: ServerIdentity(id: "s1"), settings: settings, credential: credential)
        #expect(service.isInBootstrap)
        #expect(OperatorToken(credential: credential).accepts("Bearer anything") == false)
        #expect(OperatorToken(credential: credential).accepts("Bearer ") == false, "an empty bearer is no door")

        try service.land(StoredOperatorCredential(passkeyHash: NodeStore.hash("horse-battery")))
        #expect(!service.isInBootstrap, "a landed credential ends bootstrap")
        #expect(OperatorToken(credential: credential).accepts("Bearer horse-battery"))
        #expect(!OperatorToken(credential: credential).accepts("Bearer something-else"))
    }

    @Test func theCredentialSurvivesARestartAsAHash() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("silo-credential-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("operator-credential.json")
        let service = ServerService(identity: ServerIdentity(id: "s1"), settings: settings, credential: OperatorCredential(file: file))
        #expect(service.isInBootstrap)
        #expect(OperatorToken(credential: OperatorCredential(file: file)).accepts("Bearer horse-battery") == false)

        try service.land(StoredOperatorCredential(passkeyHash: NodeStore.hash("horse-battery")))

        let reopened = OperatorCredential(file: file)
        #expect(reopened.current != nil)
        #expect(!ServerService(identity: ServerIdentity(id: "s1"), settings: settings, credential: reopened).isInBootstrap, "the boot over it is no longer bootstrap")
        #expect(OperatorToken(credential: reopened).accepts("Bearer horse-battery"))

        let onDisk = String(decoding: try Data(contentsOf: file), as: UTF8.self)
        #expect(!onDisk.contains("horse-battery"))
        #expect(onDisk.contains(NodeStore.hash("horse-battery")), "the hash, and never the passkey")
    }
}
