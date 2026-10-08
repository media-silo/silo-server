// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloKit
import Synchronization

/// Rulesets as the silo keeps them: `<state>/rulesets/<name>/<version>.xml`, the bytes as they
/// were given so that a hand-written comment survives, the version being the file's name and
/// the name the folder's. A version is never rewritten; a store is always the next number, one
/// sequence per ruleset across all its branches.
///
/// Beside each version, `<version>.json` records its branch and its parent; a version with no
/// record is on the standard, as every version stored before branches was. Each named branch is
/// `branches/<branch>.json`: the standard version it was started from, the one it is up to date
/// with, and whether it has been promoted and closed. `LayeredRulesets.md`, *Branches*.
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
    /// reader refuses is not stored. On the standard when no branch is named; on a branch, that
    /// branch's next version, declaring with `upToDateWith` the standard version it takes in.
    /// Returns the version.
    public func store(_ data: Data, as name: String, branch: String? = nil, upToDateWith: Int? = nil) throws -> Int {
        guard Self.isName(name) else { throw RulesetStoreError.invalidName(name) }
        _ = try RulesetFile.ruleset(from: data)
        return try lock.withLock { _ in
            let onBranch = branch.flatMap { $0 == Self.standard ? nil : $0 }
            var record = VersionRecord(branch: Self.standard, parent: try head(of: name, branch: Self.standard))
            var updatedBranch: BranchRecord?
            if let onBranch {
                guard var found = try branchRecord(name, onBranch) else { throw RulesetStoreError.noSuchBranch(name: name, branch: onBranch) }
                guard !found.closed else { throw RulesetStoreError.branchClosed(name: name, branch: onBranch) }
                if let upToDateWith {
                    guard try branchOf(name, version: upToDateWith) == Self.standard else { throw RulesetStoreError.notOnStandard(name: name, version: upToDateWith) }
                    found.upToDateWith = max(found.upToDateWith, upToDateWith)
                }
                record = VersionRecord(branch: onBranch, parent: try head(of: name, branch: onBranch))
                updatedBranch = found
            }
            let version = (try latestVersion(of: name) ?? 0) + 1
            let url = fileURL(name: name, version: version)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            // The lock makes the number fresh; the check is against a file put there by hand.
            guard !FileManager.default.fileExists(atPath: url.path) else { throw RulesetStoreError.versionExists(name: name, version: version) }
            try data.write(to: url, options: .atomic)
            try write(record, name: name, version: version)
            if let onBranch, let updatedBranch { try write(updatedBranch, name: name, branch: onBranch) }
            return version
        }
    }

    // MARK: - Branches

    /// Every ruleset's first branch, on which every version is stored unless another is named.
    public static let standard = "standard"

    /// A branch as the routes show it: where it started, its head, the standard version it takes
    /// in, and whether it has been promoted.
    public struct Branch: Hashable, Sendable {
        public var name: String
        /// Nil for the standard.
        public var base: Int?
        /// Its latest version, or its base while it has none.
        public var head: Int?
        public var upToDateWith: Int?
        public var closed: Bool
    }

    /// The branch a version is on.
    public func branch(of name: String, version: Int) throws -> String? {
        guard try versions(of: name).contains(version) else { return nil }
        return try branchOf(name, version: version)
    }

    /// A version's parent: the previous version on its branch, or the branch's base for its first.
    public func parent(of name: String, version: Int) throws -> Int? {
        guard try versions(of: name).contains(version) else { return nil }
        if let data = try? Data(contentsOf: recordURL(name: name, version: version)) {
            return try JSONDecoder().decode(VersionRecord.self, from: data).parent
        }
        // A version stored before branches: the standard version before it.
        return try versions(of: name).filter { try $0 < version && branchOf(name, version: $0) == Self.standard }.last
    }

    /// The branch's head: its latest version, or its base while it has none; the standard's latest.
    public func head(of name: String, branch: String) throws -> Int? {
        let own = try versions(of: name).filter { try branchOf(name, version: $0) == branch }
        if let last = own.last { return last }
        return branch == Self.standard ? nil : try branchRecord(name, branch)?.base
    }

    /// The standard first, then each named branch by name.
    public func branches(of name: String) throws -> [Branch] {
        guard !(try versions(of: name)).isEmpty else { return [] }
        var branches = [Branch(name: Self.standard, base: nil, head: try head(of: name, branch: Self.standard), upToDateWith: nil, closed: false)]
        let records = (try? FileManager.default.contentsOfDirectory(at: branchesFolder(name), includingPropertiesForKeys: nil)) ?? []
        for file in records.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let branch = file.deletingPathExtension().lastPathComponent
            guard let record = try branchRecord(name, branch) else { continue }
            branches.append(Branch(name: branch, base: record.base, head: try head(of: name, branch: branch), upToDateWith: record.upToDateWith, closed: record.closed))
        }
        return branches
    }

    /// Starts a branch from a version of the standard.
    public func startBranch(_ branch: String, of name: String, from base: Int) throws -> Branch {
        guard Self.isName(branch), branch != Self.standard else { throw RulesetStoreError.invalidName(branch) }
        return try lock.withLock { _ in
            guard try branchRecord(name, branch) == nil else { throw RulesetStoreError.branchExists(name: name, branch: branch) }
            guard try self.branch(of: name, version: base) == Self.standard else { throw RulesetStoreError.notOnStandard(name: name, version: base) }
            try write(BranchRecord(base: base, upToDateWith: base, closed: false), name: name, branch: branch)
            return Branch(name: branch, base: base, head: base, upToDateWith: base, closed: false)
        }
    }

    /// Promotes a branch: its head's document becomes the standard's next version, and the branch
    /// closes. Refused, naming them, while the standard has versions the branch has not taken in.
    public func promote(_ branch: String, of name: String) throws -> Int {
        try lock.withLock { _ in
            guard var record = try branchRecord(name, branch) else { throw RulesetStoreError.noSuchBranch(name: name, branch: branch) }
            guard !record.closed else { throw RulesetStoreError.branchClosed(name: name, branch: branch) }
            let standard = try versions(of: name).filter { try branchOf(name, version: $0) == Self.standard }
            let missed = standard.filter { $0 > record.upToDateWith }
            guard missed.isEmpty else { throw RulesetStoreError.notTakenIn(name: name, branch: branch, versions: missed) }
            guard let from = try head(of: name, branch: branch), let (_, data) = try document(named: name, version: from) else {
                throw RulesetStoreError.noSuchBranch(name: name, branch: branch)
            }
            let version = (try latestVersion(of: name) ?? 0) + 1
            let url = fileURL(name: name, version: version)
            guard !FileManager.default.fileExists(atPath: url.path) else { throw RulesetStoreError.versionExists(name: name, version: version) }
            try data.write(to: url, options: .atomic)
            try write(VersionRecord(branch: Self.standard, parent: standard.last, promotedFrom: from), name: name, version: version)
            record.closed = true
            try write(record, name: name, branch: branch)
            return version
        }
    }

    // MARK: - Records

    private struct VersionRecord: Codable {
        var branch: String
        var parent: Int?
        var promotedFrom: Int?
    }

    private struct BranchRecord: Codable, Equatable {
        var base: Int
        var upToDateWith: Int
        var closed: Bool
    }

    private static func isName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && !name.hasPrefix(".")
    }

    private func branchOf(_ name: String, version: Int) throws -> String {
        let url = recordURL(name: name, version: version)
        guard let data = try? Data(contentsOf: url) else { return Self.standard }
        return try JSONDecoder().decode(VersionRecord.self, from: data).branch
    }

    private func branchRecord(_ name: String, _ branch: String) throws -> BranchRecord? {
        guard let data = try? Data(contentsOf: branchesFolder(name).appendingPathComponent("\(branch).json")) else { return nil }
        return try JSONDecoder().decode(BranchRecord.self, from: data)
    }

    private func write(_ record: VersionRecord, name: String, version: Int) throws {
        try JSONEncoder().encode(record).write(to: recordURL(name: name, version: version), options: .atomic)
    }

    private func write(_ record: BranchRecord, name: String, branch: String) throws {
        try FileManager.default.createDirectory(at: branchesFolder(name), withIntermediateDirectories: true)
        try JSONEncoder().encode(record).write(to: branchesFolder(name).appendingPathComponent("\(branch).json"), options: .atomic)
    }

    private func fileURL(name: String, version: Int) -> URL {
        folder.appendingPathComponent(name).appendingPathComponent("\(version).\(RulesetFile.fileExtension)")
    }

    private func recordURL(name: String, version: Int) -> URL {
        folder.appendingPathComponent(name).appendingPathComponent("\(version).json")
    }

    private func branchesFolder(_ name: String) -> URL {
        folder.appendingPathComponent(name).appendingPathComponent("branches", isDirectory: true)
    }
}

public enum RulesetStoreError: Error, Equatable, CustomStringConvertible {
    case invalidName(String)
    case versionExists(name: String, version: Int)
    case noSuchBranch(name: String, branch: String)
    case branchExists(name: String, branch: String)
    case branchClosed(name: String, branch: String)
    case notOnStandard(name: String, version: Int)
    case notTakenIn(name: String, branch: String, versions: [Int])

    public var description: String {
        switch self {
        case .invalidName(let name): "\"\(name)\" is not a name a ruleset can have"
        case .versionExists(let name, let version): "\(name)@\(version) is already there; a version is never rewritten"
        case .noSuchBranch(let name, let branch): "\(name) has no branch \(branch)"
        case .branchExists(let name, let branch): "\(name) already has a branch \(branch)"
        case .branchClosed(let name, let branch): "\(name)'s branch \(branch) has been promoted, and is closed"
        case .notOnStandard(let name, let version): "\(name)@\(version) is not on the standard"
        case .notTakenIn(let name, let branch, let versions):
            "\(name)'s branch \(branch) has not taken in \(versions.map { "\(name)@\($0)" }.joined(separator: ", ")) from the standard"
        }
    }
}
