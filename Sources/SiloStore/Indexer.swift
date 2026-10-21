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
        let known = Dictionary(uniqueKeysWithValues: try index.sidecars(in: library.id).map { ($0.path, $0) })
        var walk = Walk(library: library, index: index, known: known)

        let folders = try FileManager.default.contentsOfDirectory(
            at: library.root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .filter { folder in
            (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                && FileManager.default.fileExists(atPath: folder.appendingPathComponent(SidecarFile.fileName).path)
        }
        guard !folders.isEmpty || known.isEmpty else { throw LibraryUnavailable.empty }
        for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            try visit(folder: folder.lastPathComponent, parent: nil, expecting: nil, walk: &walk)
        }
        var report = walk.report
        let reached = walk.reached

        let gone = Set(known.keys).subtracting(reached)
        if !gone.isEmpty {
            try index.remove(sidecarsAt: Array(gone), in: library.id)
            report.removed = gone.count
        }

        // Sorted, as the walker sorts them: the enumerator's order is the filesystem's.
        var unreferenced: [String] = []
        if let enumerator = FileManager.default.enumerator(
            at: library.root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
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
    public static func refresh(
        folder: String,
        parent: ContainerID?,
        in library: LibraryConfig,
        index: Index
    ) throws -> ScanReport {
        var report = ScanReport()
        let path = "\(folder)/\(SidecarFile.fileName)"
        guard FileManager.default.fileExists(atPath: library.root.appendingPathComponent(path).path) else {
            if try index.sidecars(in: library.id).contains(where: { $0.path == path }) {
                try index.remove(sidecarsAt: [path], in: library.id)
                report.removed = 1
            }
            return report
        }
        var walk = Walk(library: library, index: index, known: [:], descend: false, report: report)
        try visit(folder: folder, parent: parent, expecting: nil, walk: &walk)
        return walk.report
    }

    /// One walk's settings, and what it has gathered so far.
    private struct Walk {
        let library: LibraryConfig
        let index: Index
        /// The sidecars the index held before the walk, by path.
        let known: [String: IndexedSidecar]
        /// Whether to go on to each sidecar's children; a refresh reads one sidecar alone.
        var descend = true
        var reached: Set<String> = []
        var found: [ContainerID: String] = [:]
        var report = ScanReport()
    }

    /// A sidecar's modification time and size, as the index records them to tell it is unchanged.
    private struct SidecarStamp {
        var modified: Date?
        var size: Int?
    }

    /// The container a visited sidecar describes, and the paths of its children's sidecars.
    private struct VisitedSidecar {
        var id: ContainerID
        var children: [ContainerID: String]
    }

    private static func visit(
        folder: String,
        parent: ContainerID?,
        expecting: ContainerID?,
        walk: inout Walk
    ) throws {
        let path = "\(folder)/\(SidecarFile.fileName)"
        guard walk.reached.insert(path).inserted else { return }
        let url = walk.library.root.appendingPathComponent(path)
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let stamp = SidecarStamp(
            modified: attributes?[.modificationDate] as? Date,
            size: (attributes?[.size] as? NSNumber)?.intValue
        )

        let visited: VisitedSidecar
        if let unchanged = try unchangedSidecar(folder: folder, parent: parent, stamp: stamp, walk: &walk) {
            visited = unchanged
        } else {
            guard
                let read = try readSidecar(
                    folder: folder,
                    parent: parent,
                    expecting: expecting,
                    stamp: stamp,
                    walk: &walk
                )
            else { return }
            visited = read
        }

        walk.report.findings += Artwork.findings(
            in: walk.library.root.appendingPathComponent(folder, isDirectory: true),
            sidecar: path
        )

        guard walk.descend else { return }
        try visitChildren(of: visited, folder: folder, walk: &walk)
    }

    /// The sidecar as the index holds it, when its time and size are what the index recorded and the
    /// index holds its container at this folder, not yet reached by the walk. Its children are taken
    /// from the index.
    private static func unchangedSidecar(
        folder: String,
        parent: ContainerID?,
        stamp: SidecarStamp,
        walk: inout Walk
    ) throws -> VisitedSidecar? {
        let path = "\(folder)/\(SidecarFile.fileName)"
        let library = walk.library
        let index = walk.index
        guard let recorded = walk.known[path], recorded.modified == stamp.modified?.timeIntervalSince1970,
            recorded.size == stamp.size,
            let container = try index.container(ContainerID(recorded.container)!, in: library.id),
            container.folder == folder,
            walk.found[container.containerID] == nil
        else { return nil }
        walk.report.unchanged += 1
        let id = container.containerID
        walk.found[id] = folder
        let children = Dictionary(
            uniqueKeysWithValues: try index.children(of: id, in: library.id).map {
                ($0.containerID, "\($0.folder.dropFirst(folder.count + 1))/\(SidecarFile.fileName)")
            }
        )
        if container.parent != parent?.value { try index.setParent(parent, of: id, in: library.id) }
        if let finding = LibraryLayout.folderFinding(
            folder: folder,
            displayTitle: container.displayTitle,
            id: id,
            position: try position(of: id, under: parent, in: library.id, index: index)
        ) {
            walk.report.findings.append(finding)
        }
        return VisitedSidecar(id: id, children: children)
    }

    /// Reads the sidecar and stores what it holds, or nil having reported why it was not: it is
    /// unreadable, describes another container than its parent expects, or describes one the
    /// library already holds elsewhere.
    private static func readSidecar(
        folder: String,
        parent: ContainerID?,
        expecting: ContainerID?,
        stamp: SidecarStamp,
        walk: inout Walk
    ) throws -> VisitedSidecar? {
        let path = "\(folder)/\(SidecarFile.fileName)"
        let library = walk.library
        let index = walk.index
        let document: Data
        let sidecar: Sidecar
        do {
            document = try Data(contentsOf: library.root.appendingPathComponent(path))
            sidecar = try SidecarFile.sidecar(from: document)
        } catch {
            walk.report.findings.append(Finding(.error, path: path, "unreadable: \(error.localizedDescription)"))
            return nil
        }
        if let expecting, sidecar.container.id != expecting {
            walk.report.findings.append(
                Finding(
                    .error,
                    path: path,
                    "describes \(sidecar.container.id) where its parent expects \(expecting)"
                )
            )
            return nil
        }
        // A library holds a container once. The walk keeps the first sidecar it reaches for it and
        // reports any other; a refresh, which walks nothing, keeps the one the index holds while
        // that one is still there.
        let id = sidecar.container.id
        if let first = try walk.found[id]
            ?? (walk.descend ? nil : heldElsewhere(id, than: folder, in: library, index: index))
        {
            walk.report.findings.append(Finding(.error, path: path, "container \(id) is already at \"\(first)\""))
            try index.remove(sidecarsAt: [path], in: library.id)
            return nil
        }
        walk.found[id] = folder
        if let finding = LibraryLayout.folderFinding(
            folder: folder,
            displayTitle: sidecar.container.displayTitle,
            id: id,
            position: try position(of: id, under: parent, in: library.id, index: index)
        ) {
            walk.report.findings.append(finding)
        }
        let entry = IndexEntry(
            sidecar: sidecar,
            document: document,
            library: library.id,
            folder: folder,
            parent: parent,
            modified: stamp.modified,
            size: stamp.size
        )
        walk.report.findings += entry.findings.map { Finding($0.severity, path: path, $0.text) }
        try index.store(entry)
        walk.report.read += 1
        return VisitedSidecar(id: id, children: sidecar.children)
    }

    /// Visits each child the sidecar points at, in the order of their paths, reporting any that is
    /// not a sidecar inside this folder or is not there.
    private static func visitChildren(of visited: VisitedSidecar, folder: String, walk: inout Walk) throws {
        let path = "\(folder)/\(SidecarFile.fileName)"
        for (child, childPath) in visited.children.sorted(by: { $0.value < $1.value }) {
            guard LibraryLayout.isInside(childPath), childPath.hasSuffix("/\(SidecarFile.fileName)") else {
                walk.report.findings.append(
                    Finding(
                        .error,
                        path: path,
                        "child \(child) is at \"\(childPath)\", which is not a sidecar inside this folder"
                    )
                )
                continue
            }
            let childFolder = "\(folder)/\(childPath.dropLast(SidecarFile.fileName.count + 1))"
            guard
                FileManager.default.fileExists(
                    atPath: walk.library.root.appendingPathComponent("\(childFolder)/\(SidecarFile.fileName)").path
                )
            else {
                walk.report.findings.append(
                    Finding(.error, path: path, "child \(child) is at \"\(childPath)\", which does not exist")
                )
                continue
            }
            try visit(folder: childFolder, parent: visited.id, expecting: child, walk: &walk)
        }
    }

    /// The folder of the library's sidecar for the container, when the index holds it at a folder other
    /// than this one and that sidecar is still there.
    private static func heldElsewhere(
        _ id: ContainerID,
        than folder: String,
        in library: LibraryConfig,
        index: Index
    ) throws -> String? {
        guard let row = try index.container(id, in: library.id), row.folder != folder,
            FileManager.default.fileExists(
                atPath: library.root.appendingPathComponent("\(row.folder)/\(SidecarFile.fileName)").path
            )
        else { return nil }
        return row.folder
    }

    /// The container's place among its parent's children, as the index holds the parent: nil for a
    /// root, or for a parent the index does not hold or that does not name it.
    public static func position(
        of id: ContainerID,
        under parent: ContainerID?,
        in library: String,
        index: Index
    ) throws -> LibraryLayout.Position? {
        guard let parent else { return nil }
        let children = try index.items(of: parent, in: library).compactMap {
            $0.childContainer.flatMap(ContainerID.init)
        }
        return LibraryLayout.Position(of: id, among: children)
    }

    private static func relativePath(of url: URL, in root: URL) -> String {
        let rootPath = root.resolvingSymlinksInPath().path
        let path = url.resolvingSymlinksInPath().path
        guard path.hasPrefix(rootPath + "/") else { return path }
        return String(path.dropFirst(rootPath.count + 1))
    }
}
