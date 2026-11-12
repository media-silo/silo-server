// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloLibrary
import SiloStore
import SmdKit
import SmdSidecar

/// A store's check, made before any of its steps, and the reading of a step in its routes' terms.
extension StoreService {
    // MARK: The check

    /// The first step the store would be refused at, checked before any is made: a document that cannot
    /// be read or names another container, an edit on a sidecar the library no longer holds, an image
    /// the silo does not hold, or a container neither held nor made by an earlier step.
    func check(_ steps: [StoreStep], in library: LibraryConfig) -> Refusal? {
        var made: Set<ContainerID> = []
        for (position, step) in steps.enumerated() {
            do {
                if let reason = try checking(step, in: library, making: &made) {
                    return Refusal(step: position, reason: reason)
                }
            } catch let bad as BadEdit {
                return Refusal(step: position, reason: bad.reason)
            } catch let bad as BadCreate {
                return Refusal(step: position, reason: bad.reason)
            } catch {
                return Refusal(step: position, reason: "\(error)")
            }
        }
        return nil
    }

    private func checking(
        _ step: StoreStep,
        in library: LibraryConfig,
        making made: inout Set<ContainerID>
    ) throws -> String? {
        let earlier = made
        let held = { (id: ContainerID) in
            earlier.contains(id) || ((try? self.index.container(id, in: library.id)) ?? nil) != nil
        }
        let kinds = [step.create != nil, step.edit != nil, step.putArtwork != nil, step.removeArtwork != nil]
        guard kinds.filter({ $0 }).count == 1 else {
            return "a step is exactly one of a create, an edit, a put of artwork or a removal of it"
        }
        if let create = step.create {
            let (containers, _) = try ContainerMaker.reading(
                create.documents,
                attributions: try Self.attributions(create.attributions)
            )
            if let parent = create.parent, !(ContainerID(parent).map(held) ?? false) {
                return Self.unheld(parent)
            }
            made.formUnion(containers.map(\.id))
            return nil
        }
        if let edit = step.edit { return try checking(edit, in: library, made: made, held: held) }
        if let artwork = step.putArtwork { return try checking(artwork, putting: true, held: held) }
        return try step.removeArtwork.flatMap { try checking($0, putting: false, held: held) }
    }

    private func checking(
        _ edit: StoreStep.Edit,
        in library: LibraryConfig,
        made: Set<ContainerID>,
        held: (ContainerID) -> Bool
    ) throws -> String? {
        guard let id = ContainerID(edit.container), held(id) else { return Self.unheld(edit.container) }
        let attributions = try Self.ownAttributions(edit.attributions)
        let container = try ContainerEditor.reading(edit.document, as: id, attributions: attributions)
        return made.contains(id) ? nil : try staleness(of: edit, as: container, in: library)
    }

    private func checking(
        _ artwork: StoreStep.Artwork,
        putting: Bool,
        held: (ContainerID) -> Bool
    ) throws -> String? {
        guard Artwork.kinds.contains(artwork.kind) else { return "\(artwork.kind) is not an artwork kind" }
        guard let id = ContainerID(artwork.container), held(id) else { return Self.unheld(artwork.container) }
        guard putting else { return nil }
        guard let image = artwork.image, blobs.data(of: image) != nil else {
            return "the silo holds no image \(artwork.image ?? "")"
        }
        _ = try Self.attribution(of: artwork)
        return nil
    }

    private static func unheld(_ container: String) -> String {
        "the library does not hold \(container), nor does the store make it before"
    }

    /// Why an edit is on a sidecar the library no longer holds, as the edit's route says it; nil when
    /// it is on the sidecar held, or the sidecar already holds it.
    private func staleness(
        of edit: StoreStep.Edit,
        as container: Container,
        in library: LibraryConfig
    ) throws -> String? {
        guard let id = ContainerID(edit.container), let row = try index.container(id, in: library.id),
            let held = try? Data(
                contentsOf: library.root.appendingPathComponent("\(row.folder)/\(SidecarFile.fileName)")
            )
        else { return nil }
        let digest = IndexedContainer.digest(of: held)
        let attributions = try Self.ownAttributions(edit.attributions)
        let declined = Self.refs(edit.declined)
        guard digest != edit.basedOn,
            !ContainerEditor.holds(held, container, attributions: attributions, declined: declined)
        else { return nil }
        return "the sidecar is now \(digest), not \(edit.basedOn)"
    }

    // MARK: Reading a step

    /// A step's attributions as the routes take them, refused when one is read on no day there is.
    static func attributions(
        _ attributions: [StoreStep.Attribution]?
    ) throws -> [(container: String, attribution: Attribution)] {
        try (attributions ?? []).map {
            guard let read = CalendarDate($0.read) else {
                throw BadCreate(reason: "\($0.read) is not a yyyy-mm-dd date to have read \($0.subject) on")
            }
            return (
                container: $0.container ?? "",
                attribution: Attribution(
                    subject: Attribution.Subject(rawValue: $0.subject),
                    provider: Provider(rawValue: $0.provider),
                    value: $0.value,
                    read: read
                )
            )
        }
    }

    /// A put's attribution to its provider, all of a provider, a value and a read day or none.
    static func attribution(of artwork: StoreStep.Artwork) throws -> Attribution? {
        switch (artwork.provider, artwork.value, artwork.read) {
        case (nil, nil, nil):
            return nil
        case (let provider?, let value?, let read?):
            guard let read = CalendarDate(read) else {
                throw BadCreate(reason: "\(read) is not a yyyy-mm-dd date to have read \(artwork.kind) on")
            }
            return Attribution(
                subject: .artwork(artwork.kind),
                provider: Provider(rawValue: provider),
                value: value,
                read: read
            )
        default:
            throw BadCreate(
                reason: "a put of \(artwork.kind) names a provider, a value and a read day, or none of them"
            )
        }
    }

    static func checkKey(_ key: String) throws {
        let allowed = key.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }
        guard !key.isEmpty, key.count <= 128, allowed else {
            throw BadStoreKey(reason: "a key is letters, digits, \"-\", \"_\" and \".\", up to 128 of them")
        }
    }

    /// An edit's attributions of the container's own fields, as the edit's route takes them.
    static func ownAttributions(_ attributions: [StoreStep.Attribution]?) throws -> [Attribution]? {
        try attributions.map { try Self.attributions($0).map(\.attribution) }
    }

    /// An edit's declined references, as the edit's route takes them.
    static func refs(_ refs: [StoreStep.Ref]?) -> [ExternalRef]? {
        refs?.map { ExternalRef(provider: Provider(rawValue: $0.provider), value: $0.value) }
    }
}
