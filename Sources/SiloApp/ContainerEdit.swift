// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloKit
import SiloLibrary
import SiloStore
import SmdKit
import SmdSidecar

/// A container document that cannot be read, or that names another container than the route's.
package struct BadEdit: Error {
    package var reason: String
}

/// An edit made from a sidecar the library no longer holds: it names the digest it does.
package struct EditConflict: Error {
    package var reason: String
}

/// What an edit of a container's own fields would write, or wrote, and what the silo found in it.
package struct ContainerEditOutcome: Sendable {
    package var applied: Bool
    package var sidecar: Data
    package var digest: String
    package var findings: [Finding]
    /// The folders the edit moved, or would move.
    package var moves: [FolderMove] = []

    package var errors: [Finding] { findings.filter { $0.severity == .error } }
}

/// An edit refused by its findings, with the outcome that carries them; nothing was written.
package struct EditRefused: Error {
    package var outcome: ContainerEditOutcome
}

/// Edits a container's own fields in one library's sidecar, onto the sidecar the editor read, and
/// changes no library fact but the paths of the folders it moves: the write is SmdKit's, which keeps
/// every presentation and rule. A folder follows its container, so an edit that changes its title,
/// or the order of its children, renames the folders it names. `Containers.md`, *The edit*;
/// `FolderOrder.md`.
enum ContainerEditor {
    static func edit(
        _ id: ContainerID,
        in library: LibraryConfig,
        document: String,
        basedOn: String,
        dryRun: Bool,
        libraries: Libraries,
        index: Index
    ) async throws -> ContainerEditOutcome {
        let container: Container
        do {
            container = try ContainerFile.container(from: Data(document.utf8))
        } catch {
            throw BadEdit(reason: "the container document cannot be read: \(error.localizedDescription)")
        }
        guard container.id == id else { throw BadEdit(reason: "the document describes \(container.id), not \(id)") }
        guard try index.container(id, in: library.id) != nil else { throw NoSuchContainer() }

        // What moved is walked in the same turn, so it is read back with everything beneath it before
        // any request can look for it where it was.
        return try await libraries.exclusively(
            library,
            walkingAfter: { $0.applied && !$0.moves.isEmpty },
            doing: {
                guard let row = try index.container(id, in: library.id) else { throw NoSuchContainer() }
                let path = "\(row.folder)/\(SidecarFile.fileName)"
                let url = library.root.appendingPathComponent(path)
                let held: Data
                do {
                    held = try Data(contentsOf: url)
                } catch {
                    throw NoSuchContainer()
                }
                let digest = IndexedContainer.digest(of: held)
                guard basedOn == digest else {
                    // A sidecar changed behind the index's back is read now, so the editor's next read
                    // finds the digest this answer names.
                    if held != row.document {
                        _ = try Indexer.refresh(
                            folder: row.folder,
                            parent: row.parent.flatMap(ContainerID.init),
                            in: library,
                            index: index
                        )
                    }
                    throw EditConflict(reason: "the sidecar is now \(digest), not \(basedOn)")
                }

                let written: Data
                let sidecar: Sidecar
                do {
                    written = try SidecarFile.data(settingContainer: container, in: held)
                    sidecar = try SidecarFile.sidecar(from: written)
                } catch {
                    throw BadEdit(reason: "the edit cannot be written: \(error.localizedDescription)")
                }
                let findings = try findings(of: sidecar, editing: held, to: container, in: library, index: index)
                let (node, parent) = try layout(of: row, as: sidecar, held: held, in: library, index: index)
                let planned = Relayout.layOut(node, under: parent, in: library.root, dryRun: true)
                let final = try recording(planned, in: sidecar, written: written)
                var outcome = ContainerEditOutcome(
                    applied: false,
                    sidecar: final,
                    digest: IndexedContainer.digest(of: final),
                    findings: findings.map { located($0, at: path) },
                    moves: planned.moves
                )
                guard outcome.errors.isEmpty else { throw EditRefused(outcome: outcome) }
                guard !dryRun else { return outcome }

                try written.write(to: url, options: .atomic)
                let moved = Relayout.layOut(node, under: parent, in: library.root, dryRun: false)
                outcome.moves = moved.moves
                outcome.findings += moved.findings
                if moved.moves.isEmpty {
                    _ = try Indexer.refresh(
                        folder: row.folder,
                        parent: row.parent.flatMap(ContainerID.init),
                        in: library,
                        index: index
                    )
                } else if moved.paths.count != planned.paths.count {
                    // A rename failed: the sidecar is what the moves that were made left.
                    let now = try recording(moved, in: sidecar, written: written)
                    outcome.sidecar = now
                    outcome.digest = IndexedContainer.digest(of: now)
                }
                outcome.applied = true
                return outcome
            }
        )
    }

    private static func located(_ finding: Finding, at path: String) -> Finding {
        var located = finding
        if located.path == nil { located.path = path }
        return located
    }

    /// The container as the layout sees it: its folder as it is with the sidecar as it will be, and
    /// the holder it is numbered in. Its children are laid out with it only when the edit changes
    /// their order, which is what their names are made from.
    private static func layout(
        of row: IndexedContainer,
        as sidecar: Sidecar,
        held: Data,
        in library: LibraryConfig,
        index: Index
    ) throws -> (LibraryNode, Relayout.Parent?) {
        let before = try SidecarFile.sidecar(from: held).container
        var children: [LibraryNode] = []
        if distinct(before.childContainerIDs) != distinct(sidecar.container.childContainerIDs) {
            for child in distinct(sidecar.container.childContainerIDs) {
                guard let folder = LibraryLayout.recordedFolder(of: child, in: sidecar),
                    let childSidecar = try index.sidecar(child, in: library.id)
                else { continue }
                let relative = "\(row.folder)/\(folder)"
                children.append(
                    LibraryNode(
                        folder: library.root.appendingPathComponent(relative, isDirectory: true),
                        relativeFolder: relative,
                        sidecar: childSidecar
                    )
                )
            }
        }
        let node = LibraryNode(
            folder: library.root.appendingPathComponent(row.folder, isDirectory: true),
            relativeFolder: row.folder,
            sidecar: sidecar,
            children: children
        )
        let parent = try row.parent.flatMap(ContainerID.init).flatMap { id -> Relayout.Parent? in
            guard let parentRow = try index.container(id, in: library.id),
                let parentSidecar = try index.sidecar(id, in: library.id)
            else { return nil }
            return Relayout.Parent(container: parentSidecar.container, folder: parentRow.folder)
        }
        return (node, parent)
    }

    private static func distinct(_ ids: [ContainerID]) -> [ContainerID] {
        var seen: Set<ContainerID> = []
        return ids.filter { seen.insert($0).inserted }
    }

    /// The sidecar's bytes with the new paths of the children that moved recorded, as the layout
    /// writes them; the written bytes when none of its children moved.
    private static func recording(_ outcome: RelayoutOutcome, in sidecar: Sidecar, written: Data) throws -> Data {
        var recorded = sidecar
        for child in sidecar.children.keys {
            if let path = outcome.paths[child] { recorded.children[child] = path }
        }
        guard recorded.children != sidecar.children else { return written }
        return try SidecarFile.data(for: recorded, updating: written)
    }

    /// What the silo finds in an edit: the validator's findings, and what it would take away that the
    /// library still names. A folder no longer named as the layout would name it is moved, not found.
    private static func findings(
        of sidecar: Sidecar,
        editing held: Data,
        to container: Container,
        in library: LibraryConfig,
        index: Index
    ) throws -> [Finding] {
        Validator.check(sidecar)
            + (try taken(from: SidecarFile.sidecar(from: held), by: container, in: library, index: index).map {
                Finding(.error, $0)
            })
    }

    /// What an edit would take away that the library still names: an item the document no longer
    /// declares, of which the library holds presentations or whose container it holds a sidecar for.
    /// What the validator finds of the result — a presentation naming an alternative that is gone, a
    /// track for a feature that is gone — it reports itself.
    private static func taken(
        from held: Sidecar,
        by container: Container,
        in library: LibraryConfig,
        index: Index
    ) throws -> [String] {
        let declared = Set((container.sequences.flatMap(\.items) + container.extras).compactMap { $0.id?.value })
        var reasons: [String] = []
        for entry in held.container.sequences.flatMap(\.items) + held.container.extras {
            guard let item = entry.id?.value, !declared.contains(item) else { continue }
            if !(held.presentations[item] ?? []).isEmpty {
                reasons.append("item \(item) has presentations in this library")
            }
            if let child = entry.childContainer, try index.container(child, in: library.id) != nil {
                reasons.append("item \(item) is a container this library holds")
            }
        }
        return reasons
    }
}
