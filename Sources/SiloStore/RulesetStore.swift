// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloKit
import Synchronization

/// Rulesets as the silo keeps them: `<state>/rulesets/<name>/<version>.xml`, the bytes as they
/// were given so that a hand-written comment survives, the version being the file's name and
/// the name the folder's. A version is never rewritten; a store is always the next number.
///
/// A `Sendable` class rather than a struct or an actor, as the other stores are. The next version
/// number has to be read and taken under one lock, and a `Mutex` is non-copyable, so the type
/// that owns it is the one instance every caller shares. An actor would hold the number only
/// until its first suspension; there is none here — the critical section is a read, a decision
/// and a file write — so a lock gives the atomicity outright and keeps every caller synchronous.
public final class RulesetStore: Sendable {
    public let folder: URL
    private let lock = Mutex(())

    public init(folder: URL) throws {
        self.folder = folder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    public func names() throws -> [String] {
        try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .map(\.lastPathComponent)
            .sorted()
    }

    public func versions(of name: String) throws -> [Int] {
        let contents = (try? FileManager.default.contentsOfDirectory(at: folder.appendingPathComponent(name), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return contents.compactMap { $0.pathExtension == RulesetFile.fileExtension ? Int($0.deletingPathExtension().lastPathComponent) : nil }.sorted()
    }

    public func latestVersion(of name: String) throws -> Int? {
        try versions(of: name).last
    }

    /// The document at a version, or the latest.
    public func document(named name: String, version: Int? = nil) throws -> (version: Int, data: Data)? {
        guard let version = try version ?? latestVersion(of: name) else { return nil }
        let url = fileURL(name: name, version: version)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return (version, try Data(contentsOf: url))
    }

    /// The ruleset at a version, or the latest, named and numbered by where it was found.
    public func ruleset(named name: String, version: Int? = nil) throws -> Ruleset? {
        guard let (version, data) = try document(named: name, version: version) else { return nil }
        var ruleset = try RulesetFile.ruleset(from: data)
        ruleset.name = name
        ruleset.version = version
        return ruleset
    }

    /// Stores a document as the next version of the name, having read it first: a document this
    /// reader refuses is not stored. Returns the version.
    public func store(_ data: Data, as name: String) throws -> Int {
        guard !name.isEmpty, !name.contains("/"), !name.hasPrefix(".") else { throw RulesetStoreError.invalidName(name) }
        _ = try RulesetFile.ruleset(from: data)
        return try lock.withLock { _ in
            let version = (try latestVersion(of: name) ?? 0) + 1
            let url = fileURL(name: name, version: version)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            // The lock makes the number fresh; the check is against a file put there by hand.
            guard !FileManager.default.fileExists(atPath: url.path) else { throw RulesetStoreError.versionExists(name: name, version: version) }
            try data.write(to: url, options: .atomic)
            return version
        }
    }

    private func fileURL(name: String, version: Int) -> URL {
        folder.appendingPathComponent(name).appendingPathComponent("\(version).\(RulesetFile.fileExtension)")
    }
}

public enum RulesetStoreError: Error, CustomStringConvertible {
    case invalidName(String)
    case versionExists(name: String, version: Int)

    public var description: String {
        switch self {
        case .invalidName(let name): "\"\(name)\" is not a name a ruleset can have"
        case .versionExists(let name, let version): "\(name)@\(version) is already there; a version is never rewritten"
        }
    }
}
