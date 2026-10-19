// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloLibrary
import SmdKit
import SmdSidecar

/// A library the silo serves: a name, and the folder it is.
public struct LibraryConfig: Hashable, Sendable, Codable {
    public var id: String
    public var root: URL
    /// The library's standard: the ruleset an application to one of its bindings takes when it
    /// names none. Nil for a library with no standard.
    public var ruleset: String?

    public init(id: String, root: URL, ruleset: String? = nil) {
        self.id = id
        self.root = root
        self.ruleset = ruleset
    }
}

/// What a scan did.
public struct ScanReport: Hashable, Sendable {
    public var read: Int = 0
    public var unchanged: Int = 0
    public var removed: Int = 0
    public var findings: [Finding] = []

    public init() {}
}

/// Why a walk was not applied: the library is unavailable, and the index keeps what it holds for it.
public enum LibraryUnavailable: Error, Hashable, Sendable, CustomStringConvertible {
    /// The library's folder does not exist.
    case missing
    /// The folder holds no container at its top level, where the index holds some: an unmounted
    /// Linux mount point is an empty folder, and applying the walk would forget the whole library.
    case empty

    public var description: String {
        switch self {
        case .missing: "its folder does not exist"
        case .empty: "its folder holds no container, where the index holds some"
        }
    }
}

/// Brings the index up to date with a library. The walk is `LibraryWalker`'s, from the top-level
/// folders down each sidecar's `smd` paths, with one difference: a sidecar whose modification
/// time and size are what the index recorded is not read again, and its children are taken from
/// the index instead. A placement re-reads one container by calling this on its folder.
public enum Indexer {
    /// Walks the library and applies what it found, or throws `LibraryUnavailable` having changed
    /// nothing: a folder that is missing, or that holds no container where the index holds some, is
    /// far more often a drive not yet mounted than a library emptied.
    public static func scan(_ library: LibraryConfig, into index: Index) throws -> ScanReport {
        guard folderExists(library) else {
            throw LibraryUnavailable.missing
        }
        var report = ScanReport()
        let known = Dictionary(uniqueKeysWithValues: try index.sidecars(in: library.id).map { ($0.path, $0) })
        var reached: Set<String> = []
        var found: [ContainerID: String] = [:]

        let folders = try FileManager.default.contentsOfDirectory(at: library.root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            .filter { folder in
                (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                    && FileManager.default.fileExists(atPath: folder.appendingPathComponent(SidecarFile.fileName).path)
            }
        guard !folders.isEmpty || known.isEmpty else { throw LibraryUnavailable.empty }
        for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            try visit(folder: folder.lastPathComponent, parent: nil, expecting: nil, library: library, index: index, known: known, reached: &reached, found: &found, report: &report)
        }

        let gone = Set(known.keys).subtracting(reached)
        if !gone.isEmpty {
            try index.remove(sidecarsAt: Array(gone), in: library.id)
            report.removed = gone.count
        }

        // Sorted, as the walker sorts them: the enumerator's order is the filesystem's.
        var unreferenced: [String] = []
        if let enumerator = FileManager.default.enumerator(at: library.root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator where url.lastPathComponent == SidecarFile.fileName {
                let relative = relativePath(of: url, in: library.root)
                if !reached.contains(relative) { unreferenced.append(relative) }
            }
        }
        for relative in unreferenced.sorted() {
            report.findings.append(Finding(.warning, path: relative, "a sidecar nothing references"))
        }
        return report
    }

    /// Whether the library's folder is there, as a folder. Asked of the filesystem each time, since a
    /// URL's resource values are cached and a drive comes and goes.
    public static func folderExists(_ library: LibraryConfig) -> Bool {
        isFolder(atPath: library.root.path) == true
    }

    /// Whether something is at `path` and is a folder, following links: nil when nothing is there.
    public static func isFolder(atPath path: String) -> Bool? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return nil }
        return isDirectory.boolValue
    }

    /// Re-reads one container's sidecar, after a placement wrote it or a request found one of its
    /// files gone. The container must already be reachable, or the next full scan will find it; a
    /// sidecar that is no longer there is forgotten, as the walk would forget it.
    public static func refresh(folder: String, parent: ContainerID?, in library: LibraryConfig, index: Index) throws -> ScanReport {
        var report = ScanReport()
        let path = "\(folder)/\(SidecarFile.fileName)"
        guard FileManager.default.fileExists(atPath: library.root.appendingPathComponent(path).path) else {
            if try index.sidecars(in: library.id).contains(where: { $0.path == path }) {
                try index.remove(sidecarsAt: [path], in: library.id)
                report.removed = 1
            }
            return report
        }
        var reached: Set<String> = []
        var found: [ContainerID: String] = [:]
        try visit(folder: folder, parent: parent, expecting: nil, library: library, index: index, known: [:], reached: &reached, found: &found, report: &report, descend: false)
        return report
    }

    private static func visit(
        folder: String, parent: ContainerID?, expecting: ContainerID?, library: LibraryConfig, index: Index,
        known: [String: IndexedSidecar], reached: inout Set<String>, found: inout [ContainerID: String], report: inout ScanReport,
        descend: Bool = true
    ) throws {
        let path = "\(folder)/\(SidecarFile.fileName)"
        guard reached.insert(path).inserted else { return }
        let url = library.root.appendingPathComponent(path)
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let modified = attributes?[.modificationDate] as? Date
        let size = (attributes?[.size] as? NSNumber)?.intValue

        let children: [ContainerID: String]
        let id: ContainerID
        if let recorded = known[path], recorded.modified == modified?.timeIntervalSince1970, recorded.size == size,
           let container = try index.container(ContainerID(recorded.container)!, in: library.id), container.folder == folder,
           found[container.containerID] == nil {
            report.unchanged += 1
            id = container.containerID
            found[id] = folder
            children = Dictionary(uniqueKeysWithValues: try index.children(of: id, in: library.id).map { ($0.containerID, "\($0.folder.dropFirst(folder.count + 1))/\(SidecarFile.fileName)") })
            if container.parent != parent?.value { try index.setParent(parent, of: id, in: library.id) }
            if let finding = LibraryLayout.folderFinding(folder: folder, displayTitle: container.displayTitle, id: id) {
                report.findings.append(finding)
            }
        } else {
            let document: Data
            let sidecar: Sidecar
            do {
                document = try Data(contentsOf: url)
                sidecar = try SidecarFile.sidecar(from: document)
            } catch {
                report.findings.append(Finding(.error, path: path, "unreadable: \(error.localizedDescription)"))
                return
            }
            if let expecting, sidecar.container.id != expecting {
                report.findings.append(Finding(.error, path: path, "describes \(sidecar.container.id) where its parent expects \(expecting)"))
                return
            }
            // A library holds a container once. The walk keeps the first sidecar it reaches for it and
            // reports any other; a refresh, which walks nothing, keeps the one the index holds while
            // that one is still there.
            id = sidecar.container.id
            if let first = try found[id] ?? (descend ? nil : heldElsewhere(id, than: folder, in: library, index: index)) {
                report.findings.append(Finding(.error, path: path, "container \(id) is already at \"\(first)\""))
                try index.remove(sidecarsAt: [path], in: library.id)
                return
            }
            found[id] = folder
            if let finding = LibraryLayout.folderFinding(folder: folder, displayTitle: sidecar.container.displayTitle, id: id) {
                report.findings.append(finding)
            }
            try index.store(IndexEntry(sidecar: sidecar, document: document, library: library.id, folder: folder, parent: parent, modified: modified, size: size))
            report.read += 1
            children = sidecar.children
        }

        report.findings += Artwork.findings(in: library.root.appendingPathComponent(folder, isDirectory: true), sidecar: path)

        guard descend else { return }
        for (child, childPath) in children.sorted(by: { $0.value < $1.value }) {
            guard LibraryLayout.isInside(childPath), childPath.hasSuffix("/\(SidecarFile.fileName)") else {
                report.findings.append(Finding(.error, path: path, "child \(child) is at \"\(childPath)\", which is not a sidecar inside this folder"))
                continue
            }
            let childFolder = "\(folder)/\(childPath.dropLast(SidecarFile.fileName.count + 1))"
            guard FileManager.default.fileExists(atPath: library.root.appendingPathComponent("\(childFolder)/\(SidecarFile.fileName)").path) else {
                report.findings.append(Finding(.error, path: path, "child \(child) is at \"\(childPath)\", which does not exist"))
                continue
            }
            try visit(folder: childFolder, parent: id, expecting: child, library: library, index: index, known: known, reached: &reached, found: &found, report: &report)
        }
    }

    /// The folder of the library's sidecar for the container, when the index holds it at a folder other
    /// than this one and that sidecar is still there.
    private static func heldElsewhere(_ id: ContainerID, than folder: String, in library: LibraryConfig, index: Index) throws -> String? {
        guard let row = try index.container(id, in: library.id), row.folder != folder,
              FileManager.default.fileExists(atPath: library.root.appendingPathComponent("\(row.folder)/\(SidecarFile.fileName)").path)
        else { return nil }
        return row.folder
    }

    private static func relativePath(of url: URL, in root: URL) -> String {
        let rootPath = root.resolvingSymlinksInPath().path
        let path = url.resolvingSymlinksInPath().path
        guard path.hasPrefix(rootPath + "/") else { return path }
        return String(path.dropFirst(rootPath.count + 1))
    }
}
