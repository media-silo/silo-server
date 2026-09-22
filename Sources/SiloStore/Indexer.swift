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

    public init(id: String, root: URL) {
        self.id = id
        self.root = root
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

/// Brings the index up to date with a library. The walk is `LibraryWalker`'s, from the top-level
/// folders down each sidecar's `smd` paths, with one difference: a sidecar whose modification
/// time and size are what the index recorded is not read again, and its children are taken from
/// the index instead. A placement re-reads one container by calling this on its folder.
public enum Indexer {
    public static func scan(_ library: LibraryConfig, into index: Index) throws -> ScanReport {
        var report = ScanReport()
        let known = Dictionary(uniqueKeysWithValues: try index.sidecars(in: library.id).map { ($0.path, $0) })
        var reached: Set<String> = []

        let folders = (try? FileManager.default.contentsOfDirectory(at: library.root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            guard FileManager.default.fileExists(atPath: folder.appendingPathComponent(SidecarFile.fileName).path) else { continue }
            try visit(folder: folder.lastPathComponent, parent: nil, expecting: nil, library: library, index: index, known: known, reached: &reached, report: &report)
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

    /// Re-reads one container's sidecar, after a placement wrote it. The container must already
    /// be reachable, or the next full scan will find it.
    public static func refresh(folder: String, parent: ContainerID?, in library: LibraryConfig, index: Index) throws -> ScanReport {
        var report = ScanReport()
        var reached: Set<String> = []
        try visit(folder: folder, parent: parent, expecting: nil, library: library, index: index, known: [:], reached: &reached, report: &report, descend: false)
        return report
    }

    private static func visit(
        folder: String, parent: ContainerID?, expecting: ContainerID?, library: LibraryConfig, index: Index,
        known: [String: IndexedSidecar], reached: inout Set<String>, report: inout ScanReport, descend: Bool = true
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
           let container = try index.container(ContainerID(recorded.container)!) {
            report.unchanged += 1
            id = container.containerID
            children = Dictionary(uniqueKeysWithValues: try index.children(of: id).map { ($0.containerID, "\($0.folder.dropFirst(folder.count + 1))/\(SidecarFile.fileName)") })
            if container.parent != parent?.rawValue { try index.setParent(parent, of: id) }
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
            try index.store(IndexEntry(sidecar: sidecar, document: document, library: library.id, folder: folder, parent: parent, modified: modified, size: size))
            report.read += 1
            id = sidecar.container.id
            children = sidecar.children
        }

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
            try visit(folder: childFolder, parent: id, expecting: child, library: library, index: index, known: known, reached: &reached, report: &report)
        }
    }

    private static func relativePath(of url: URL, in root: URL) -> String {
        let rootPath = root.resolvingSymlinksInPath().path
        let path = url.resolvingSymlinksInPath().path
        guard path.hasPrefix(rootPath + "/") else { return path }
        return String(path.dropFirst(rootPath.count + 1))
    }
}
