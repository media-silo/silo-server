// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SmdKit
import SmdSidecar

/// Something a walk or a check noticed. An error is a fact a client would be misled by; a warning
/// is one a person should know. Neither is resolved by whoever found it.
public struct Finding: Hashable, Sendable, Codable, CustomStringConvertible {
    public enum Severity: String, Hashable, Sendable, Codable {
        case error, warning
    }

    public var severity: Severity
    /// The sidecar or file the finding is about, relative to the library root, when it is about one.
    public var path: String?
    public var text: String

    public init(_ severity: Severity, path: String? = nil, _ text: String) {
        self.severity = severity
        self.path = path
        self.text = text
    }

    public var description: String {
        "\(severity.rawValue): \(path.map { "\($0): " } ?? "")\(text)"
    }
}

/// One container's folder as the walk found it.
public struct LibraryNode: Sendable {
    public var folder: URL
    /// The folder relative to the library root, `""` for a root's own.
    public var relativeFolder: String
    public var sidecar: Sidecar
    public var children: [LibraryNode]
    /// The sidecar file's modification time and size: what an index remembers to know whether
    /// to read it again.
    public var modified: Date?
    public var size: Int?

    public var sidecarURL: URL { folder.appendingPathComponent(LibraryLayout.sidecarFileName) }
    public var relativeSidecar: String { relativeFolder.isEmpty ? LibraryLayout.sidecarFileName : "\(relativeFolder)/\(LibraryLayout.sidecarFileName)" }

    public init(folder: URL, relativeFolder: String, sidecar: Sidecar, children: [LibraryNode] = [], modified: Date? = nil, size: Int? = nil) {
        self.folder = folder
        self.relativeFolder = relativeFolder
        self.sidecar = sidecar
        self.children = children
        self.modified = modified
        self.size = size
    }

    /// This node and every node under it, parents first.
    public var flattened: [LibraryNode] {
        [self] + children.flatMap(\.flattened)
    }
}

public struct LibraryTree: Sendable {
    public var root: URL
    public var roots: [LibraryNode]
    public var findings: [Finding]

    public var nodes: [LibraryNode] { roots.flatMap(\.flattened) }

    public func node(for id: ContainerID) -> LibraryNode? {
        nodes.first { $0.sidecar.container.id == id }
    }
}

/// Finds every container in a library: the top-level folders holding a sidecar are the roots, and
/// each sidecar's `smd` paths lead to its children. A sidecar the walk never reaches is a warning,
/// because reachability is what keeps an abandoned draft from changing what a client renders.
public enum LibraryWalker {
    public static func walk(_ root: URL) -> LibraryTree {
        var findings: [Finding] = []
        var reached: Set<String> = []
        var roots: [LibraryNode] = []

        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            let sidecar = folder.appendingPathComponent(LibraryLayout.sidecarFileName)
            guard FileManager.default.fileExists(atPath: sidecar.path) else { continue }
            if let node = read(folder: folder, relativeFolder: folder.lastPathComponent, expecting: nil, reached: &reached, findings: &findings) {
                roots.append(node)
            }
        }

        // The enumerator's order is the filesystem's, which differs between platforms; the
        // findings are sorted so a report reads the same everywhere.
        var unreferenced: [String] = []
        if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator where url.lastPathComponent == LibraryLayout.sidecarFileName {
                let relative = relativePath(of: url, in: root)
                if !reached.contains(relative) { unreferenced.append(relative) }
            }
        }
        for relative in unreferenced.sorted() {
            findings.append(Finding(.warning, path: relative, "a sidecar nothing references"))
        }
        return LibraryTree(root: root, roots: roots, findings: findings)
    }

    private static func read(folder: URL, relativeFolder: String, expecting: ContainerID?, reached: inout Set<String>, findings: inout [Finding]) -> LibraryNode? {
        let url = folder.appendingPathComponent(LibraryLayout.sidecarFileName)
        let relative = "\(relativeFolder)/\(LibraryLayout.sidecarFileName)"
        reached.insert(relative)
        let sidecar: Sidecar
        do {
            sidecar = try SidecarFile.sidecar(from: Data(contentsOf: url))
        } catch {
            findings.append(Finding(.error, path: relative, "unreadable: \(error.localizedDescription)"))
            return nil
        }
        if let expecting, sidecar.container.id != expecting {
            findings.append(Finding(.error, path: relative, "describes \(sidecar.container.id) where its parent expects \(expecting)"))
            return nil
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        var node = LibraryNode(
            folder: folder,
            relativeFolder: relativeFolder,
            sidecar: sidecar,
            modified: attributes?[.modificationDate] as? Date,
            size: (attributes?[.size] as? NSNumber)?.intValue
        )
        for (child, path) in sidecar.children.sorted(by: { $0.value < $1.value }) {
            guard LibraryLayout.isInside(path), path.hasSuffix("/\(LibraryLayout.sidecarFileName)") else {
                findings.append(Finding(.error, path: relative, "child \(child) is at \"\(path)\", which is not a sidecar inside this folder"))
                continue
            }
            let childFolder = folder.appendingPathComponent(String(path.dropLast(LibraryLayout.sidecarFileName.count + 1)))
            let childRelative = "\(relativeFolder)/\(String(path.dropLast(LibraryLayout.sidecarFileName.count + 1)))"
            guard FileManager.default.fileExists(atPath: childFolder.appendingPathComponent(LibraryLayout.sidecarFileName).path) else {
                findings.append(Finding(.error, path: relative, "child \(child) is at \"\(path)\", which does not exist"))
                continue
            }
            if let childNode = read(folder: childFolder, relativeFolder: childRelative, expecting: child, reached: &reached, findings: &findings) {
                node.children.append(childNode)
            }
        }
        return node
    }

    /// A path under the root, relative to it. Textual first, because a placement names folders
    /// it is about to create and standardising resolves `/private` away only for a path that
    /// exists; then with symlinks resolved on both sides, because a directory enumerator hands
    /// back the resolved form of a root that was given as the link.
    public static func relativePath(of url: URL, in root: URL) -> String {
        if let relative = relative(url.path, under: root.path) { return relative }
        if let relative = relative(url.resolvingSymlinksInPath().path, under: root.resolvingSymlinksInPath().path) { return relative }
        return url.path
    }

    private static func relative(_ path: String, under root: String) -> String? {
        var rootPath = root
        while rootPath.hasSuffix("/") && rootPath.count > 1 { rootPath.removeLast() }
        guard path.hasPrefix(rootPath + "/") else { return nil }
        return String(path.dropFirst(rootPath.count + 1))
    }
}
