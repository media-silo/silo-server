// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation

/// A binding's rules while there is no library folder to hold them: before the binding's first
/// presentation is placed, its versions are kept here, one file each under
/// `<state>/binding-rules/<binding id>/<n>.xml`, and the first placement moves them into the
/// library beside the sidecar of the container that holds the binding's item. A staging area, never
/// a second home: once moved, the library's copy is the truth. `LayeredRulesets.md`, *A binding's
/// own rules*.
public struct BindingRulesStore: Sendable {
    public let folder: URL

    public init(folder: URL) throws {
        self.folder = folder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// The versions staged for a binding, in order.
    public func versions(of binding: String) -> [Int] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder(of: binding), includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { $0.pathExtension == "xml" ? Int($0.deletingPathExtension().lastPathComponent) : nil }.sorted()
    }

    /// One staged version's file, whether or not it is there.
    public func file(of binding: String, version: Int) -> URL {
        folder(of: binding).appendingPathComponent("\(version).xml")
    }

    /// Stages a new version after the highest already staged or already elsewhere, never writing
    /// over one: a version is never rewritten. Answers the version.
    public func store(_ document: Data, for binding: String, after highest: Int = 0) throws -> Int {
        try FileManager.default.createDirectory(at: folder(of: binding), withIntermediateDirectories: true)
        var version = max(highest, versions(of: binding).last ?? 0) + 1
        while FileManager.default.fileExists(atPath: file(of: binding, version: version).path) {
            version += 1
        }
        try document.write(to: file(of: binding, version: version), options: .atomic)
        return version
    }

    /// Forgets a binding's staged versions, once the library holds them.
    public func remove(_ binding: String) throws {
        let folder = folder(of: binding)
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
    }

    private func folder(of binding: String) -> URL {
        folder.appendingPathComponent(binding, isDirectory: true)
    }
}
