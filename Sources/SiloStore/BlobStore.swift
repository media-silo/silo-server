// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Crypto
import Foundation

/// Images the silo holds by their digest, for a store to put: one file per image under
/// `<state>/blobs`, named by the SHA-256 of its bytes. A blob is put once however often it is sent,
/// and kept a day from when it was last put, unless a store under way names it. `Stores.md`, *Images
/// sent before the store*.
public struct BlobStore: Sendable {
    public let folder: URL
    /// How long a blob nothing names is kept after it was last put.
    public static let lifetime: TimeInterval = 24 * 60 * 60

    public init(folder: URL) throws {
        self.folder = folder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// The SHA-256 of the bytes, in lowercase hexadecimal, as a blob is named.
    public static func digest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Whether a name is one a blob could have: a SHA-256 in lowercase hexadecimal.
    public static func isDigest(_ name: String) -> Bool {
        name.count == 64 && name.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    /// The bytes held under the digest, or nil when none are.
    public func data(of digest: String) -> Data? {
        guard Self.isDigest(digest) else { return nil }
        return try? Data(contentsOf: url(of: digest))
    }

    /// Holds the bytes under their digest, by writing beside the blob and renaming. Bytes already held
    /// are not written again; their day starts again, so a store sent again keeps its images.
    public func put(_ data: Data) throws -> String {
        let digest = Self.digest(of: data)
        let destination = url(of: digest)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: destination.path)
            return digest
        }
        let beside = folder.appendingPathComponent(".\(digest).\(UUID().uuidString)")
        try data.write(to: beside)
        do {
            try FileManager.default.moveItem(at: beside, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: beside)
            if !FileManager.default.fileExists(atPath: destination.path) { throw error }
        }
        return digest
    }

    /// Removes every blob last put longer than a lifetime before `now`, but those `kept` names.
    public func sweep(now: Date = Date(), keeping kept: Set<String> = []) {
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []
        for file in files where !kept.contains(file.lastPathComponent) {
            let put = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let put, now.timeIntervalSince(put) > Self.lifetime {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private func url(of digest: String) -> URL {
        folder.appendingPathComponent(digest)
    }
}
