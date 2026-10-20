// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloClient
import SmdKit
import SmdSidecar
import Synchronization

/// A container's own fields being changed in one library: its repository document as the operator
/// edits it, and the digest of the library's sidecar it was made from, its base, which a store names
/// so that the silo refuses one landing on a sidecar the operator never saw. Kept on this Mac by a
/// `ContainerDraftStore` until it is stored or discarded, as a ruleset's draft is; the silo holds the
/// sidecar, and never a draft.
public struct ContainerDraft: Hashable, Sendable, Identifiable, Codable {
    public let id: UUID
    public var library: String
    /// The container's id.
    public var container: String
    /// The container's display title when the draft was made, to list it by.
    public var title: String
    /// The digest of the sidecar it was made from.
    public var base: String
    /// The base's container as its repository document, what the draft's difference is read against.
    public var baseText: String
    public var text: String
    /// When the text last changed.
    public var edited: Date
    /// Where a container the library does not hold yet is to be made, for a draft of a new one; nil
    /// for a draft of a change to a container the library holds. A new container has no base: its
    /// `base` and `baseText` are empty.
    public var creating: Creating?

    /// Where a new container is filed: beneath `parent`, a container the library holds, as the item
    /// `item` at `position` in its sequence `sequence`; or, with no parent, at the top of the library.
    public struct Creating: Hashable, Sendable, Codable {
        public var parent: String?
        public var sequence: String?
        public var item: String?
        public var position: Int?

        public init(parent: String? = nil, sequence: String? = nil, item: String? = nil, position: Int? = nil) {
            self.parent = parent
            self.sequence = sequence
            self.item = item
            self.position = position
        }
    }

    public init(
        library: String,
        container: String,
        title: String,
        base: String,
        baseText: String,
        text: String,
        edited: Date = .now
    ) {
        id = UUID()
        self.library = library
        self.container = container
        self.title = title
        self.base = base
        self.baseText = baseText
        self.text = text
        self.edited = edited
    }

    /// A change from the library's container on screen, whose sidecar is its base.
    public static func change(_ opened: SiloClient.LibraryContainer, sidecar: Data) throws -> ContainerDraft {
        let document = try Self.document(of: sidecar)
        return ContainerDraft(
            library: opened.library,
            container: opened.container.id,
            title: opened.container.displayTitle,
            base: opened.digest,
            baseText: document,
            text: document
        )
    }

    /// A new container, with the id `id` — the one smddb's client issued — at the top of a library or
    /// beneath a container it holds. Its text is the container's document; it has no base.
    public static func new(_ container: Container, in library: String, at creating: Creating) -> ContainerDraft {
        var draft = ContainerDraft(
            library: library,
            container: container.id.value,
            title: container.displayTitle,
            base: "",
            baseText: "",
            text: String(decoding: ContainerFile.data(for: container), as: UTF8.self)
        )
        draft.creating = creating
        return draft
    }

    /// Whether the draft is of a container the library does not hold yet.
    public var isNew: Bool { creating != nil }

    /// The draft re-based on the sidecar that landed since: its text as it is, read against the new base.
    public func rebased(on landed: SiloClient.LibraryContainer, sidecar: Data) throws -> ContainerDraft {
        var rebased = self
        rebased.base = landed.digest
        rebased.baseText = try Self.document(of: sidecar)
        return rebased
    }

    /// A sidecar's container as its repository document: its own fields, without the library's facts.
    public static func document(of sidecar: Data) throws -> String {
        String(decoding: ContainerFile.data(for: try SidecarFile.sidecar(from: sidecar).container), as: UTF8.self)
    }

    /// The text as a container, or nil when it does not read as one.
    public var value: Container? {
        try? ContainerFile.container(from: Data(text.utf8))
    }

    /// The text made the container's document, as the form changes it.
    public mutating func set(_ container: Container) {
        text = String(decoding: ContainerFile.data(for: container), as: UTF8.self)
        edited = .now
    }

    /// Whether the text says anything other than its base. A new container always does.
    public var isChanged: Bool { isNew || text != baseText }

    /// Whether the library's sidecar is no longer the one the draft was made from: a store would be
    /// refused, so it is to be re-based first. A new container has no sidecar to fall behind.
    public func isBehind(_ digest: String) -> Bool { !isNew && digest != base }

    /// The text's difference from its base, line by line.
    public var difference: [LineDifference.Line] { LineDifference.lines(from: baseText, to: text) }
}

/// The container drafts this Mac keeps, by the `ServerID` of the silo each is for: one JSON object
/// rewritten atomically whole on every change, as the ruleset drafts are, and ending as they do.
public final class ContainerDraftStore: Sendable {
    public let file: URL
    private let entries: Mutex<[String: [ContainerDraft]]>

    public init(file: URL) {
        self.file = file
        entries = Mutex(Self.read(file))
    }

    /// In memory only, for tests and for platforms where the app passes no file.
    public init() {
        file = URL(fileURLWithPath: "/dev/null")
        entries = Mutex([:])
    }

    /// A silo's drafts, by library and title, then most recently edited first.
    public func drafts(of silo: String) -> [ContainerDraft] {
        entries.withLock { $0[silo] ?? [] }.sorted {
            ($0.library, $0.title, $1.edited) < ($1.library, $1.title, $0.edited)
        }
    }

    /// The draft kept for a container in a library, when there is one.
    public func draft(of container: String, in library: String, of silo: String) -> ContainerDraft? {
        entries.withLock { $0[silo]?.first { $0.container == container && $0.library == library } }
    }

    /// Keeps the draft, replacing the one with its id.
    public func save(_ draft: ContainerDraft, for silo: String) throws {
        try entries.withLock { entries in
            var drafts = entries[silo] ?? []
            if let index = drafts.firstIndex(where: { $0.id == draft.id }) {
                drafts[index] = draft
            } else {
                drafts.append(draft)
            }
            entries[silo] = drafts
            try Self.persist(entries, to: file)
        }
    }

    public func remove(_ id: ContainerDraft.ID, of silo: String) throws {
        try entries.withLock { entries in
            guard let index = entries[silo]?.firstIndex(where: { $0.id == id }) else { return }
            entries[silo]?.remove(at: index)
            if entries[silo]?.isEmpty == true { entries[silo] = nil }
            try Self.persist(entries, to: file)
        }
    }

    /// Every draft for the silo, gone: forgetting's share.
    public func removeAll(of silo: String) throws {
        try entries.withLock { entries in
            guard entries.removeValue(forKey: silo) != nil else { return }
            try Self.persist(entries, to: file)
        }
    }

    private static func persist(_ entries: [String: [ContainerDraft]], to file: URL) throws {
        guard file.path != "/dev/null" else { return }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(entries).write(to: file, options: .atomic)
    }

    private static func read(_ file: URL) -> [String: [ContainerDraft]] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: [ContainerDraft]].self, from: Data(contentsOf: file))) ?? [:]
    }
}
