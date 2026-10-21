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

    package var errors: [Finding] { findings.filter { $0.severity == .error } }
}

/// An edit refused by its findings, with the outcome that carries them; nothing was written.
package struct EditRefused: Error {
    package var outcome: ContainerEditOutcome
}

/// Edits a container's own fields in one library's sidecar, onto the sidecar the editor read, and
/// changes no library fact: the write is SmdKit's, which keeps every presentation, child path and rule.
/// `Containers.md`, *The edit*.
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

        return try await libraries.exclusively(library) {
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
            let findings = try findings(
                of: sidecar,
                editing: held,
                to: container,
                at: row,
                in: library,
                index: index
            )
            var outcome = ContainerEditOutcome(
                applied: false,
                sidecar: written,
                digest: IndexedContainer.digest(of: written),
                findings: findings
            )
            guard outcome.errors.isEmpty else { throw EditRefused(outcome: outcome) }
            guard !dryRun else { return outcome }

            try written.write(to: url, options: .atomic)
            _ = try Indexer.refresh(
                folder: row.folder,
                parent: row.parent.flatMap(ContainerID.init),
                in: library,
                index: index
            )
            outcome.applied = true
            return outcome
        }
    }

    /// What the silo finds in an edit: the validator's findings, what it would take away that the
    /// library still names, and a folder no longer named as the layout would name it.
    private static func findings(
        of sidecar: Sidecar,
        editing held: Data,
        to container: Container,
        at row: IndexedContainer,
        in library: LibraryConfig,
        index: Index
    ) throws -> [Finding] {
        let path = "\(row.folder)/\(SidecarFile.fileName)"
        var findings = Validator.check(sidecar).map { finding -> Finding in
            var located = finding
            located.path = path
            return located
        }
        findings += try taken(from: SidecarFile.sidecar(from: held), by: container, in: library, index: index).map {
            Finding(.error, path: path, $0)
        }
        if let folder = LibraryLayout.folderFinding(
            folder: row.folder,
            displayTitle: container.displayTitle,
            id: container.id,
            position: try Indexer.position(
                of: container.id,
                under: row.parent.flatMap(ContainerID.init),
                in: library.id,
                index: index
            )
        ) {
            findings.append(folder)
        }
        return findings
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
