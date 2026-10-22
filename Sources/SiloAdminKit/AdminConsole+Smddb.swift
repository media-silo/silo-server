// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloClient
import SmdKit
import SmdSidecar

// MARK: - smddb

/// smddb as the console reaches it: through SmdKit's client, which on this Mac is a clone of the data
/// repository. The console reads containers from it, asks it for a provisional id, and offers it
/// contributions; it never commits, pulls or pushes, and the silo never learns where a container came
/// from. `Smddb.md`.
extension AdminConsole {
    /// How a library's container stands against smddb's record of the same id.
    public enum Standing: Hashable, Sendable {
        /// The library's own fields are smddb's.
        case matches
        /// They differ; smddb's record is carried.
        case differs(Container)
        /// smddb has no container with the id.
        case absent
    }

    /// How a library's sidecar stands against smddb: the two documents compared, the silo not asked.
    public nonisolated static func standing(
        of sidecar: Data,
        in database: any ContainerDatabase
    ) async throws -> Standing {
        let held = try SidecarFile.sidecar(from: sidecar).container
        guard let record = try await database.container(held.id) else { return .absent }
        return record == held ? .matches : .differs(record)
    }

    /// smddb's containers whose title holds the text, ignoring case and diacritics, or that carry it as
    /// a provider's id, alone or as `provider:value`; every root when the text is empty. A filter over
    /// the listing, which smddb's first principle keeps small.
    public nonisolated static func search(
        _ text: String,
        in database: any ContainerDatabase
    ) async throws -> [Container] {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return try await database.roots() }
        return try await database.containers().filter { container in
            container.displayTitle.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || container.externalRefs.contains {
                    $0.value == query || "\($0.provider.rawValue):\($0.value)" == query
                }
        }
    }

    // MARK: Import

    /// What importing a container from smddb into a library would make: the container the library
    /// holds that it goes beneath, if any; smddb's containers between that one and the picked one,
    /// which the library holds none of; and the picked one's descendants in smddb, with those the
    /// library holds set apart, since they are shown and cannot be chosen.
    public struct ImportPlan: Hashable, Sendable {
        public var library: String
        public var picked: Container
        /// The nearest of the picked container's ancestors in smddb that the library holds.
        public var parent: ContainerID?
        /// The ancestors below the parent, top first, which the import makes too.
        public var ancestors: [Container]
        /// The picked container's descendants in smddb that the library does not hold, top down.
        public var descendants: [Container]
        /// Its descendants the library holds already, as smddb has them.
        public var held: [Container]

        /// The containers the plan knows: the picked one, its descendants, and those held.
        private var known: [Container] { [picked] + descendants + held }

        /// A container's children in the plan that the library does not hold, in the order its
        /// document names them: what the import can make beneath it.
        public func children(of id: ContainerID) -> [Container] {
            guard let container = known.first(where: { $0.id == id }) else { return [] }
            return container.childContainerIDs.compactMap { child in descendants.first { $0.id == child } }
        }

        /// A container's children in the plan that the library holds already, in the order its
        /// document names them: shown beneath it, and not chosen.
        public func heldChildren(of id: ContainerID) -> [Container] {
            guard let container = known.first(where: { $0.id == id }) else { return [] }
            return container.childContainerIDs.compactMap { child in held.first { $0.id == child } }
        }

        /// Every container the import could make below one, children first and then theirs, depth
        /// first: what an all-or-none choice for its children covers.
        public func subtree(of id: ContainerID) -> [ContainerID] {
            children(of: id).flatMap { [$0.id] + subtree(of: $0.id) }
        }

        /// The documents an import makes when `chosen` are the descendants chosen: every ancestor, the
        /// picked container, and each chosen descendant whose parent in smddb is made too.
        public func documents(choosing chosen: Set<ContainerID>) -> [String] {
            var made: Set<ContainerID> = Set(ancestors.map(\.id) + [picked.id])
            var containers = ancestors + [picked]
            for descendant in descendants where chosen.contains(descendant.id) {
                guard containers.contains(where: { $0.childContainerIDs.contains(descendant.id) }) else { continue }
                guard !made.contains(descendant.id) else { continue }
                made.insert(descendant.id)
                containers.append(descendant)
            }
            return containers.map { String(decoding: ContainerFile.data(for: $0), as: UTF8.self) }
        }
    }

    /// What picking a container in smddb for a library comes to: a plan to make it, or, for a container
    /// the library already holds, an edit draft whose document is smddb's, based on the library's
    /// sidecar, since importing onto a held container is an edit.
    public enum ImportStart: Hashable, Sendable {
        case plan(ImportPlan)
        case held(ContainerDraft)
    }

    /// Works out the import of a container from smddb into a library, asking the silo which of
    /// smddb's containers the library holds.
    public func planImport(
        _ id: ContainerID,
        into library: String,
        of silo: Silo,
        from database: any ContainerDatabase
    ) async throws -> ImportStart {
        let all = try await database.containers()
        guard let picked = all.first(where: { $0.id == id }) else {
            throw SettingsRefused(reason: "smddb has no \(id)")
        }
        if try await holds(id, in: library, of: silo) {
            return .held(try await draft(fromSmddb: picked, in: library, of: silo))
        }
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var parentOf: [ContainerID: ContainerID] = [:]
        for container in all {
            for child in container.childContainerIDs where parentOf[child] == nil { parentOf[child] = container.id }
        }

        var ancestors: [Container] = []
        var parent: ContainerID?
        var cursor = id
        while let above = parentOf[cursor], let container = byID[above] {
            if try await holds(above, in: library, of: silo) {
                parent = above
                break
            }
            ancestors.insert(container, at: 0)
            cursor = above
        }

        var descendants: [Container] = []
        var held: [Container] = []
        var queue = picked.childContainerIDs
        while !queue.isEmpty {
            let next = queue.removeFirst()
            guard let container = byID[next] else { continue }
            if try await holds(next, in: library, of: silo) {
                held.append(container)
                continue
            }
            descendants.append(container)
            queue += container.childContainerIDs
        }
        return .plan(
            ImportPlan(
                library: library,
                picked: picked,
                parent: parent,
                ancestors: ancestors,
                descendants: descendants,
                held: held
            )
        )
    }

    /// How an import, or its dry run, ended: what it made or would make; or the findings that refused
    /// it, with, when the parent's sidecar does not name the container below it, an edit draft of the
    /// parent whose document is smddb's, to be stored first.
    public enum ImportOutcome: Hashable, Sendable {
        case wouldMake(SiloClient.ContainerCreateResult)
        case made(SiloClient.ContainerCreateResult)
        case refused(SiloClient.ContainerCreateResult, parentFromSmddb: ContainerDraft?)
    }

    /// Imports the plan's containers, with the descendants chosen, or asks for its dry run.
    public func importContainers(
        _ plan: ImportPlan,
        choosing chosen: Set<ContainerID>,
        dryRun: Bool,
        of silo: Silo,
        from database: any ContainerDatabase
    ) async throws -> ImportOutcome {
        let documents = plan.documents(choosing: chosen)
        let result: SiloClient.ContainerCreateResult
        do {
            result = try await withOperator(silo) {
                try await $0.create(containers: documents, parent: plan.parent?.value, in: plan.library, dryRun: dryRun)
            }
        } catch SiloClientError.status(422, let body) {
            guard
                let refused = try? SiloClient.decoder.decode(
                    SiloClient.ContainerCreateResult.self,
                    from: Data(body.utf8)
                )
            else { throw StoreRefused(reason: Self.detail(body)) }
            guard let parent = plan.parent,
                refused.findings.contains(where: { $0.text.hasPrefix("\(parent) does not name ") }),
                let record = try await database.container(parent)
            else { return .refused(refused, parentFromSmddb: nil) }
            return .refused(refused, parentFromSmddb: try await draft(fromSmddb: record, in: plan.library, of: silo))
        } catch SiloClientError.status(let status, let body) where status == 400 || status == 404 {
            throw StoreRefused(
                reason: Self.detail(body).isEmpty ? "the library no longer holds the parent" : Self.detail(body)
            )
        }
        return dryRun ? .wouldMake(result) : .made(result)
    }

    /// An edit draft of a container the library holds, whose document is smddb's record and whose base
    /// is the library's sidecar as the silo has it now.
    public func draft(fromSmddb record: Container, in library: String, of silo: Silo) async throws -> ContainerDraft {
        let opened = try await open(container: record.id.value, in: library, of: silo)
        var draft = try ContainerDraft.change(opened.container, sidecar: opened.sidecar)
        draft.take(record)
        return draft
    }

    /// Whether the library holds a container, by asking for it.
    private func holds(_ id: ContainerID, in library: String, of silo: Silo) async throws -> Bool {
        do {
            _ = try await withOperator(silo) { try await $0.container(id.value, in: library) }
            return true
        } catch SiloClientError.status(404, _) {
            return false
        }
    }

    // MARK: Create

    /// A new container, with an id from smddb's client, as a draft kept on this Mac until it is made
    /// or discarded: at the top of a library, or beneath a container it holds.
    public func newContainer(
        _ type: ContainerType,
        titled title: Title,
        in library: String,
        at creating: ContainerDraft.Creating,
        of silo: Silo,
        from database: any ContainerDatabase
    ) async throws -> ContainerDraft {
        let container = Container(id: try await database.provisionalID(), type: type, title: title)
        let draft = ContainerDraft.new(container, in: library, at: creating)
        try containerDrafts.save(draft, for: silo.id)
        return draft
    }

    /// The parent's own fields with the new container named in them: as the item `creating.item`, or
    /// one slugged from the title, at `creating.position` in the sequence `creating.sequence`, or the
    /// first, which is made when the parent has none.
    public nonisolated static func naming(
        _ child: Container,
        in parent: Container,
        at creating: ContainerDraft.Creating
    ) -> Container {
        var parent = parent
        guard !parent.childContainerIDs.contains(child.id) else { return parent }
        let item =
            creating.item.flatMap(ItemID.init)
            ?? ItemID(Slug.unique(from: child.title.rawValue, avoiding: Set(parent.itemIDs.map(\.value))))!
        let entry = Entry.child(Entry.Child(id: item, container: child.id))
        if parent.sequences.isEmpty { parent.sequences = [Sequence(items: [])] }
        let index = parent.sequences.firstIndex { $0.id != nil && $0.id == creating.sequence } ?? 0
        let position = min(
            max(creating.position ?? parent.sequences[index].items.count, 0),
            parent.sequences[index].items.count
        )
        parent.sequences[index].items.insert(entry, at: position)
        return parent
    }

    /// What making a new container would come to, asked of the silo without storing anything: for one
    /// at the top of a library, the dry run of making it; for one beneath a parent, the dry run of the
    /// edit that names it in the parent, which is what is stored first.
    public func check(new draft: ContainerDraft, of silo: Silo) async throws -> ContainerCheck {
        guard let creating = draft.creating, let child = draft.value else {
            return .unreadable("the document does not read as a container")
        }
        guard let parent = creating.parent else {
            do {
                let result = try await withOperator(silo) {
                    try await $0.create(containers: [draft.text], parent: nil, in: draft.library, dryRun: true)
                }
                return .wouldWrite(Self.editResult(result))
            } catch SiloClientError.status(422, let body) {
                guard
                    let result = try? SiloClient.decoder.decode(
                        SiloClient.ContainerCreateResult.self,
                        from: Data(body.utf8)
                    )
                else { return .unreadable(Self.detail(body)) }
                return .refused(Self.editResult(result))
            } catch SiloClientError.status(400, let body) {
                return .unreadable(Self.detail(body))
            }
        }
        let opened = try await open(container: parent, in: draft.library, of: silo)
        var naming = try ContainerDraft.change(opened.container, sidecar: opened.sidecar)
        guard let held = naming.value else { return .unreadable("the parent's sidecar does not read as a container") }
        naming.set(Self.naming(child, in: held, at: creating))
        return try await check(naming, of: silo)
    }

    /// How making a new container ended: made, which ends the draft; refused by the silo's findings on
    /// the parent's edit or on the making, which keep it; or the parent named it and the making was
    /// refused, which keeps it too, the parent left naming a child the library does not hold.
    public enum CreateOutcome: Hashable, Sendable {
        case created(SiloClient.ContainerCreateResult)
        case parentRefused(SiloClient.ContainerEditResult)
        case refused(SiloClient.ContainerCreateResult)
    }

    /// Makes a new container: for one beneath a parent, first an edit of the parent that names it,
    /// based on the parent's sidecar as the silo has it now, then the making. Made, the draft ends.
    public func create(_ draft: ContainerDraft, of silo: Silo) async throws -> CreateOutcome {
        guard let creating = draft.creating, let child = draft.value else {
            throw StoreRefused(reason: "the document does not read as a container")
        }
        if let parent = creating.parent {
            let opened = try await open(container: parent, in: draft.library, of: silo)
            var naming = try ContainerDraft.change(opened.container, sidecar: opened.sidecar)
            guard let held = naming.value else {
                throw StoreRefused(reason: "the parent's sidecar does not read as a container")
            }
            let named = Self.naming(child, in: held, at: creating)
            if named != held {
                naming.set(named)
                switch try await store(naming, of: silo) {
                case .stored: break
                case .refused(let result): return .parentRefused(result)
                case .landedFirst:
                    throw StoreRefused(reason: "the parent's sidecar changed as it was edited; try again")
                }
            }
        }
        do {
            let result = try await withOperator(silo) {
                try await $0.create(
                    containers: [draft.text],
                    parent: creating.parent,
                    in: draft.library,
                    attributions: draft.attributions.map {
                        SiloClient.CreateAttribution(
                            container: child.id.value,
                            subject: $0.subject.rawValue,
                            provider: $0.provider.rawValue,
                            value: $0.value
                        )
                    }
                )
            }
            try containerDrafts.remove(draft.id, of: silo.id)
            return .created(result)
        } catch SiloClientError.status(422, let body) {
            guard
                let result = try? SiloClient.decoder.decode(
                    SiloClient.ContainerCreateResult.self,
                    from: Data(body.utf8)
                )
            else { throw StoreRefused(reason: Self.detail(body)) }
            return .refused(result)
        } catch SiloClientError.status(let status, let body) where status == 400 || status == 404 {
            throw StoreRefused(
                reason: Self.detail(body).isEmpty ? "the library no longer holds the parent" : Self.detail(body)
            )
        }
    }

    /// A making's result as an edit's, for the verdict the editor shows: its findings, and nothing written.
    nonisolated static func editResult(
        _ result: SiloClient.ContainerCreateResult
    ) -> SiloClient.ContainerEditResult {
        SiloClient.ContainerEditResult(applied: result.applied, sidecar: "", digest: "", findings: result.findings)
    }

    // MARK: Export

    /// What proposing a library's container to smddb would offer: the container as the library's
    /// sidecar says it, smddb's record of the same id if it has one, the containers it names — as
    /// children beneath it, or through a ref — that smddb does not have and the library holds, which
    /// go with it, and those neither has, which would refuse it.
    public struct ExportPlan: Hashable, Sendable {
        public var library: String
        /// The container as it will be contributed: its attributed fields smddb's, or none.
        public var container: Container
        public var record: Container?
        public var offered: [Container]
        public var unavailable: [ContainerID]
        /// The fields each contributed container's sidecar attributes to a provider, which the
        /// contribution leaves out: a provider's contributors' writing is not smddb's to hold.
        public var leftOut: [ContainerID: [Attribution]] = [:]

        /// The document's difference from smddb's record, line by line; every line added when smddb has none.
        public var difference: [LineDifference.Line] {
            LineDifference.lines(
                from: record.map { String(decoding: ContainerFile.data(for: $0), as: UTF8.self) } ?? "",
                to: String(decoding: ContainerFile.data(for: container), as: UTF8.self)
            )
        }
    }

    /// Works out the export of a library's container to smddb, reading the library's sidecars of the
    /// containers it names that smddb does not have, and theirs in turn.
    public func planExport(
        _ id: String,
        in library: String,
        of silo: Silo,
        to database: any ContainerDatabase
    ) async throws -> ExportPlan {
        let opened = try await open(container: id, in: library, of: silo)
        let sidecar = try SidecarFile.sidecar(from: opened.sidecar)
        let record = try await database.container(sidecar.container.id)
        let (container, left) = Self.contributable(sidecar, record: record)
        var leftOut: [ContainerID: [Attribution]] = left.isEmpty ? [:] : [container.id: left]
        var offered: [Container] = []
        var unavailable: [ContainerID] = []
        var seen: Set<ContainerID> = [container.id]
        var queue = container.namedContainerIDs
        while !queue.isEmpty {
            let next = queue.removeFirst()
            guard seen.insert(next).inserted, try await database.container(next) == nil else { continue }
            do {
                let bytes = try await withOperator(silo) { try await $0.sidecar(of: next.value, in: library) }
                let (named, left) = Self.contributable(try SidecarFile.sidecar(from: bytes), record: nil)
                if !left.isEmpty { leftOut[named.id] = left }
                offered.append(named)
                queue += named.namedContainerIDs
            } catch SiloClientError.status(404, _) {
                unavailable.append(next)
            }
        }
        return ExportPlan(
            library: library,
            container: container,
            record: record,
            offered: offered,
            unavailable: unavailable,
            leftOut: leftOut
        )
    }

    /// A sidecar's container as smddb may take it: each field the sidecar attributes to a provider given
    /// the value smddb's record holds, or none when there is no record; and the attributions it left out.
    public nonisolated static func contributable(
        _ sidecar: Sidecar,
        record: Container?
    ) -> (Container, [Attribution]) {
        var container = sidecar.container
        var left: [Attribution] = []
        for attribution in sidecar.attributions {
            if attribution.subject == .outline {
                container.outline = record?.outline
                left.append(attribution)
            } else if let alternative = attribution.subject.alternative,
                let index = container.alternatives.firstIndex(where: { $0.id == alternative })
            {
                container.alternatives[index].outline = record?.alternatives.first { $0.id == alternative }?.outline
                left.append(attribution)
            }
        }
        return (container, left)
    }

    /// Contributes the plan's container to smddb, with the offered containers chosen. smddb refuses it
    /// whole when it names a container neither it nor the contribution holds.
    public nonisolated func export(
        _ plan: ExportPlan,
        choosing chosen: Set<ContainerID>,
        to database: any ContainerDatabase
    ) async throws -> Contribution {
        try await database.contribute([plan.container] + plan.offered.filter { chosen.contains($0.id) })
    }
}
