// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import Logging
import ServiceLifecycle
import SiloLibrary
import SiloStore
import SmdKit
import SmdSidecar
import Wire
import WireMVC

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
@BackgroundService
package struct StoreService: Service {
    let libraries: Libraries
    let index: Index
    let records: StoreRecords
    let blobs: BlobStore
    private let logger = Logger(label: "silo.stores")
    /// The stores taken and not yet begun, in the order they were taken, which `run` makes.
    private let queued: AsyncStream<Queued>
    private let queue: AsyncStream<Queued>.Continuation

    @Inject
    package init(libraries: Libraries, index: Index, records: StoreRecords, blobs: BlobStore) {
        self.libraries = libraries
        self.index = index
        self.records = records
        self.blobs = blobs
        (queued, queue) = AsyncStream.makeStream(of: Queued.self)
    }

    /// A store taken: its record, and whether the key was new.
    package struct Taken {
        package var record: StoreRecord
        package var added: Bool
    }

    private struct Queued: Sendable {
        var library: String
        var key: String
    }

    /// Takes a store under its key: the store the key already names when its steps are the same, or a
    /// new one, checked and recorded, and queued for making when the check passes.
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
        if let refusal = check(steps, in: library) { record.state = .refused(refusal) }
        let (taken, added) = try records.adding(record)
        if added, taken.state == .underWay { queue.yield(Queued(library: library.id, key: key)) }
        return Taken(record: taken, added: added)
    }

    package func record(_ key: String, in library: LibraryConfig) throws -> StoreRecord {
        guard let record = records.record(key, in: library.id) else { throw NoSuchStore() }
        return record
    }

    /// Makes the stores while the silo runs: every store under way when it stopped, and then each as it
    /// is taken. Each library has a lane of its own, its stores made one at a time in the order they
    /// were queued, beside the other libraries'. Stopping the silo, or cancelling the run, ends each
    /// store once the step it is making is made, and leaves it under way for the next start to make.
    /// The silo runs it once, among its background services.
    package func run() async {
        await cancelWhenGracefulShutdown { await making() }
    }

    private func making() async {
        for record in records.underWay() { queue.yield(Queued(library: record.library, key: record.key)) }
        await withDiscardingTaskGroup { group in
            var lanes: [String: AsyncStream<String>.Continuation] = [:]
            for await store in queued {
                if let lane = lanes[store.library] {
                    lane.yield(store.key)
                    continue
                }
                let (keys, lane) = AsyncStream.makeStream(of: String.self)
                lanes[store.library] = lane
                lane.yield(store.key)
                group.addTask {
                    for await key in keys { await make(key, of: store.library) }
                }
            }
            for lane in lanes.values { lane.finish() }
        }
    }

    /// Makes a queued store, refused when the silo no longer serves its library.
    private func make(_ key: String, of library: String) async {
        guard let config = libraries.library(library) else {
            _ = try? records.update(key, in: library) {
                $0.state = .refused(Refusal(reason: "the silo no longer serves \(library)"))
            }
            return
        }
        if let record = records.record(key, in: library), record.made > 0 {
            logger.info("resuming the store \(key) of \(library) at step \(record.made)")
        }
        await make(key, in: config)
    }

    /// Makes the store's steps from the first not made, in one turn of the library, recording each as
    /// it is made and ending at the first its route refuses, or, cancelled, before the next step.
    private func make(_ key: String, in library: LibraryConfig) async {
        do {
            try await libraries.exclusively(library) {
                guard let record = records.record(key, in: library.id), record.state == .underWay else { return }
                for position in record.made..<record.steps.count {
                    guard !Task.isCancelled else { return }
                    let made = Set(record.steps[..<position].flatMap(Self.makes))
                    if var refusal = try make(record.steps[position], in: library, after: made) {
                        refusal.step = position
                        try records.update(key, in: library.id) { $0.state = .refused(refusal) }
                        return
                    }
                    try records.update(key, in: library.id) { $0.made = position + 1 }
                }
                try records.update(key, in: library.id) { $0.state = .made }
            }
        } catch {
            logger.error("the store \(key) of \(library.id) stopped: \(error)")
            _ = try? records.update(key, in: library.id) {
                $0.state = .refused(Refusal(step: $0.step, reason: "the store stopped: \(error)"))
            }
        }
    }

    /// Why a store was refused, at the step the check or the step's route refused it.
    typealias Refusal = StoreRecord.Refusal

    /// The containers a step makes: a creation's, or none.
    static func makes(_ step: StoreStep) -> [ContainerID] {
        guard case .create(let create) = step else { return [] }
        return (try? ContainerMaker.reading(create.documents, attributions: []).containers.map(\.id)) ?? []
    }

    /// Makes one step within the turn the store holds, after the steps that made `made`; nil when it is
    /// made, or why it is refused.
    private func make(_ step: StoreStep, in library: LibraryConfig, after made: Set<ContainerID>) throws -> Refusal? {
        do {
            switch step {
            case .create(let create):
                try make(create, in: library)
            case .edit(let edit):
                try make(edit, in: library, after: made)
            case .putArtwork(let artwork):
                return try put(artwork, in: library)
            case .removeArtwork(let artwork):
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

    /// An edit of a container an earlier step made, with no base, is based on the sidecar that step
    /// left, which its sender could not have read.
    private func make(_ edit: StoreStep.Edit, in library: LibraryConfig, after made: Set<ContainerID>) throws {
        guard let id = ContainerID(edit.container) else { throw NoSuchContainer() }
        let attributions = try Self.ownAttributions(edit.attributions)
        var basedOn = edit.basedOn
        if basedOn.isEmpty, made.contains(id), let digest = try digest(of: id, in: library) { basedOn = digest }
        let outcome = try ContainerEditor.edit(
            ContainerEditor.Request(
                id: id,
                container: try ContainerEditor.reading(edit.document, as: id, attributions: attributions),
                basedOn: basedOn,
                attributions: attributions,
                declined: Self.refs(edit.declined)
            ),
            in: library,
            dryRun: false,
            index: index
        )
        if outcome.applied, !outcome.moves.isEmpty { libraries.walkInTurn(library) }
        if outcome.applied { libraries.containerEdited() }
    }

    /// The digest of the sidecar the library holds for a container, read now; nil when it holds none.
    private func digest(of id: ContainerID, in library: LibraryConfig) throws -> String? {
        guard let row = try index.container(id, in: library.id) else { return nil }
        let url = library.root.appendingPathComponent("\(row.folder)/\(SidecarFile.fileName)")
        return (try? Data(contentsOf: url)).map(IndexedContainer.digest)
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
