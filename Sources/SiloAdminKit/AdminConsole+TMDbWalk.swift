// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloClient
import SmdKit
import SmdSidecar

// MARK: - A walk against TMDb

/// A held tree reviewed against TMDb as a walk: its stops found as each is confirmed, its specials
/// placed where they belong, and one store at the end, listed first and made in an order that has
/// everything a change refers to there before it. `TmdbWalk.md`.
extension AdminConsole {
    /// Starts a walk rooted at a held container, its first stop, read when it is opened. The series
    /// whose specials sit beside every stop is the root, or the nearest series above it.
    public func startWalk(at id: String, in library: String, of silo: Silo) async throws -> TMDbWalk {
        let opened = try await open(container: id, in: library, of: silo)
        let held = opened.container.container
        var walk = TMDbWalk(
            library: library,
            root: TMDbWalk.Stop(id: id, title: held.displayTitle, type: held.type, parent: held.parent)
        )
        walk.series =
            held.type == ContainerType.series.rawValue ? id : try await seriesContainerAbove(opened, of: silo)?.id
        return walk
    }

    /// The containers the library holds beneath a stop, as the stops confirming it adds, in the order
    /// its sequences hold them; a stop the walk has already is as the walk has it. A stop TMDb could not
    /// read is opened for them, so the walk goes on beneath it.
    public func stops(beneath id: String, in walk: TMDbWalk, of silo: Silo) async throws -> [TMDbWalk.Stop] {
        guard walk.stops[id] != nil else { return [] }
        if let tree = walk.draft(holding: id) {
            let beneath = (tree.container(id)?.childContainerIDs ?? []) + tree.alternativeChildren(of: id)
            return beneath.filter { tree.isMade($0.value) }.compactMap { child in
                walk.stops[child.value]
                    ?? tree.container(child.value).map { _ in
                        TMDbWalk.Stop(
                            newIn: tree,
                            child.value,
                            parent: id,
                            offering: walk.offered(child.value, in: tree)
                        )
                    }
            }
        }
        let sidecar: Data
        if let read = walk.stops[id]?.comparison?.opened.sidecar {
            sidecar = read
        } else {
            sidecar = try await open(container: id, in: walk.library, of: silo).sidecar
        }
        let held = try SidecarFile.sidecar(from: sidecar).container
        let (library, known) = (walk.library, walk.stops)
        let beneath: [TMDbWalk.Stop?] = try await Self.concurrently(held.childContainerIDs.map(\.value)) { child in
            if let stop = known[child] { return stop }
            // A child the sidecar names and the library does not hold is no stop.
            guard let opened = try? await self.open(container: child, in: library, of: silo) else { return nil }
            let container = opened.container.container
            return TMDbWalk.Stop(id: child, title: container.displayTitle, type: container.type, parent: id)
        }
        return beneath.compactMap { $0 }
    }

    /// A draft from TMDb of each missing season chosen at a stop that the walk has not drafted yet, filed
    /// beneath the stop's container after the seasons it holds: what confirming the stop adds as new
    /// stops.
    public func drafts(
        confirming id: String,
        in walk: TMDbWalk,
        from database: any ContainerDatabase,
        tmdb: any TMDbSource
    ) async throws -> [TMDbTree] {
        guard let stop = walk.stops[id], let series = stop.comparison?.series else {
            return []
        }
        let drafted = Set(walk.drafts.values.map(TMDbWalk.missing))
        let sequence = walk.container(id)?.sequences.first { $0.items.contains { $0.childContainer != nil } }?.id
        var trees: [TMDbTree] = []
        for case .season(let season) in walk.differences(of: id)
        where stop.chosen.contains("season:\(season.id)") && !drafted.contains("season:\(season.id)") {
            trees.append(
                try await draft(
                    ofSeason: season.number,
                    of: series,
                    at: ContainerDraft.Creating(parent: id, sequence: sequence),
                    into: walk.library,
                    from: database,
                    tmdb: tmdb
                )
            )
        }
        return trees
    }

    /// The series a library holds that specials may go into as their companion, listed or not: every one
    /// at the top of the library but the series they are of.
    public func companionSeries(
        in library: String,
        besides series: String?,
        of silo: Silo
    ) async throws -> [SiloClient.ContainerSummary] {
        try await containers(in: library, of: silo).filter {
            $0.type == ContainerType.series.rawValue && $0.id != series
        }
    }

    /// How a store of a walk ended: what it made, and, when the silo refused a step, why, and the steps
    /// it did not make, which the walk keeps.
    public struct TMDbWalkStored: Hashable, Sendable {
        public var walk: TMDbWalk
        public var stored: [TMDbWalk.Step]
        public var refusal: String?
        public var rest: [TMDbWalk.Step]
        /// The stop whose sidecar changed since it was read, which is to be read again and confirmed again.
        public var stale: String?
    }

    /// Stores the walk as its plan lists it, step by step, stopping at the first the silo refuses.
    public func store(_ walk: TMDbWalk, of silo: Silo, tmdb: any TMDbSource) async throws -> TMDbWalkStored {
        var walk = walk
        let steps = try walk.plan().steps
        var stored: [TMDbWalk.Step] = []
        for (index, step) in steps.enumerated() {
            if let refusal = try await make(step, in: walk.library, of: silo, tmdb: tmdb) {
                var stale: String?
                // An edit based on a sidecar the library has changed since: its stop is to be read again,
                // and confirmed again once the operator has looked.
                if case .edit(let draft) = step.kind, refusal == Self.changedSince(draft) {
                    stale = draft.container
                    walk.stops[draft.container]?.comparison = nil
                    walk.stops[draft.container]?.taken = nil
                }
                return TMDbWalkStored(
                    walk: walk,
                    stored: stored,
                    refusal: refusal,
                    rest: Array(steps[index...]),
                    stale: stale
                )
            }
            walk.stored.insert(step.id)
            stored.append(step)
        }
        return TMDbWalkStored(walk: walk, stored: stored, refusal: nil, rest: [])
    }

    /// Makes one step of a walk's store; the silo's refusal, in its words, or nil when it was made.
    private func make(
        _ step: TMDbWalk.Step,
        in library: String,
        of silo: Silo,
        tmdb: any TMDbSource
    ) async throws -> String? {
        do {
            switch step.kind {
            case .create(let containers, let parent, let attributions):
                _ = try await withOperator(silo) {
                    try await $0.create(
                        containers: containers.map(TMDbTree.text),
                        parent: parent,
                        in: library,
                        attributions: attributions
                    )
                }
            case .edit(let draft):
                switch try await store(draft, of: silo) {
                case .stored: break
                case .refused(let result): return result.findings.map(\.text).joined(separator: "; ")
                case .landedFirst: return Self.changedSince(draft)
                }
            case .held(let edit):
                try await apply(edit, on: silo)
            case .decline(let refs, let series):
                try await decline(refs, in: series, of: library, on: silo)
            case .artwork(let kind, let path, let record, let container):
                try await putArtwork(
                    try await tmdb.image(at: path),
                    as: kind,
                    of: container,
                    in: library,
                    on: silo,
                    attributedTo: record.ref
                )
            }
            return nil
        } catch SiloClientError.status(422, let body) {
            let result = try? SiloClient.decoder.decode(SiloClient.ContainerCreateResult.self, from: Data(body.utf8))
            return result?.findings.map(\.text).joined(separator: "; ") ?? Self.detail(body)
        } catch SiloClientError.status(let status, let body) where status == 400 || status == 404 {
            return Self.detail(body).isEmpty ? "the library no longer holds what it names" : Self.detail(body)
        } catch let refused as StoreRefused {
            return refused.reason
        } catch let refused as SettingsRefused {
            return refused.reason
        }
    }

    /// Why an edit whose sidecar changed after its stop read it is refused.
    nonisolated static func changedSince(_ draft: ContainerDraft) -> String {
        "\(draft.title) changed in the library after the walk read it, so it is read again"
    }

    /// A special put where the operator placed it, as part of the change of the container it is placed
    /// in: an entry or an extra of it, a container of its own beneath it, a ref from it to a duplicate's
    /// home or a breakout's entry, or, in the series, declined. What it makes of other containers is
    /// gathered as their edits; a new breakout gains the entry itself.
    nonisolated static func place(
        _ special: Special,
        _ placement: SpecialPlacement,
        library: String,
        in container: inout Container,
        declined: inout [ExternalRef],
        made: inout [String: Container],
        edits: inout [TMDbTree.Making.HeldEdit],
        children: inout [Container]
    ) {
        func entryID(in title: String) -> String { "\(Slug.make(from: title))-\(special.id)" }
        switch placement {
        case .entry(_, let sequence, let position):
            TMDbTree.insert(
                TMDbTree.leaf(special, type: .episode, in: container),
                into: &container,
                sequence: sequence,
                at: position
            )
        case .extra(_, let type):
            container.extras.append(
                TMDbTree.leaf(special, type: EntryType(rawValue: type) ?? .featurette, in: container)
            )
        case .child(_, let id, let type):
            guard let childID = ContainerID(id), let title = Title(special.episode.title) ?? Title("Special") else {
                return
            }
            var child = Container(id: childID, type: ContainerType(rawValue: type) ?? .serial, title: title)
            child.sequences = [Sequence(id: "parts", items: [TMDbTree.leaf(special, type: .episode, in: child)])]
            children.append(child)
        case .duplicate(let home, let item, let homeLibrary, _, let asExtra):
            edits.append(.init(library: homeLibrary, container: home, item: item, ref: special.episode.ref))
            guard let homeID = ContainerID(home), let itemID = ItemID(item) else { return }
            TMDbTree.refer(to: EntryRef(container: homeID, item: itemID), from: &container, asExtra: asExtra)
        case .breakout(let breakout, _, let asExtra):
            let item = ItemID(entryID(in: special.episode.title))!
            if var companion = made[breakout] {
                TMDbTree.insert(
                    .leaf(Entry.Leaf(id: item, type: .episode, externalRefs: special.refs)),
                    into: &companion,
                    sequence: nil,
                    at: nil
                )
                made[breakout] = companion
            } else {
                edits.append(.init(library: library, container: breakout, entry: special, entryID: item.value))
            }
            guard let breakoutID = ContainerID(breakout) else { return }
            TMDbTree.refer(to: EntryRef(container: breakoutID, item: item), from: &container, asExtra: asExtra)
        case .edition(_, let title):
            TMDbTree.edition(special, titled: title, in: &container)
        case .version(_, let item, let title):
            TMDbTree.version(special, of: item, titled: title, in: &container)
        case .alternative:
            // Made with the alternative it is in, once the stop's specials are placed.
            break
        case .declined:
            if !declined.contains(special.episode.ref) { declined.append(special.episode.ref) }
        }
    }
}

// MARK: - The store's plan

extension TMDbWalk {
    /// Everything storing the walk makes, in the order it makes it, each step said in words before any
    /// is made: the containers the walk makes at the top of the library; the edits of containers outside
    /// the walk that specials placed make, so what the walk refers to is there; each confirmed stop's
    /// edit, in the tree's order, each followed by the creation of the containers it names beneath it;
    /// and the artwork, each put with its attribution.
    public struct Plan: Hashable, Sendable {
        public var steps: [Step]
        /// The containers storing makes, and those of the library it edits, by id, whether or not an
        /// earlier store made the step already.
        public var made: Set<String> = []
        public var edited: Set<String> = []
    }

    /// One thing storing the walk makes, said in words.
    public struct Step: Hashable, Sendable, Identifiable {
        public var id: String
        public var kind: StepKind
        public var described: String
    }

    public enum StepKind: Hashable, Sendable {
        /// Containers made through the create route, beneath a parent that names the first, or at the top
        /// of the library, with the attributions of their fields.
        case create([Container], parent: String?, attributions: [SiloClient.CreateAttribution] = [])
        /// A stop's edit, based on the sidecar its reading found.
        case edit(ContainerDraft)
        /// An edit of a container outside the walk, onto its sidecar as it is then.
        case held(TMDbTree.Making.HeldEdit)
        /// References the series declines, when the series is no stop of the walk.
        case decline([ExternalRef], in: String)
        case artwork(kind: String, path: String, record: TMDb.Record, of: String)
    }

    /// A confirmed stop's pending change as the plan gathers it.
    private struct Change {
        var stop: Stop
        var draft: ContainerDraft
        var container: Container
        var children: [Container] = []
        /// The groups of its missing episodes taken, by each episode's TMDb id.
        var grouped: [String: EpisodeGroup] = [:]
        /// The containers held beneath it its missing episodes were handed to, by each episode's TMDb id.
        var intoHeld: [String: String] = [:]
        /// The operator's own titles for its missing episodes, by TMDb id.
        var titles: [Int: String] = [:]
        /// The new containers the walk makes beneath it, each with what is beneath it.
        var made: [(creating: ContainerDraft.Creating, making: TMDbTree.Making)] = []
    }

    /// What the plan gathers across the stops besides their own edits.
    private struct Gathering {
        /// The entries placed in each confirmed companion series of the walk from elsewhere, gathered in
        /// its first sequence, by id.
        var made: [String: Container]
        /// The edits of other containers that placed specials make.
        var edits: [TMDbTree.Making.HeldEdit] = []
        var artwork: [Step] = []
    }

    /// The confirmed companion series, each holding nothing yet, to gather the entries placed in them.
    private var gathering: Gathering {
        var made: [String: Container] = [:]
        for id in companionStops where stops[id]?.taken != nil {
            guard var series = companion(id) else { continue }
            series.sequences = [Sequence(id: series.sequences.first?.id, items: [])]
            made[id] = series
        }
        return Gathering(made: made)
    }

    /// The walk's store, from what each confirmed stop took and where the specials were placed, less
    /// what an earlier store made. A stop never confirmed contributes nothing.
    public func plan() throws -> Plan {
        var gathering = gathering
        var companions: [(creating: ContainerDraft.Creating, making: TMDbTree.Making)] = []
        for id in companionStops {
            if let made = making(of: id, gathering: &gathering) { companions.append(made) }
        }
        var changes: [Change] = []
        for id in order {
            if let change = try change(of: id, gathering: &gathering) { changes.append(change) }
        }
        // In the walk's order, so each is named in its parent among the siblings listed around it.
        for top in order.filter({ drafts[$0] != nil }) + drafts.keys.sorted().filter({ !order.contains($0) }) {
            guard let parent = drafts[top]?.creating.parent,
                let index = changes.firstIndex(where: { $0.stop.id == parent }),
                let made = making(of: top, gathering: &gathering)
            else { continue }
            changes[index].made.append(made)
        }
        // An edit of a container that is a confirmed stop is made in that stop's edit, which is based on
        // the sidecar its reading found; any other is made onto the sidecar as it is when it is stored.
        var outside: [TMDbTree.Making.HeldEdit] = []
        for edit in gathering.edits {
            if edit.library == library, let index = changes.firstIndex(where: { $0.stop.id == edit.container }) {
                AdminConsole.applying(edit, to: &changes[index].container)
            } else {
                outside.append(edit)
            }
        }
        // Each confirmed companion first, holding the entries placed in it from elsewhere after its own.
        var steps = companions.compactMap { _, making -> Step? in
            guard var top = making.documents.first else { return nil }
            for entry in gathering.made[top.id.value]?.sequences.first?.items ?? [] {
                TMDbTree.insert(entry, into: &top, sequence: nil, at: nil)
            }
            let beneath = making.documents.count - 1
            return Step(
                id: "create:\(top.id)",
                kind: .create([top] + making.documents.dropFirst(), parent: nil, attributions: making.attributions),
                described:
                    "make \(top.displayTitle), a series of its own,\(beneath > 0 ? " and the \(beneath) beneath it," : "") at the top of the library"
            )
        }
        steps += outside.map { edit in
            Step(id: "held:\(edit.key)", kind: .held(edit), described: edit.described)
        }
        for change in changes { steps += Self.steps(for: change) }
        if let decline { steps.append(decline) }
        steps += gathering.artwork
        var plan = Plan(steps: steps.filter { !stored.contains($0.id) })
        for step in steps {
            switch step.kind {
            case .create(let containers, _, _): plan.made.formUnion(containers.map(\.id.value))
            case .edit(let draft): plan.edited.insert(draft.container)
            case .held(let edit) where edit.library == library: plan.edited.insert(edit.container)
            case .held: break
            case .decline(_, let series): plan.edited.insert(series)
            case .artwork(_, _, _, let container): plan.edited.insert(container)
            }
        }
        return plan
    }

    /// What a confirmed new stop's draft makes: each container of it as its own stop left it, with the
    /// specials placed in the confirmed ones; what that makes of other containers is gathered, a walk's
    /// new companion gaining its entries itself.
    private func making(
        of top: String,
        gathering: inout Gathering
    ) -> (creating: ContainerDraft.Creating, making: TMDbTree.Making)? {
        guard var tree = drafts[top], stops[top]?.taken != nil else { return nil }
        for container in tree.containers {
            guard let taken = stops[container.id.value]?.taken else {
                // Not confirmed, it is not made, nor anything beneath it.
                if let parent = tree.containers.first(where: { $0.childContainerIDs.contains(container.id) }),
                    let item = parent.sequences.flatMap(\.items).first(where: { $0.childContainer == container.id })?.id
                {
                    tree.include(item, in: parent.id.value, false)
                } else if tree.alternativeParent(of: container.id.value) != nil {
                    // Played in an alternative alone, it is left out of the tree.
                    tree.drop(container.id.value)
                }
                continue
            }
            var kept = container
            for difference in offered(container.id.value, in: tree) where !taken.contains(difference.id) {
                switch difference {
                case .year: kept.year = nil
                case .outline: kept.outline = nil
                case .reference(_, let ref): kept.externalRefs.removeAll { $0 == ref }
                default: break
                }
            }
            tree.set(kept)
        }
        let confirmed = Set(tree.containers.map(\.id.value).filter { stops[$0]?.taken != nil })
        let placed = (specials + declined).filter { special in
            !waitsOnCompanion(placements[special.id])
                && placements[special.id].flatMap(home).map(confirmed.contains) ?? false
        }
        tree.specials = placed
        tree.placements = placements.filter { id, _ in placed.contains { $0.id == id } }
        tree.draftedAlternatives = draftedAlternatives.filter { confirmed.contains($0.key) }
        for special in placed {
            guard case .breakout(let id, _, _)? = placements[special.id], var companion = gathering.made[id] else {
                continue
            }
            let item = ItemID("\(Slug.make(from: special.episode.title))-\(special.id)")!
            TMDbTree.insert(
                .leaf(Entry.Leaf(id: item, type: .episode, externalRefs: special.refs)),
                into: &companion,
                sequence: nil,
                at: nil
            )
            gathering.made[id] = companion
        }
        let making = tree.making
        gathering.edits += making.heldEdits.filter { edit in edit.entry == nil || gathering.made[edit.container] == nil
        }
        return (tree.creating, making)
    }

    /// A confirmed stop's change: its ticked differences and the specials placed in it, onto the sidecar
    /// its reading found.
    private func change(of id: String, gathering: inout Gathering) throws -> Change? {
        guard let stop = stops[id], let taken = stop.taken, var comparison = stop.comparison else { return nil }
        // The missing episodes its parent handed to it are its own, as though its reading offered them.
        comparison.differences += handed(to: id)
        let sidecar = try SidecarFile.sidecar(from: comparison.opened.sidecar)
        var draft = try ContainerDraft.change(comparison.opened.container, sidecar: comparison.opened.sidecar)
        guard let held = draft.value else {
            throw AdminConsole.StoreRefused(reason: "\(stop.title)'s sidecar does not read as a container")
        }
        var change = Change(stop: stop, draft: draft, container: held)
        for (sequence, name) in renamedSequences[id] ?? [:] { change.container.renameSequence(sequence, to: name) }
        change.titles = titles
        let groups = stop.groups.filter { taken.contains($0.tick) }
        for group in groups {
            for episode in group.episodes { change.grouped[String(episode)] = group }
        }
        for (child, episodes) in stop.intoHeld {
            for episode in episodes { change.intoHeld[String(episode)] = child }
        }
        for difference in comparison.differences {
            // One handed to a container held beneath is that container's to take.
            if case .episode(let episode, _) = difference, change.intoHeld[String(episode.id)] != nil { continue }
            // A group taken is made beneath the stop, named where its first episode would have gone.
            if case .episode(let episode, let after) = difference, let group = change.grouped[String(episode.id)] {
                // Made from its stop's draft, with what was placed and shaped there, once that stop is
                // confirmed, as every new container is; named here where its first episode would have gone.
                if Self.first(of: group, in: comparison) == episode.id, drafts[group.id] != nil,
                    stops[group.id]?.taken != nil
                {
                    Self.name(group, after: after, in: &change)
                }
                continue
            }
            guard taken.contains(difference.id) else { continue }
            Self.take(difference, into: &change, comparison: comparison, gathering: &gathering)
        }
        var declined = sidecar.declined
        for special in placed(in: id) {
            guard let placement = placements[special.id], !waitsOnCompanion(placement) else { continue }
            AdminConsole.place(
                special,
                placement,
                library: library,
                in: &change.container,
                declined: &declined,
                made: &gathering.made,
                edits: &gathering.edits,
                children: &change.children
            )
        }
        if let order = arrangedEntries[id], !change.container.sequences.isEmpty {
            change.container.sequences[0].items = AdminConsole.arranged(
                change.container.sequences[0].items,
                by: order,
                held: Set(held.itemIDs)
            )
        }
        DraftAlternative.make(
            alternatives(draftedAt: id),
            specials: placed(in: id),
            containers: containers(madeBeneath: id, taking: taken),
            in: &change.container
        )
        // A declined special placed after all, wherever it went, is no longer declined.
        if id == series {
            for special in self.declined where placements[special.id].map({ $0 != .declined }) ?? false {
                declined.removeAll { $0 == special.episode.ref }
            }
        }
        if taken.contains("outline"),
            case .outline(_, let record)? = comparison.differences.first(where: {
                $0.id == "outline"
            })
        {
            draft.attributions.removeAll { $0.subject == .outline }
            draft.attributions.append(Attribution(subject: .outline, provider: .tmdb, value: record))
        }
        if declined != sidecar.declined { draft.declined = declined }
        change.draft = draft
        return change
    }

    /// One ticked difference taken into a stop's change, or gathered as artwork to put or a season to
    /// draft.
    private static func take(
        _ difference: AdminConsole.TMDbDifference,
        into change: inout Change,
        comparison: AdminConsole.TMDbComparison,
        gathering: inout Gathering
    ) {
        let id = change.stop.id
        switch difference {
        case .title(let title): if let title = Title(title) { change.container.title = title }
        case .year(let year): change.container.year = year
        case .outline(let text, _): change.container.outline = text
        case .reference(nil, let ref): change.container.externalRefs.append(ref)
        case .reference(let item?, let ref): AdminConsole.add(ref, toItem: item, in: &change.container)
        case .episode(let episode, let after):
            AdminConsole.insert(
                AdminConsole.leaf(episode, in: change.container, title: change.titles[episode.id]),
                after: Self.anchor(after, in: change),
                into: &change.container
            )
        case .order(let sequence, let items): AdminConsole.reorder(sequence, to: items, in: &change.container)
        // A missing season chosen is a new stop of the walk, made with what its own stop keeps.
        case .season, .heldSeason, .unmatchedSeason: break
        case .artwork(let kind, let path, let record):
            gathering.artwork.append(
                Step(
                    id: "artwork:\(id):\(kind)",
                    kind: .artwork(kind: kind, path: path, record: record, of: id),
                    described: "put TMDb's \(kind) on \(change.stop.title), credited to TMDb"
                )
            )
        case .special: break
        }
    }

    /// The first of a group's episodes the stop's reading still offers.
    private static func first(of group: EpisodeGroup, in comparison: AdminConsole.TMDbComparison) -> Int? {
        let offered = comparison.differences.compactMap { difference -> Int? in
            if case .episode(let episode, _) = difference { episode.id } else { nil }
        }
        return group.episodes.first(where: offered.contains)
    }

    /// A group's container named in the stop where the first of its episodes would have gone.
    private static func name(_ group: EpisodeGroup, after: ExternalRef?, in change: inout Change) {
        guard let id = ContainerID(group.id) else { return }
        let item = ItemID(
            Slug.unique(from: group.title.rawValue, avoiding: Set(change.container.itemIDs.map(\.value)))
        )!
        AdminConsole.insert(
            .child(Entry.Child(id: item, container: id)),
            after: anchor(after, in: change),
            into: &change.container
        )
    }

    /// What an entry TMDb puts after an episode goes after in the stop's container: the episode, the
    /// group taken in its place, or the container held beneath it was handed to.
    private static func anchor(_ after: ExternalRef?, in change: Change) -> AdminConsole.Anchor? {
        guard let after else { return nil }
        if let group = change.grouped[after.value], let id = ContainerID(group.id) { return .child(id) }
        if let child = change.intoHeld[after.value].flatMap(ContainerID.init) { return .child(child) }
        return .ref(after)
    }

    /// A stop's edit, naming the containers of its own placed specials make beneath it, then their making.
    private static func steps(for change: Change) -> [Step] {
        var draft = change.draft
        var named = change.container
        for child in change.children {
            named = AdminConsole.naming(child, in: named, at: ContainerDraft.Creating(parent: change.stop.id))
        }
        for (creating, making) in change.made {
            guard let top = making.documents.first else { continue }
            named = AdminConsole.naming(
                top,
                in: named,
                at: placing(top.id.value, creating, among: change.stop.children, in: named)
            )
        }
        draft.set(named)
        var steps: [Step] = []
        if draft.isChanged {
            steps.append(
                Step(
                    id: "edit:\(change.stop.id)",
                    kind: .edit(draft),
                    described: described(draft, of: change.stop)
                )
            )
        }
        return steps
            + change.children.map { child in
                Step(
                    id: "create:\(child.id)",
                    kind: .create([child], parent: change.stop.id),
                    described: "make \(child.displayTitle) beneath \(change.stop.title)"
                )
            }
            + change.made.compactMap { _, making in
                guard let top = making.documents.first else { return nil }
                let beneath = making.documents.count - 1
                return Step(
                    id: "create:\(top.id)",
                    kind: .create(making.documents, parent: change.stop.id, attributions: making.attributions),
                    described:
                        "make \(top.displayTitle)\(beneath > 0 ? " and the \(beneath) beneath it" : "") beneath \(change.stop.title)"
                )
            }
    }

    /// Where a new container is named in its parent: where its creating says, or, said nowhere, before the
    /// first sibling listed after it that the parent names, and last when none is.
    private static func placing(
        _ top: String,
        _ creating: ContainerDraft.Creating,
        among children: [String],
        in parent: Container
    ) -> ContainerDraft.Creating {
        guard creating.position == nil, let index = children.firstIndex(of: top) else { return creating }
        let sequence = parent.sequences.firstIndex { $0.id != nil && $0.id == creating.sequence } ?? 0
        guard parent.sequences.indices.contains(sequence) else { return creating }
        let items = parent.sequences[sequence].items
        var placed = creating
        placed.position =
            children[(index + 1)...].lazy.compactMap { sibling in
                items.firstIndex { $0.childContainer?.value == sibling }
            }
            .first
        return placed
    }

    /// The specials declined in a series that is no confirmed stop of the walk, as an edit of its own.
    private var decline: Step? {
        guard let series, stops[series]?.taken == nil else { return nil }
        let refs = specials.filter { placements[$0.id] == .declined }.map(\.episode.ref)
        guard !refs.isEmpty else { return nil }
        return Step(
            id: "decline:\(series)",
            kind: .decline(refs, in: series),
            described: "decline \(refs.count) of TMDb's specials in the series"
        )
    }

    /// A stop's edit in words: what it changes of the container, read from the draft against its base.
    private static func described(_ draft: ContainerDraft, of stop: Stop) -> String {
        guard let before = try? ContainerFile.container(from: Data(draft.baseText.utf8)), let after = draft.value
        else { return "edit \(stop.title)" }
        var parts: [String] = []
        if before.title != after.title { parts.append("its title") }
        if before.year != after.year { parts.append("its year") }
        if before.outline != after.outline { parts.append("its outline") }
        let refs = Set(after.externalRefs).subtracting(before.externalRefs).count
        if refs > 0 { parts.append(refs == 1 ? "1 reference" : "\(refs) references") }
        // A reference to an item of the container itself, as an alternative plays one, is no entry more.
        func entries(_ container: Container) -> [Entry] {
            (container.sequences.flatMap(\.items) + container.extras).filter { entry in
                entry.reference.map { $0.container != nil && $0.container != container.id } ?? true
            }
        }
        let added = entries(after).count - entries(before).count
        if added > 0 { parts.append(added == 1 ? "1 entry" : "\(added) entries") }
        let itemRefs =
            entries(after).map(\.externalRefs.count).reduce(0, +)
            - entries(before).map(\.externalRefs.count).reduce(0, +)
        if itemRefs > 0, added == 0 {
            parts.append(itemRefs == 1 ? "1 item's reference" : "\(itemRefs) items' references")
        }
        if added == 0,
            before.sequences.map({ $0.items.compactMap(\.id) }) != after.sequences.map({ $0.items.compactMap(\.id) })
        {
            parts.append("its order")
        }
        let alternatives = after.alternatives.count - before.alternatives.count
        if alternatives > 0 { parts.append(alternatives == 1 ? "1 alternative" : "\(alternatives) alternatives") }
        if before.sequences.map(\.id) != after.sequences.prefix(before.sequences.count).map(\.id) {
            parts.append("a sequence's name")
        }
        if draft.declined != nil { parts.append("what it declines") }
        return parts.isEmpty ? "edit \(stop.title)" : "edit \(stop.title): \(parts.joined(separator: ", "))"
    }
}

extension TMDbTree.Making.HeldEdit {
    /// What names the edit among a walk's steps.
    var key: String {
        "\(library)/\(container)/\(item ?? entryID ?? "")/\(ref.map { "\($0.provider):\($0.value)" } ?? "")"
    }

    public var described: String {
        if ref != nil { return "add TMDb's id to \(item ?? "") of \(container) in \(library)" }
        if refer != nil { return "refer to a special from \(container) in \(library)" }
        if entryType != nil { return "add an extra to \(container) in \(library)" }
        return "add an entry to \(container) in \(library)"
    }
}

// MARK: - What a stop is stored as

extension TMDbWalk {
    /// One way a stop's container is played, as storing the walk would leave it.
    public struct StopAlternative: Hashable, Sendable, Identifiable {
        public let id: String
        public let title: String
        /// What it plays, in order, each by its title.
        public let plays: [String]
        /// Made by a special placed at the stop, rather than held or drafted there already.
        public let isPlaced: Bool

        public init(id: String, title: String, plays: [String], isPlaced: Bool) {
            self.id = id
            self.title = title
            self.plays = plays
            self.isPlaced = isPlaced
        }
    }

    /// A stop's alternatives as storing would leave its container, were the stop confirmed with what is
    /// chosen and placed there now: those it holds or its draft has, then those its placed specials make.
    public func alternatives(at id: String) -> [StopAlternative] {
        guard let (before, after) = stored(id) else { return [] }
        return after.alternatives.compactMap { alternative in
            guard let sequence = after.sequences.first(where: { $0.id == alternative.sequence }) else { return nil }
            return StopAlternative(
                id: alternative.id,
                title: alternative.title ?? alternative.id,
                plays: sequence.items.map { title(of: $0, in: after, at: id) },
                isPlaced: !before.alternatives.contains { $0.id == alternative.id }
            )
        }
    }

    /// The title of one of a stop's items, by its id.
    public func title(ofItem item: String, at id: String) -> String {
        guard let container = container(id),
            let entry = container.sequences.flatMap(\.items).first(where: { $0.id?.value == item })
        else { return item }
        return title(of: entry, in: container, at: id)
    }

    /// An entry by its title: its own, TMDb's for the episode or special it carries, the operator's for a
    /// missing episode, the stop's beneath it for a child, or the title of the item it refers to.
    func title(of entry: Entry, in container: Container, at id: String) -> String {
        if let title = entry.title { return title }
        if let ref = entry.externalRefs.first(where: { $0.provider == .tmdb }) {
            if let episode = Int(ref.value), let title = titles[episode] { return title }
            let episodes = stops[id]?.comparison?.episodeTitles ?? draft(holding: id)?.episodeTitles ?? [:]
            if let title = episodes[ref.value] { return title }
            if let special = (specials + declined).first(where: { $0.episode.ref == ref }) {
                return special.episode.title
            }
        }
        if let child = entry.childContainer { return stops[child.value]?.title ?? child.value }
        if let ref = entry.reference, ref.container == nil || ref.container == container.id,
            let referred = container.sequences.flatMap(\.items).first(where: { $0.id == ref.item }),
            referred.reference == nil
        {
            return title(of: referred, in: container, at: id)
        }
        return entry.id?.value ?? entry.reference.map { "\($0.container?.value ?? "")#\($0.item)" } ?? "an item"
    }

    /// A stop's container before the walk, and as storing would make it, were the stop, and for a new
    /// stop every container of its draft, confirmed with what is chosen now, or with every child its
    /// children list taken, each new one confirmed: made by the store's own plan, so it is what storing
    /// creates.
    /// Every child a held stop's children list taken, each drafted beneath it confirmed.
    private mutating func takeEveryChild(of id: String) {
        let drafted = drafts.values.filter { $0.creating.parent == id }
        let missing = differences(of: id).filter { difference in
            switch difference {
            case .episode, .season: true
            default: false
            }
        }
        let children = missing.map(\.id) + (stops[id]?.groups ?? []).map(\.tick) + drafted.map(Self.missing)
        stops[id]?.taken?.formUnion(children)
        for container in drafted.flatMap(\.containers) {
            guard let stop = stops[container.id.value] else { continue }
            stops[container.id.value]?.taken = stop.taken ?? stop.chosen
        }
    }

    func stored(_ id: String, takingEveryChild: Bool = false) -> (before: Container, after: Container)? {
        var walk = self
        var gathering = gathering
        if let (top, tree) = drafts.first(where: { $0.value.documents[id] != nil }) {
            for container in tree.containers.map(\.id.value) {
                walk.stops[container]?.taken = stops[container]?.taken ?? stops[container]?.chosen
            }
            guard let before = tree.container(id),
                let after = walk.making(of: top, gathering: &gathering)?.making.documents.first(where: {
                    $0.id.value == id
                })
            else { return nil }
            return (before, after)
        }
        walk.stops[id]?.taken = stops[id]?.taken ?? stops[id]?.chosen
        if takingEveryChild { walk.takeEveryChild(of: id) }
        guard let before = container(id),
            let change = try? walk.change(of: id, gathering: &gathering)
        else { return nil }
        return (before, change.container)
    }
}
