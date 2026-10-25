// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloClient
import SmdKit
import SmdSidecar
import Synchronization

/// A special, from a series' season 0 at TMDb: unassigned until the operator places it or declines it.
public struct Special: Hashable, Sendable, Codable, Identifiable {
    public var episode: TMDb.Episode
    /// Its references: TMDb's id for it, and the ids other providers give it once TMDb has been asked.
    public var refs: [ExternalRef]

    public init(episode: TMDb.Episode, refs: [ExternalRef]? = nil) {
        self.episode = episode
        self.refs = refs ?? [episode.ref]
    }

    public var id: Int { episode.id }
}

/// Where the operator puts a special. Each names containers by id: one in the tree, or, for a
/// duplicate's home and a breakout made before, one a library holds.
public enum SpecialPlacement: Hashable, Sendable, Codable {
    /// An entry in one of a container's sequences, the first when none is named, at a position, or last.
    case entry(in: String, sequence: String? = nil, position: Int? = nil)
    /// An extra of a container, of a type SmdKit names.
    case extra(of: String, type: String)
    /// A container of its own beneath one, holding the special as its one entry.
    case child(of: String, id: String, type: String)
    /// The same thing as another record, whose home is an item a library holds: the home's entry gains
    /// the special's id, and a container of the tree refers to it, from its extras or its first sequence.
    case duplicate(home: String, item: String, library: String, from: String, asExtra: Bool)
    /// An entry in a series of the operator's own, new in this tree's library or held already, referred
    /// to from a container of the tree.
    case breakout(String, from: String, asExtra: Bool)
    /// Another way to play a container, as an omnibus edition is: a new sequence holding the special as
    /// its only entry, named by a new alternative with the title given.
    case edition(of: String, title: String)
    /// Another way to play one of a container's items, as an episode with new effects is: a new sequence
    /// holding the special in that item's place and referring to each of the sequence's other items,
    /// named by a new alternative with the title given.
    case version(of: String, item: String, title: String)
    /// Not held: the series' sidecar declines it.
    case declined

    /// The container a placement puts the special in, or refers to it from; none for a decline.
    public var container: String? {
        switch self {
        case .entry(let id, _, _), .extra(let id, _), .child(let id, _, _), .edition(let id, _), .version(let id, _, _):
            id
        case .duplicate(_, _, _, let from, _), .breakout(_, let from, _): from
        case .declined: nil
        }
    }
}

/// A draft from TMDb: the containers a TMDb record reads as, shaped by the operator before any is made,
/// kept on this Mac as a new container's draft is. Its containers are documents, as a draft's are; the
/// outline of each is attributed to TMDb; and a series' specials wait in it, unassigned, until the
/// operator places them. `Tmdb.md`, *A draft from TMDb* and *Specials*.
public struct TMDbTree: Hashable, Sendable, Codable, Identifiable {
    public let id: UUID
    public var library: String
    public var record: TMDb.Record
    /// The top's display title when the draft was made, to list it by.
    public var title: String
    /// Where the top is filed: beneath a container the library holds, or at its top.
    public var creating: ContainerDraft.Creating
    public var top: String
    /// Each container's document, by id.
    public var documents: [String: String]
    /// The attributions of each container's own fields, by id.
    public var attributions: [String: [Attribution]]
    /// TMDb's title for each episode the tree holds or the pool lists, by TMDb id: shown as the tree is
    /// reviewed, and stored nowhere.
    public var episodeTitles: [String: String]
    /// When each of the tree's episodes aired, by TMDb id, for suggesting where a special did.
    public var airDates: [String: String]
    /// The series' episode groups, for suggesting where one places a special.
    public var episodeGroups: [String]
    /// How long each of the tree's episodes runs, in minutes, by TMDb id, for suggesting an omnibus; nil
    /// for a draft kept before runtimes were.
    public var runtimes: [String: Int]?
    /// The series' specials, in TMDb's season 0 order.
    public var specials: [Special]
    /// Where each special goes, by its TMDb id; one with none is unassigned.
    public var placements: [Int: SpecialPlacement]
    /// The series of the operator's own that placements made, by id, as documents: each made at the
    /// top of the library before the tree, so the refs to it resolve when the tree arrives.
    public var breakouts: [String: String]
    public var edited: Date
    /// The entries the operator unticked, to be left out when the tree is made, by the id of the
    /// container holding them; absent from a draft kept before entries could be.
    var leftOutEntries: [String: [String]]?

    public init(
        library: String,
        record: TMDb.Record,
        creating: ContainerDraft.Creating,
        containers: [Container],
        top: ContainerID,
        attributions: [ContainerID: [Attribution]] = [:],
        episodeTitles: [String: String] = [:],
        airDates: [String: String] = [:],
        episodeGroups: [String] = [],
        runtimes: [String: Int] = [:],
        specials: [Special] = []
    ) {
        id = UUID()
        self.library = library
        self.record = record
        self.creating = creating
        self.top = top.value
        documents = Dictionary(
            containers.map { ($0.id.value, Self.text($0)) },
            uniquingKeysWith: { first, _ in first }
        )
        self.attributions = Dictionary(
            attributions.map { ($0.key.value, $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
        self.episodeTitles = episodeTitles
        self.airDates = airDates
        self.episodeGroups = episodeGroups
        self.runtimes = runtimes
        self.specials = specials
        placements = [:]
        breakouts = [:]
        title = containers.first { $0.id == top }?.displayTitle ?? ""
        edited = .now
    }

    static func text(_ container: Container) -> String {
        String(decoding: ContainerFile.data(for: container), as: UTF8.self)
    }

    /// The container a document says, or nil when it does not read as one.
    public func container(_ id: String) -> Container? {
        (documents[id] ?? breakouts[id]).flatMap { try? ContainerFile.container(from: Data($0.utf8)) }
    }

    /// The tree's containers from the top down, each before its children.
    public var containers: [Container] {
        var ordered: [Container] = []
        var queue = [top]
        var seen: Set<String> = []
        while !queue.isEmpty {
            let next = queue.removeFirst()
            guard seen.insert(next).inserted, documents[next] != nil, let container = container(next) else { continue }
            ordered.append(container)
            queue += container.childContainerIDs.map(\.value)
        }
        return ordered
    }

    /// A container of the tree made the value the form hands back. Its outline's attribution goes when
    /// the outline does, and stays through any rewording.
    public mutating func set(_ container: Container) {
        guard documents[container.id.value] != nil else {
            if breakouts[container.id.value] != nil { breakouts[container.id.value] = Self.text(container) }
            return
        }
        documents[container.id.value] = Self.text(container)
        attributions[container.id.value] = ContainerDraft.pruned(
            attributions[container.id.value] ?? [],
            for: container
        )
        if container.id.value == top { title = container.displayTitle }
        edited = .now
    }

    /// Removes an attribution alone: the operator saying the text is their own.
    public mutating func removeAttribution(of subject: Attribution.Subject, from container: String) {
        attributions[container]?.removeAll { $0.subject == subject }
        edited = .now
    }

    /// Takes a container and everything beneath it out of the tree, and out of its parent's sequences.
    public mutating func drop(_ id: String) {
        guard id != top, let dropped = container(id) else { return }
        for child in dropped.childContainerIDs { drop(child.value) }
        documents[id] = nil
        attributions[id] = nil
        for var parent in containers where parent.childContainerIDs.map(\.value).contains(id) {
            for index in parent.sequences.indices {
                parent.sequences[index].items.removeAll { $0.childContainer?.value == id }
            }
            parent.extras.removeAll { $0.childContainer?.value == id }
            documents[parent.id.value] = Self.text(parent)
        }
        edited = .now
    }

    /// Gathers entries of one container into a new child container of it, at the first one's place:
    /// a season's episodes regrouped into a serial. The new container's id is the one smddb's client
    /// issued; its entries keep their ids and references.
    public mutating func regroup(
        _ items: [ItemID],
        in parentID: String,
        into id: ContainerID,
        type: ContainerType,
        typeLabel: String? = nil,
        title: Title
    ) {
        guard var parent = container(parentID), !items.isEmpty else { return }
        let chosen = Set(items)
        // Grouped, an entry is made with its group, and left out only with it.
        let grouped = Set(items.map(\.value))
        leftOutEntries?[parentID]?.removeAll(where: grouped.contains)
        var gathered: [Entry] = []
        var placedAt: (sequence: Int, item: Int)?
        for sequence in parent.sequences.indices {
            var kept: [Entry] = []
            for entry in parent.sequences[sequence].items {
                if let item = entry.id, chosen.contains(item) {
                    if placedAt == nil { placedAt = (sequence, kept.count) }
                    gathered.append(entry)
                } else {
                    kept.append(entry)
                }
            }
            parent.sequences[sequence].items = kept
        }
        guard let placedAt else { return }
        var child = Container(id: id, type: type, typeLabel: typeLabel, title: title)
        child.sequences = [Sequence(id: "parts", items: gathered)]
        let item = ItemID(Slug.unique(from: title.rawValue, avoiding: Set(parent.itemIDs.map(\.value))))!
        parent.sequences[placedAt.sequence].items.insert(
            .child(Entry.Child(id: item, container: id)),
            at: placedAt.item
        )
        documents[parentID] = Self.text(parent)
        documents[id.value] = Self.text(child)
        edited = .now
    }

    /// Puts a special where the operator says, or, with nil, makes it unassigned again. A new breakout
    /// it names is kept with the tree until it is made.
    public mutating func place(_ special: Int, _ placement: SpecialPlacement?, breakout: Container? = nil) {
        placements[special] = placement
        if let breakout { breakouts[breakout.id.value] = Self.text(breakout) }
        edited = .now
    }

    /// The specials nothing has placed yet.
    public var unassigned: [Special] { specials.filter { placements[$0.id] == nil } }

    // MARK: What the tree makes

    /// What creating the tree comes to: the tree's documents with the placed specials in them, their
    /// attributions, the new breakouts made first, the edits of containers libraries hold that the
    /// placements make, and the references the top declines.
    public struct Making: Hashable, Sendable {
        /// An edit of a container a library holds: a special's id added to an item, or an entry added.
        public struct HeldEdit: Hashable, Sendable {
            public var library: String
            public var container: String
            /// The id to add to an item's references, for a duplicate's home.
            public var item: String?
            public var ref: ExternalRef?
            /// The entry to add, for a breakout made before, under the id the tree's ref names.
            public var entry: Special?
            public var entryID: String?
            /// The type the entry is, an episode unless an extra's type is named.
            public var entryType: EntryType?
            /// A ref to add, for a container that refers to a duplicate's home or a breakout, from its
            /// extras or its first sequence.
            public var refer: EntryRef?
            public var asExtra = false
        }

        public var documents: [Container]
        public var attributions: [SiloClient.CreateAttribution]
        public var breakouts: [Container]
        public var heldEdits: [HeldEdit]
        public var declined: [ExternalRef]

        /// Every creation and edit, in the order creating makes them, in words.
        public var described: [String] {
            breakouts.map { "make \($0.displayTitle), a series of its own, at the top of the library" }
                + ["make \(documents.first?.displayTitle ?? "the tree") and the \(documents.count - 1) beneath it"]
                + (declined.isEmpty
                    ? [] : ["decline \(declined.count) of TMDb's specials in \(documents.first?.displayTitle ?? "")"])
                + heldEdits.map {
                    $0.ref != nil
                        ? "add TMDb's id to \($0.item ?? "") of \($0.container) in \($0.library)"
                        : "add an entry to \($0.container) in \($0.library)"
                }
        }
    }

    /// The tree as creating it would make it, every placement applied.
    public var making: Making {
        let made = containers.filter { isMade($0.id.value) }.map(leavingOut)
        var byID = Dictionary(made.map { ($0.id.value, $0) }, uniquingKeysWith: { first, _ in first })
        var order = made.map(\.id.value)
        var newBreakouts = Dictionary(
            breakouts.compactMap { id, _ in container(id).map { (id, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        var heldEdits: [Making.HeldEdit] = []
        var declined: [ExternalRef] = []

        for special in specials {
            guard let placement = placements[special.id] else { continue }
            switch placement {
            case .entry(let id, let sequence, let position):
                guard var container = byID[id] else { continue }
                Self.insert(
                    Self.leaf(special, type: .episode, in: container),
                    into: &container,
                    sequence: sequence,
                    at: position
                )
                byID[id] = container
            case .extra(let id, let type):
                guard var container = byID[id], let type = EntryType(rawValue: type) else { continue }
                container.extras.append(Self.leaf(special, type: type, in: container))
                byID[id] = container
            case .child(let id, let childID, let type):
                guard var parent = byID[id], let childID = ContainerID(childID),
                    let type = ContainerType(rawValue: type),
                    let title = Title(special.episode.title) ?? Title("Special")
                else { continue }
                var child = Container(id: childID, type: type, title: title)
                child.sequences = [Sequence(id: "parts", items: [Self.leaf(special, type: .episode, in: child)])]
                Self.insert(
                    .child(Entry.Child(id: Self.itemID(for: title.rawValue, in: parent), container: childID)),
                    into: &parent,
                    sequence: nil,
                    at: nil
                )
                byID[id] = parent
                byID[childID.value] = child
                order.append(childID.value)
            case .duplicate(let home, let item, let library, let from, let asExtra):
                guard var referrer = byID[from], let homeID = ContainerID(home), let itemID = ItemID(item) else {
                    continue
                }
                Self.refer(to: EntryRef(container: homeID, item: itemID), from: &referrer, asExtra: asExtra)
                byID[from] = referrer
                heldEdits.append(
                    .init(
                        library: library,
                        container: home,
                        item: item,
                        ref: special.episode.ref,
                        entry: nil,
                        entryID: nil
                    )
                )
            case .breakout(let breakoutID, let from, let asExtra):
                guard var referrer = byID[from], let breakout = ContainerID(breakoutID) else { continue }
                let entryID: ItemID
                if var made = newBreakouts[breakoutID] {
                    let leaf = Self.leaf(special, type: .episode, in: made)
                    entryID = leaf.id!
                    Self.insert(leaf, into: &made, sequence: nil, at: nil)
                    newBreakouts[breakoutID] = made
                } else {
                    // A breakout made before is not read here, so the entry's id is one no title it
                    // holds could have taken: the special's title with its TMDb id.
                    entryID = ItemID("\(Slug.make(from: special.episode.title))-\(special.id)")!
                    heldEdits.append(
                        .init(
                            library: library,
                            container: breakoutID,
                            item: nil,
                            ref: nil,
                            entry: special,
                            entryID: entryID.value
                        )
                    )
                }
                Self.refer(to: EntryRef(container: breakout, item: entryID), from: &referrer, asExtra: asExtra)
                byID[from] = referrer
            case .edition(let id, let title):
                guard var container = byID[id] else { continue }
                Self.edition(special, titled: title, in: &container)
                byID[id] = container
            case .version(let id, let item, let title):
                guard var container = byID[id] else { continue }
                Self.version(special, of: item, titled: title, in: &container)
                byID[id] = container
            case .declined:
                declined += special.refs.filter { $0.provider == .tmdb }
            }
        }

        let documents = order.compactMap { byID[$0] }
        let attributions = documents.flatMap { container in
            (self.attributions[container.id.value] ?? []).map {
                SiloClient.CreateAttribution(
                    container: container.id.value,
                    subject: $0.subject.rawValue,
                    provider: $0.provider.rawValue,
                    value: $0.value
                )
            }
        }
        return Making(
            documents: documents,
            attributions: attributions,
            breakouts: breakouts.keys.sorted().compactMap { newBreakouts[$0] },
            heldEdits: heldEdits,
            declined: declined
        )
    }

    /// A special as an entry of a container: its references, and no title, since TMDb has one for it.
    static func leaf(_ special: Special, type: EntryType, in container: Container) -> Entry {
        .leaf(
            Entry.Leaf(
                id: itemID(for: special.episode.title, in: container),
                type: type,
                externalRefs: special.refs
            )
        )
    }

    static func itemID(for title: String, in container: Container) -> ItemID {
        ItemID(Slug.unique(from: title, avoiding: Set(container.itemIDs.map(\.value))))!
    }

    static func insert(_ entry: Entry, into container: inout Container, sequence: String?, at position: Int?) {
        if container.sequences.isEmpty { container.sequences = [Sequence(items: [])] }
        let index = container.sequences.firstIndex { sequence != nil && $0.id == sequence } ?? 0
        let count = container.sequences[index].items.count
        container.sequences[index].items.insert(entry, at: min(max(position ?? count, 0), count))
    }

    /// A special as a new edition of a container: a sequence of its own holding it alone, and an
    /// alternative with the title given naming that sequence. The container's other sequences stay.
    static func edition(_ special: Special, titled title: String, in container: inout Container) {
        let entry = leaf(special, type: .episode, in: container)
        alternative(titled: title, playing: [entry], in: &container)
    }

    /// A special as a version of one item: a sequence holding it in the item's place and referring to
    /// each of the other items of the sequence the item is in, so each stays one entry, and an
    /// alternative with the title given naming it.
    static func version(_ special: Special, of item: String, titled title: String, in container: inout Container) {
        guard let source = container.sequences.first(where: { $0.items.contains { $0.id?.value == item } }) else {
            return
        }
        let entry = leaf(special, type: .episode, in: container)
        let items = source.items.map { other -> Entry in
            if other.id?.value == item { return entry }
            return other.id.map { .ref(EntryRef(item: $0)) } ?? other
        }
        alternative(titled: title, playing: items, in: &container)
    }

    private static func alternative(titled title: String, playing items: [Entry], in container: inout Container) {
        let sequence = Slug.unique(from: title, avoiding: Set(container.sequences.compactMap(\.id)))
        container.sequences.append(Sequence(id: sequence, items: items))
        container.alternatives.append(
            Alternative(
                id: Slug.unique(from: title, avoiding: Set(container.alternatives.map(\.id))),
                sequence: sequence,
                title: title
            )
        )
    }

    static func refer(to ref: EntryRef, from container: inout Container, asExtra: Bool) {
        if asExtra {
            container.extras.append(.ref(ref))
        } else {
            insert(.ref(ref), into: &container, sequence: nil, at: nil)
        }
    }
}

/// The drafts from TMDb this Mac keeps, by the `ServerID` of the silo each is for, kept as the
/// container drafts are: one JSON object rewritten atomically whole on every change.
public final class TMDbDraftStore: Sendable {
    public let file: URL
    private let entries: Mutex<[String: [TMDbTree]]>

    public init(file: URL) {
        self.file = file
        entries = Mutex(Self.read(file))
    }

    /// In memory only, for tests and for platforms where the app passes no file.
    public init() {
        file = URL(fileURLWithPath: "/dev/null")
        entries = Mutex([:])
    }

    /// A silo's drafts from TMDb, most recently edited first.
    public func drafts(of silo: String) -> [TMDbTree] {
        entries.withLock { $0[silo] ?? [] }.sorted { $0.edited > $1.edited }
    }

    public func save(_ tree: TMDbTree, for silo: String) throws {
        try entries.withLock { entries in
            var trees = entries[silo] ?? []
            if let index = trees.firstIndex(where: { $0.id == tree.id }) {
                trees[index] = tree
            } else {
                trees.append(tree)
            }
            entries[silo] = trees
            try Self.persist(entries, to: file)
        }
    }

    public func remove(_ id: TMDbTree.ID, of silo: String) throws {
        try entries.withLock { entries in
            guard let index = entries[silo]?.firstIndex(where: { $0.id == id }) else { return }
            entries[silo]?.remove(at: index)
            if entries[silo]?.isEmpty == true { entries[silo] = nil }
            try Self.persist(entries, to: file)
        }
    }

    /// Every draft from TMDb for the silo, gone: forgetting's share.
    public func removeAll(of silo: String) throws {
        try entries.withLock { entries in
            guard entries.removeValue(forKey: silo) != nil else { return }
            try Self.persist(entries, to: file)
        }
    }

    private static func persist(_ entries: [String: [TMDbTree]], to file: URL) throws {
        guard file.path != "/dev/null" else { return }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(entries).write(to: file, options: .atomic)
    }

    private static func read(_ file: URL) -> [String: [TMDbTree]] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: [TMDbTree]].self, from: Data(contentsOf: file))) ?? [:]
    }
}
