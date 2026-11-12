// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Logging
import SiloLibrary
import SiloStore
import SmdKit
import Wire

/// A key the library has a store for, sent with other steps.
package struct StoreKeyTaken: Error {
    package var reason: String
}

/// A key that cannot be one: empty, longer than 128, or holding anything but letters, digits, `-`,
/// `_` and `.`.
package struct BadStoreKey: Error {
    package var reason: String
}

/// The store a library has under a key, which there is none of.
package struct NoSuchStore: Error {}

/// A library's stores: taken under their keys, checked before any step is made, and made in the
/// background, step by step, in one turn of the library, each step as its own route makes it. A store
/// under way when the silo stops is made from the step it was making when it starts again, which
/// each step's route answers as made when it was. `Stores.md`.
@Singleton
package final class StoreService: Sendable {
    let libraries: Libraries
    let index: Index
    let records: StoreRecords
    let blobs: BlobStore
    private let logger = Logger(label: "silo.stores")

    @Inject
    package init(libraries: Libraries, index: Index, records: StoreRecords, blobs: BlobStore) {
        self.libraries = libraries
        self.index = index
        self.records = records
        self.blobs = blobs
    }

    /// A store taken: its record, whether the key was new, and, for a store begun, its making, for
    /// whoever waits on it.
    package struct Taken {
        package var record: StoreRecord
        package var added: Bool
        package var making: Task<Void, Never>?
    }

    /// Takes a store under its key: the store the key already names when its steps are the same, or a
    /// new one, checked and recorded, and begun when the check passes.
    package func take(_ steps: [StoreStep], key: String, in library: LibraryConfig) throws -> Taken {
        try Self.checkKey(key)
        records.sweep()
        if let held = records.record(key, in: library.id) {
            guard held.steps == steps else {
                throw StoreKeyTaken(reason: "\(key) names a store of other steps in \(library.id)")
            }
            return Taken(record: held, added: false)
        }
        var record = StoreRecord(library: library.id, key: key, steps: steps)
        if let refusal = check(steps, in: library) {
            record.state = .refused
            record.step = refusal.step
            record.reason = refusal.reason
        }
        let (taken, added) = try records.adding(record)
        guard added, taken.state == .underWay else { return Taken(record: taken, added: added) }
        return Taken(record: taken, added: true, making: Task.detached { [self] in await make(key, in: library) })
    }

    package func record(_ key: String, in library: LibraryConfig) throws -> StoreRecord {
        guard let record = records.record(key, in: library.id) else { throw NoSuchStore() }
        return record
    }

    /// Makes every store under way, from the step each was making: what the silo does when it starts.
    package func resume() async {
        for record in records.underWay() {
            guard let library = libraries.library(record.library) else {
                _ = try? records.update(record.key, in: record.library) {
                    $0.state = .refused
                    $0.reason = "the silo no longer serves \(record.library)"
                }
                continue
            }
            logger.info("resuming the store \(record.key) of \(record.library) at step \(record.made)")
            await make(record.key, in: library)
        }
    }

    /// Makes the store's steps from the first not made, in one turn of the library, recording each as
    /// it is made and ending at the first its route refuses.
    private func make(_ key: String, in library: LibraryConfig) async {
        do {
            try await libraries.exclusively(library) { [self] in
                guard let record = records.record(key, in: library.id), record.state == .underWay else { return }
                for position in record.made..<record.steps.count {
                    try records.update(key, in: library.id) { $0.step = position }
                    if let refusal = try make(record.steps[position], in: library) {
                        try records.update(key, in: library.id) {
                            $0.state = .refused
                            $0.reason = refusal.reason
                            $0.findings = refusal.findings
                        }
                        return
                    }
                    try records.update(key, in: library.id) { $0.made = position + 1 }
                }
                try records.update(key, in: library.id) {
                    $0.state = .made
                    $0.step = nil
                }
            }
        } catch {
            logger.error("the store \(key) of \(library.id) stopped: \(error)")
            _ = try? records.update(key, in: library.id) {
                $0.state = .refused
                $0.reason = "the store stopped: \(error)"
            }
        }
    }

    /// Why a step was refused, in its route's words, with its findings when it gave them.
    struct Refusal {
        var step = 0
        var reason: String
        var findings: [StoreRecord.Finding]?
    }

    /// Makes one step within the turn the store holds; nil when it is made, or why it is refused.
    private func make(_ step: StoreStep, in library: LibraryConfig) throws -> Refusal? {
        do {
            if let create = step.create {
                try make(create, in: library)
            } else if let edit = step.edit {
                try make(edit, in: library)
            } else if let artwork = step.putArtwork {
                return try put(artwork, in: library)
            } else if let artwork = step.removeArtwork {
                guard let id = ContainerID(artwork.container),
                    try ArtworkController.remove(artwork.kind, of: id, in: library, index: index)
                else { throw NoSuchContainer() }
            }
            return nil
        } catch {
            guard let refusal = Self.refusal(of: error) else { throw error }
            return refusal
        }
    }

    private func make(_ create: StoreStep.Create, in library: LibraryConfig) throws {
        let (containers, attributions) = try ContainerMaker.reading(
            create.documents,
            attributions: try Self.attributions(create.attributions)
        )
        _ = try ContainerMaker.make(
            ContainerMaker.Request(
                containers: containers,
                parent: create.parent.flatMap(ContainerID.init),
                attributions: attributions
            ),
            in: library,
            dryRun: false,
            index: index
        )
    }

    private func make(_ edit: StoreStep.Edit, in library: LibraryConfig) throws {
        guard let id = ContainerID(edit.container) else { throw NoSuchContainer() }
        let attributions = try Self.ownAttributions(edit.attributions)
        let outcome = try ContainerEditor.edit(
            ContainerEditor.Request(
                id: id,
                container: try ContainerEditor.reading(edit.document, as: id, attributions: attributions),
                basedOn: edit.basedOn,
                attributions: attributions,
                declined: Self.refs(edit.declined)
            ),
            in: library,
            dryRun: false,
            index: index
        )
        if outcome.applied, !outcome.moves.isEmpty { libraries.walkInTurn(library) }
    }

    private func put(_ artwork: StoreStep.Artwork, in library: LibraryConfig) throws -> Refusal? {
        guard let id = ContainerID(artwork.container) else { throw NoSuchContainer() }
        guard let digest = artwork.image, let image = blobs.data(of: digest),
            let format = Artwork.Format(signatureOf: image)
        else { return Refusal(reason: "the silo holds no image \(artwork.image ?? "")") }
        let put = ArtworkController.Put(
            image: image,
            format: format,
            kind: artwork.kind,
            attribution: try Self.attribution(of: artwork)
        )
        guard try ArtworkController.put(put, of: id, in: library, index: index) else { throw NoSuchContainer() }
        return nil
    }

    /// A step's route's refusal in its words, with its findings when it gave them; nil for an error no
    /// route answers with.
    private static func refusal(of error: any Error) -> Refusal? {
        switch error {
        case let refused as EditRefused: refusal(refused.outcome.findings)
        case let refused as CreateRefused: refusal(refused.outcome.findings)
        case let conflict as EditConflict: Refusal(reason: conflict.reason)
        case let bad as BadEdit: Refusal(reason: bad.reason)
        case let bad as BadCreate: Refusal(reason: bad.reason)
        case is NoSuchContainer: Refusal(reason: "the library does not hold the container")
        default: nil
        }
    }

    private static func refusal(_ findings: [Finding]) -> Refusal {
        let errors = findings.filter { $0.severity == .error }
        return Refusal(
            reason: errors.map(\.text).joined(separator: "; "),
            findings: findings.map {
                StoreRecord.Finding(severity: $0.severity == .error ? "error" : "warning", path: $0.path, text: $0.text)
            }
        )
    }
}
