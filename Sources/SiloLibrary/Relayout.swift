// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SmdKit
import SmdSidecar

/// One folder renamed, or to be renamed: its path relative to the library before and after.
public struct FolderMove: Hashable, Sendable {
    public var from: String
    public var to: String

    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }
}

/// What laying folders out did, or would do.
public struct RelayoutOutcome: Hashable, Sendable {
    public var moves: [FolderMove] = []
    /// The path each moved container's parent records for it now: its folder's new name and the
    /// sidecar in it.
    public var paths: [ContainerID: String] = [:]
    /// A rename that failed, as a warning; the folder is where it was.
    public var findings: [Finding] = []

    public init() {}
}

/// Renames container folders to the names the layout gives them now, from the top down, and records
/// each new path in the sidecar of the container that holds it. A folder follows its container: the
/// silo keeps it so when it changes what the name is made from, and when asked to lay a library out
/// again. Renaming a folder moves everything in it; no file within it is renamed.
public enum Relayout {
    /// The container holding the one being laid out: its container, its folder relative to the
    /// library as it is when the child is reached, and the folder it was found at, which the child's
    /// folder as found is inside.
    public struct Parent: Sendable {
        public var container: Container
        public var folder: String
        public var found: String

        public init(container: Container, folder: String, found: String? = nil) {
            self.container = container
            self.folder = folder
            self.found = found ?? folder
        }
    }

    /// Lays out every container of a walked library.
    public static func layOut(_ tree: LibraryTree, dryRun: Bool) -> RelayoutOutcome {
        var outcome = RelayoutOutcome()
        for root in tree.roots {
            visit(root, under: nil, in: tree.root, dryRun: dryRun, outcome: &outcome)
        }
        return outcome
    }

    /// Lays out one container and the children the node carries: its own folder when the name the
    /// layout gives it beneath `parent` is no longer the folder's, and each child's within it. The
    /// node's folder is where the container is now, relative to the library; a child's folder is
    /// where it is within the node's, and moves with it.
    public static func layOut(
        _ node: LibraryNode,
        under parent: Parent?,
        in library: URL,
        dryRun: Bool
    ) -> RelayoutOutcome {
        var outcome = RelayoutOutcome()
        let id = node.sidecar.container.id
        visit(node, under: parent, in: library, dryRun: dryRun, outcome: &outcome)
        // The parent was not visited, so its sidecar learns the node's new path here.
        if let parent, let path = outcome.paths[id], !dryRun {
            let folder = parent.folder
            do {
                let url = library.appendingPathComponent(folder).appendingPathComponent(LibraryLayout.sidecarFileName)
                let existing = try Data(contentsOf: url)
                var sidecar = try SidecarFile.sidecar(from: existing)
                sidecar.children[id] = path
                try SidecarFile.data(for: sidecar, updating: existing).write(to: url, options: .atomic)
            } catch {
                outcome.findings.append(unrecorded(in: folder, error))
            }
        }
        return outcome
    }

    /// Lays the node out, then its children within the folder it ends up in, and writes its sidecar
    /// when a child it records moved. Returns the folder's name within its parent's when it moved.
    @discardableResult
    private static func visit(
        _ node: LibraryNode,
        under parent: Parent?,
        in library: URL,
        dryRun: Bool,
        outcome: inout RelayoutOutcome
    ) -> String? {
        let container = node.sidecar.container
        let base = parent.map { "\($0.folder)/" } ?? ""
        let within = within(node.relativeFolder, parentFolder: parent?.found)
        let current = base + within
        let expected =
            parent.map { LibraryLayout.folderName(for: container, in: $0.container) }
            ?? LibraryLayout.folderName(for: container)
        var folder = current
        var moved: String?
        if within != expected {
            let target = base + expected
            do {
                if !dryRun { try rename(current, to: target, in: library) }
                outcome.moves.append(FolderMove(from: current, to: target))
                outcome.paths[container.id] = LibraryLayout.childPath(folder: expected)
                folder = target
                moved = expected
            } catch {
                outcome.findings.append(
                    Finding(
                        .warning,
                        path: "\(current)/\(LibraryLayout.sidecarFileName)",
                        "folder \"\(current)\" could not be renamed \"\(target)\": \(reason(error))"
                    )
                )
            }
        }

        var sidecar = node.sidecar
        var recorded = false
        for child in node.children {
            if let name = visit(
                child,
                under: Parent(container: container, folder: folder, found: node.relativeFolder),
                in: library,
                dryRun: dryRun,
                outcome: &outcome
            ) {
                sidecar.children[child.sidecar.container.id] = LibraryLayout.childPath(folder: name)
                recorded = true
            }
        }
        if recorded, !dryRun {
            do {
                let url = library.appendingPathComponent(folder).appendingPathComponent(LibraryLayout.sidecarFileName)
                try SidecarFile.data(for: sidecar, updating: Data(contentsOf: url)).write(to: url, options: .atomic)
            } catch {
                outcome.findings.append(unrecorded(in: folder, error))
            }
        }
        return moved
    }

    private static func unrecorded(in folder: String, _ error: Error) -> Finding {
        Finding(
            .warning,
            path: "\(folder)/\(LibraryLayout.sidecarFileName)",
            "the new paths of its children could not be recorded: \(reason(error))"
        )
    }

    /// The node's folder within its parent's: what the parent's sidecar records, without the sidecar.
    private static func within(_ folder: String, parentFolder: String?) -> String {
        guard let parentFolder, folder.hasPrefix(parentFolder + "/") else { return folder }
        return String(folder.dropFirst(parentFolder.count + 1))
    }

    /// Renames a folder within the library. A rename that changes only the case of a name goes by way
    /// of another name, since a case-insensitive disk takes the target for the folder itself; any other
    /// target already there is refused.
    private static func rename(_ from: String, to target: String, in library: URL) throws {
        let source = library.appendingPathComponent(from, isDirectory: true)
        let destination = library.appendingPathComponent(target, isDirectory: true)
        if from.lowercased() == target.lowercased() {
            let aside = source.deletingLastPathComponent().appendingPathComponent(
                ".moving \(UUID().uuidString)",
                isDirectory: true
            )
            try FileManager.default.moveItem(at: source, to: aside)
            try FileManager.default.moveItem(at: aside, to: destination)
            return
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw RelayoutError.occupied
        }
        try FileManager.default.moveItem(at: source, to: destination)
    }

    private static func reason(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

enum RelayoutError: Error, LocalizedError {
    case occupied

    var errorDescription: String? {
        switch self {
        case .occupied: "something is already there"
        }
    }
}
