// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloStore
import Testing
@testable import SiloApp

/// Bootstrap is computable from the state directory and the environment, the gate takes the
/// stored credential where the environment is silent, and the environment wins over both.
struct OperatorCredentialTests {
    private func config(at state: URL, token: String?) -> SiloConfig {
        SiloConfig(host: "0.0.0.0", port: 8080, stateDirectory: state, libraries: [], operatorToken: token)
    }

    @Test func bootstrapIsTheAbsenceOfACredentialOrAnEnvironmentToken() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("silo-credential-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }

        let credential = OperatorCredential()
        #expect(credential.current == nil)
        let service = ServerService(identity: ServerIdentity(id: "s1", name: "Study"), config: config(at: folder, token: nil), credential: credential)
        #expect(service.isInBootstrap)
        #expect(OperatorToken(config: config(at: folder, token: nil), credential: credential).accepts("Bearer anything") == false)

        try service.land(StoredOperatorCredential(passkeyHash: NodeStore.hash("horse-battery")))
        #expect(!service.isInBootstrap, "a landed credential ends bootstrap")
        #expect(OperatorToken(config: config(at: folder, token: nil), credential: credential).accepts("Bearer horse-battery"))
        #expect(OperatorToken(config: config(at: folder, token: "env"), credential: credential).accepts("Bearer env"), "an environment token ends bootstrap too")
    }

    @Test func theCredentialSurvivesARestartAsAHash() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("silo-credential-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("operator-credential.json")
        let service = ServerService(identity: ServerIdentity(id: "s1", name: "Study"), config: config(at: folder, token: nil), credential: OperatorCredential(file: file))
        #expect(service.isInBootstrap)
        #expect(OperatorToken(config: config(at: folder, token: nil), credential: OperatorCredential(file: file)).accepts("Bearer horse-battery") == false)

        try service.land(StoredOperatorCredential(passkeyHash: NodeStore.hash("horse-battery")))

        let reopened = OperatorCredential(file: file)
        #expect(reopened.current != nil)
        #expect(!ServerService(identity: ServerIdentity(id: "s1", name: "Study"), config: config(at: folder, token: nil), credential: reopened).isInBootstrap, "the boot over it is no longer bootstrap")
        #expect(OperatorToken(config: config(at: folder, token: nil), credential: reopened).accepts("Bearer horse-battery"))

        let onDisk = String(decoding: try Data(contentsOf: file), as: UTF8.self)
        #expect(!onDisk.contains("horse-battery"))
        #expect(onDisk.contains(NodeStore.hash("horse-battery")), "the hash, and never the passkey")
    }

    @Test func theEnvironmentWinsOverTheStoredCredential() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("silo-credential-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("operator-credential.json")
        let writer = JSONEncoder()
        writer.dateEncodingStrategy = .iso8601
        try writer.encode(StoredOperatorCredential(passkeyHash: NodeStore.hash("stored"))).write(to: file)
        let credential = OperatorCredential(file: file)

        #expect(OperatorToken(config: config(at: folder, token: nil), credential: credential).accepts("Bearer stored"))
        let gated = OperatorToken(config: config(at: folder, token: "env"), credential: credential)
        #expect(gated.accepts("Bearer env"))
        #expect(!gated.accepts("Bearer stored"), "where the environment speaks, the state is silent")
    }
}
