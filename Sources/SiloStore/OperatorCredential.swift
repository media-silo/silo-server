// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import Synchronization

/// What the silo keeps of the operator's passkey: its SHA-256 as hex, and when it was set — the
/// contents of `operator-credential.json` in the state directory. Never the passkey itself.
public struct StoredOperatorCredential: Hashable, Sendable, Codable {
    public var passkeyHash: String
    public var setAt: Date

    public init(passkeyHash: String, setAt: Date = .now) {
        self.passkeyHash = passkeyHash
        self.setAt = setAt
    }
}

/// The operator credential the daemon located, where the operator token used to be
/// configuration's alone: the environment's token when one is set — it wins whenever it is — and
/// otherwise the stored credential's hash, accepted as a bearer's hash. The crossing point a
/// confirmed setup writes through, so the credential installed this boot authenticates without
/// the environment having anything to say about it. The absence of both is what bootstrap is.
///
/// A `Sendable` class for the reason the stores are: accepting a bearer's hash and landing the
/// credential is one section under one lock, and nothing inside it suspends.
public final class OperatorCredential: Sendable {
    public let file: URL
    private let stored: Mutex<StoredOperatorCredential?>

    public init(file: URL) {
        self.file = file
        stored = Mutex(Self.read(file))
    }

    /// In memory only, for tests.
    public init() {
        file = URL(fileURLWithPath: "/dev/null")
        stored = Mutex(nil)
    }

    /// The stored credential, when one is on disk.
    public var current: StoredOperatorCredential? {
        stored.withLock { $0 }
    }

    /// Whether a bearer's SHA-256 is the stored credential's.
    public func acceptsHash(_ hash: String) -> Bool {
        stored.withLock { $0?.passkeyHash == hash }
    }

    /// Lands the credential on disk atomically and accepts it from that line on.
    public func install(_ credential: StoredOperatorCredential) throws {
        try stored.withLock { stored in
            guard file.path != "/dev/null" else {
                stored = credential
                return
            }
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(credential).write(to: file, options: .atomic)
            stored = credential
        }
    }

    private static func read(_ file: URL) -> StoredOperatorCredential? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(StoredOperatorCredential.self, from: Data(contentsOf: file))
    }
}

/// What a reset file had to say, for the daemon to log loudly.
public enum OperatorCredentialReset: Hashable, Sendable {
    /// A new token's hash is now the operator credential.
    case rotated
    /// The file was empty or whitespace; it is gone and the credential is unchanged.
    case ignored
}

/// Boot-time recovery, the filesystem's own deliberate act: the operator writes
/// `operator-credential.reset` holding a new token, and by the time the boot is done the file is
/// gone and the token's SHA-256 is the operator credential. An empty file is no door — it is
/// removed and the credential left alone. No network route offers this; that is the point of it
/// being a file. Returns `nil` when no reset file exists.
public func processOperatorCredentialReset(from file: URL, into credential: OperatorCredential) throws -> OperatorCredentialReset? {
    guard let raw = try? String(contentsOf: file, encoding: .utf8) else { return nil }
    let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if !token.isEmpty {
        try credential.install(StoredOperatorCredential(passkeyHash: NodeStore.hash(token)))
    }
    try FileManager.default.removeItem(at: file)
    return token.isEmpty ? .ignored : .rotated
}
