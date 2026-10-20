// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloLibrary
import SiloStore
import SmdKit

/// Container documents that cannot be read, or that are not one tree.
package struct BadCreate: Error {
    package var reason: String
}

/// What making containers in a library would write, or wrote, and what the silo found in it.
package struct ContainerCreateOutcome: Sendable {
    package var applied: Bool
    package var writes: [SidecarWrite]
    package var findings: [Finding]

    package var errors: [Finding] { findings.filter { $0.severity == .error } }
}

/// A create refused by its findings, with the outcome that carries them; nothing was written.
package struct CreateRefused: Error {
    package var outcome: ContainerCreateOutcome
}

/// Makes a tree of containers in one library with no file: their folders and sidecars, as a placement
/// would make them, beneath a container the library holds or at its top. The silo takes the containers
/// as documents and does not ask where they came from. `Smddb.md`, *What the silo adds*.
enum ContainerMaker {
    static func create(
        _ documents: [String],
        parent: String?,
        in library: LibraryConfig,
        dryRun: Bool,
        libraries: Libraries,
        index: Index
    ) async throws -> ContainerCreateOutcome {
        let containers: [Container]
        do {
            containers = try documents.map { try ContainerFile.container(from: Data($0.utf8)) }
        } catch {
            throw BadCreate(reason: "a container document cannot be read: \(error.localizedDescription)")
        }
        let parentID: ContainerID?
        if let parent {
            guard let id = ContainerID(parent), try index.container(id, in: library.id) != nil else {
                throw NoSuchContainer()
            }
            parentID = id
        } else {
            parentID = nil
        }

        return try await libraries.exclusively(library) {
            var holder: MakingRequest.Holder?
            if let parentID {
                guard let row = try index.container(parentID, in: library.id) else { throw NoSuchContainer() }
                holder = MakingRequest.Holder(
                    folder: library.root.appendingPathComponent(row.folder, isDirectory: true),
                    parent: row.parent.flatMap(ContainerID.init)
                )
            }
            let making: Making
            do {
                making = try Maker.compute(
                    MakingRequest(library: library.root, holder: holder, containers: containers)
                )
            } catch let error as MakingError {
                throw BadCreate(reason: error.localizedDescription)
            }

            // A container the library holds anywhere, in the walk's words for one held twice; the
            // computation has already said so of one whose folder it would use.
            var findings: [Finding] = []
            for container in containers {
                guard let row = try index.container(container.id, in: library.id) else { continue }
                let finding = Finding(.error, "container \(container.id) is already at \"\(row.folder)\"")
                if !making.findings.contains(where: { $0.text == finding.text }) { findings.append(finding) }
            }
            var outcome = ContainerCreateOutcome(
                applied: false,
                writes: making.sidecars,
                findings: findings + making.findings
            )
            guard outcome.errors.isEmpty else { throw CreateRefused(outcome: outcome) }
            guard !dryRun else { return outcome }

            try Maker.apply(making)
            // What was written, the holder first and then the tree from the top down, each under the
            // parent it is filed beneath; nothing else is walked.
            let written = making.sidecars.filter { !$0.creates } + making.sidecars.filter(\.creates)
            for write in written {
                let folder = LibraryWalker.relativePath(of: write.url.deletingLastPathComponent(), in: library.root)
                _ = try Indexer.refresh(folder: folder, parent: write.parent, in: library, index: index)
            }
            outcome.applied = true
            return outcome
        }
    }
}
