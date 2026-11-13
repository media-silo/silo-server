// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloLibrary
import SiloStore
import SmdKit
import SmdSidecar

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
    /// A request's attributions by the container they belong to, refused when one names a container
    /// the request does not carry, or an artwork kind, which a new container has none of.
    private static func attributedFields(
        _ attributions: [(container: String, attribution: Attribution)],
        of containers: [Container]
    ) throws -> [ContainerID: [Attribution]] {
        var attributed: [ContainerID: [Attribution]] = [:]
        for (named, attribution) in attributions {
            guard let id = ContainerID(named), containers.contains(where: { $0.id == id }) else {
                throw BadCreate(reason: "an attribution names \(named), which the request does not carry")
            }
            guard attribution.subject.artworkKind == nil else {
                throw BadCreate(reason: "\(attribution.subject) is artwork, which a new container has none of")
            }
            attributed[id, default: []].append(attribution)
        }
        return attributed
    }

    static func create(
        _ documents: [String],
        parent: String?,
        attributions: [(container: String, attribution: Attribution)] = [],
        in library: LibraryConfig,
        dryRun: Bool,
        libraries: Libraries,
        index: Index
    ) async throws -> ContainerCreateOutcome {
        let (containers, attributedByID) = try reading(documents, attributions: attributions)
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
            try make(
                Request(containers: containers, parent: parentID, attributions: attributedByID),
                in: library,
                dryRun: dryRun,
                index: index
            )
        }
    }

    /// Reads a create's documents and attributions, refused as `BadCreate` when a document cannot be
    /// read or an attribution names a container the request does not carry.
    static func reading(
        _ documents: [String],
        attributions: [(container: String, attribution: Attribution)]
    ) throws -> (containers: [Container], attributions: [ContainerID: [Attribution]]) {
        let containers: [Container]
        do {
            containers = try documents.map { try ContainerFile.container(from: Data($0.utf8)) }
        } catch {
            throw BadCreate(reason: "a container document cannot be read: \(error.localizedDescription)")
        }
        return (containers, try attributedFields(attributions, of: containers))
    }

    /// Containers to make, read, beneath a parent the library holds or at its top.
    struct Request {
        var containers: [Container]
        var parent: ContainerID?
        var attributions: [ContainerID: [Attribution]]
    }

    /// Makes the containers within a turn of the library the caller holds, beneath the parent or at
    /// the top of the library.
    static func make(
        _ request: Request,
        in library: LibraryConfig,
        dryRun: Bool,
        index: Index
    ) throws -> ContainerCreateOutcome {
        let (containers, parentID, attributedByID) = (request.containers, request.parent, request.attributions)
        // Containers made already, as the request makes them, were made: a create sent again, its
        // first answer lost, is answered as the first was, writing nothing.
        if try made(containers, beneath: parentID, attributions: attributedByID, in: library, index: index) {
            return ContainerCreateOutcome(applied: !dryRun, writes: [], findings: [])
        }
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
                MakingRequest(
                    library: library.root,
                    holder: holder,
                    containers: containers,
                    attributions: attributedByID
                )
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

    /// Whether the library holds every container of the request, each filed beneath the container the
    /// request files it beneath, its sidecar holding the document's own fields and the request's
    /// attributions of them.
    private static func made(
        _ containers: [Container],
        beneath parent: ContainerID?,
        attributions: [ContainerID: [Attribution]],
        in library: LibraryConfig,
        index: Index
    ) throws -> Bool {
        for container in containers {
            guard let row = try index.container(container.id, in: library.id) else { return false }
            let holder = containers.first { $0.childContainerIDs.contains(container.id) }?.id ?? parent
            guard row.parent == holder?.description else { return false }
            let url = library.root.appendingPathComponent("\(row.folder)/\(SidecarFile.fileName)")
            guard let held = try? Data(contentsOf: url),
                let set = try? SidecarFile.data(settingContainer: container, in: held), set == held,
                let sidecar = try? SidecarFile.sidecar(from: held)
            else { return false }
            let own = sidecar.attributions.filter { $0.subject.artworkKind == nil }
            guard Set(own) == Set(attributions[container.id] ?? []) else { return false }
        }
        return true
    }
}
