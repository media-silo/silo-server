// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloStore
import Testing

/// Recovery through the filesystem: the reset file rotates the credential and is gone, an empty
/// one is removed without touching anything, and a boot with no file does nothing at all.
struct OperatorCredentialResetTests {
    private static func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("silo-reset-\(UUID().uuidString)")
    }

    @Test func theResetFileRotatesTheCredential() throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let credential = OperatorCredential(file: folder.appendingPathComponent("operator-credential.json"))
        try credential.install(StoredOperatorCredential(passkeyHash: NodeStore.hash("old-token")))

        let reset = folder.appendingPathComponent("operator-credential.reset")
        try Data("new-token\n".utf8).write(to: reset)

        #expect(try processOperatorCredentialReset(from: reset, into: credential) == .rotated)
        #expect(!FileManager.default.fileExists(atPath: reset.path), "the file is gone")
        #expect(credential.acceptsHash(NodeStore.hash("new-token")))
        #expect(!credential.acceptsHash(NodeStore.hash("old-token")), "the old passkey is refused")

        let reopened = OperatorCredential(file: folder.appendingPathComponent("operator-credential.json"))
        #expect(reopened.acceptsHash(NodeStore.hash("new-token")), "the rotation is the stored credential's now")
    }

    @Test func anEmptyFileIsNoDoor() throws {
        let folder = Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let credential = OperatorCredential(file: folder.appendingPathComponent("operator-credential.json"))
        try credential.install(StoredOperatorCredential(passkeyHash: NodeStore.hash("kept-token")))

        let reset = folder.appendingPathComponent("operator-credential.reset")
        try Data("  \n\t\n".utf8).write(to: reset)

        #expect(try processOperatorCredentialReset(from: reset, into: credential) == .ignored)
        #expect(!FileManager.default.fileExists(atPath: reset.path), "it is removed")
        #expect(credential.acceptsHash(NodeStore.hash("kept-token")), "the credential is unchanged")
    }

    @Test func noFileIsNoReset() throws {
        let folder = Self.folder()
        let credential = OperatorCredential()
        #expect(try processOperatorCredentialReset(from: folder.appendingPathComponent("operator-credential.reset"), into: credential) == nil)
        #expect(credential.current == nil)
    }
}
