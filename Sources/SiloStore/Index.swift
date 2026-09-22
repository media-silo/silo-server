// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import GRDB
import SmdKit
import SmdSidecar

/// The index: what the silo answers requests from. A SQLite file, derived from the sidecars and
/// rebuilt from them, holding nothing they do not. `Silo.md`, *The index*: a cache, and the file
/// can be thrown away.
///
/// One row per container, item, presentation and external reference, and one per sidecar with
/// the modification time and size the next scan compares against. The container row also keeps
/// the sidecar's bytes, so that one container's detail, or its `.smd` projection, is one read
/// and one parse rather than a join across five tables.
///
/// A value: its only state is the handle to the queue, which serialises access itself, so there
/// is nothing here for identity to protect.
public struct Index: Sendable {
    private let queue: DatabaseQueue

    /// Opens or creates the index at `url`; `nil` keeps it in memory, for tests.
    public init(at url: URL?) throws {
        queue = try url.map { try DatabaseQueue(path: $0.path) } ?? DatabaseQueue()
        try Self.migrator.migrate(queue)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "container") { t in
                t.primaryKey("id", .text)
                t.column("library", .text).notNull().indexed()
                t.column("folder", .text).notNull()
                t.column("parent", .text).indexed()
                t.column("type", .text).notNull()
                t.column("title", .text).notNull()
                t.column("displayTitle", .text).notNull().indexed()
                t.column("year", .integer)
                t.column("typeLabel", .text)
                t.column("outline", .text)
                t.column("listed", .boolean).notNull()
                t.column("document", .blob).notNull()
            }
            try db.create(table: "item") { t in
                t.column("container", .text).notNull().references("container", onDelete: .cascade)
                t.column("id", .text).notNull()
                t.column("position", .integer).notNull()
                t.column("sequence", .text)
                t.column("isExtra", .boolean).notNull()
                t.column("type", .text)
                t.column("title", .text).indexed()
                t.column("childContainer", .text)
                t.primaryKey(["container", "id"])
            }
            try db.create(table: "presentation") { t in
                t.primaryKey("id", .text)
                t.column("library", .text).notNull()
                t.column("container", .text).notNull().references("container", onDelete: .cascade).indexed()
                t.column("item", .text).notNull()
                t.column("alternative", .text)
                t.column("profile", .text)
                t.column("file", .text).notNull()
                t.column("path", .text).notNull()
            }
            try db.create(table: "externalRef") { t in
                t.column("container", .text).notNull().references("container", onDelete: .cascade)
                t.column("item", .text)
                t.column("provider", .text).notNull()
                t.column("value", .text).notNull()
                t.uniqueKey(["container", "item", "provider", "value"])
            }
            try db.create(index: "externalRef_lookup", on: "externalRef", columns: ["provider", "value"])
            try db.create(table: "sidecar") { t in
                t.column("library", .text).notNull()
                t.column("path", .text).notNull()
                t.column("container", .text).notNull()
                t.column("modified", .double)
                t.column("size", .integer)
                t.primaryKey(["library", "path"])
            }
        }
        return migrator
    }

    // MARK: - Reading

    public func roots(in library: String? = nil, listedOnly: Bool = true) throws -> [IndexedContainer] {
        try queue.read { db in
            var request = IndexedContainer.filter(Column("parent") == nil).order(Column("displayTitle"))
            if let library { request = request.filter(Column("library") == library) }
            if listedOnly { request = request.filter(Column("listed") == true) }
            return try request.fetchAll(db)
        }
    }

    public func container(_ id: ContainerID) throws -> IndexedContainer? {
        try queue.read { db in try IndexedContainer.fetchOne(db, key: id.rawValue) }
    }

    /// The container's sidecar, parsed from the bytes the row keeps.
    public func sidecar(_ id: ContainerID) throws -> Sidecar? {
        guard let row = try container(id) else { return nil }
        return try SidecarFile.sidecar(from: row.document)
    }

    public func children(of id: ContainerID) throws -> [IndexedContainer] {
        try queue.read { db in
            try IndexedContainer.filter(Column("parent") == id.rawValue).order(Column("displayTitle")).fetchAll(db)
        }
    }

    public func items(of id: ContainerID) throws -> [IndexedItem] {
        try queue.read { db in
            try IndexedItem.filter(Column("container") == id.rawValue).order(Column("position")).fetchAll(db)
        }
    }

    public func presentations(of id: ContainerID) throws -> [IndexedPresentation] {
        try queue.read { db in
            try IndexedPresentation.filter(Column("container") == id.rawValue).order(Column("item"), Column("id")).fetchAll(db)
        }
    }

    public func presentation(_ id: String) throws -> IndexedPresentation? {
        try queue.read { db in try IndexedPresentation.fetchOne(db, key: id) }
    }

    /// Containers a provider's id names, directly or through one of their items.
    public func lookup(provider: Provider, value: String) throws -> [IndexedContainer] {
        try queue.read { db in
            let ids = try String.fetchAll(db, sql: "SELECT DISTINCT container FROM externalRef WHERE provider = ? AND value = ?", arguments: [provider.rawValue, value])
            return try IndexedContainer.filter(keys: ids).order(Column("displayTitle")).fetchAll(db)
        }
    }

    /// Containers and items whose title contains the text, case-insensitively.
    public func search(_ text: String, limit: Int = 50) throws -> [SearchHit] {
        let pattern = "%\(text.replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_"))%"
        return try queue.read { db in
            let containers = try IndexedContainer
                .filter(sql: "displayTitle LIKE ? ESCAPE '\\'", arguments: [pattern])
                .order(Column("displayTitle")).limit(limit).fetchAll(db)
            let items = try IndexedItem
                .filter(sql: "title LIKE ? ESCAPE '\\'", arguments: [pattern])
                .order(Column("title")).limit(limit).fetchAll(db)
            return containers.map { SearchHit(container: $0.id, item: nil, title: $0.displayTitle) }
                + items.map { SearchHit(container: $0.container, item: $0.id, title: $0.title ?? $0.id) }
        }
    }

    public func sidecars(in library: String) throws -> [IndexedSidecar] {
        try queue.read { db in try IndexedSidecar.filter(Column("library") == library).fetchAll(db) }
    }

    public func count() throws -> (containers: Int, presentations: Int) {
        try queue.read { db in
            (try IndexedContainer.fetchCount(db), try IndexedPresentation.fetchCount(db))
        }
    }

    // MARK: - Writing

    /// Replaces everything the index holds about one container with what its sidecar says.
    func store(_ entry: IndexEntry) throws {
        try queue.write { db in
            try IndexedContainer.deleteOne(db, key: entry.container.id)
            try entry.container.insert(db)
            for item in entry.items { try item.insert(db) }
            for presentation in entry.presentations { try presentation.insert(db) }
            for ref in entry.externalRefs { try ref.insert(db) }
            try IndexedSidecar.filter(Column("library") == entry.sidecar.library && Column("path") == entry.sidecar.path).deleteAll(db)
            try entry.sidecar.insert(db)
        }
    }

    func remove(sidecarsAt paths: [String], in library: String) throws {
        try queue.write { db in
            for path in paths {
                if let row = try IndexedSidecar.filter(Column("library") == library && Column("path") == path).fetchOne(db) {
                    try IndexedContainer.deleteOne(db, key: row.container)
                    try row.delete(db)
                }
            }
        }
    }

    func setParent(_ parent: ContainerID?, of child: ContainerID) throws {
        try queue.write { db in
            try db.execute(sql: "UPDATE container SET parent = ? WHERE id = ?", arguments: [parent?.rawValue, child.rawValue])
        }
    }
}

// MARK: - Rows

public struct IndexedContainer: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "container"

    public var id: String
    public var library: String
    /// The container's folder relative to the library root.
    public var folder: String
    public var parent: String?
    public var type: String
    public var title: String
    public var displayTitle: String
    public var year: Int?
    public var typeLabel: String?
    public var outline: String?
    public var listed: Bool
    /// The sidecar's bytes.
    public var document: Data

    public var containerID: ContainerID { ContainerID(id)! }
}

public struct IndexedItem: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "item"

    public var container: String
    public var id: String
    public var position: Int
    public var sequence: String?
    public var isExtra: Bool
    public var type: String?
    public var title: String?
    public var childContainer: String?
}

public struct IndexedPresentation: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "presentation"

    /// Stable across rescans: a hash of the library and the file's path in it.
    public var id: String
    public var library: String
    public var container: String
    public var item: String
    public var alternative: String?
    public var profile: String?
    /// As the sidecar names it, relative to the container's folder.
    public var file: String
    /// Relative to the library root.
    public var path: String

    public static func id(library: String, path: String) -> String {
        // FNV-1a, 64 bits: stable, dependency-free, and not asked to resist anything.
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in "\(library)|\(path)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}

public struct IndexedExternalRef: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "externalRef"

    public var container: String
    public var item: String?
    public var provider: String
    public var value: String
}

public struct IndexedSidecar: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "sidecar"

    public var library: String
    /// The sidecar relative to the library root.
    public var path: String
    public var container: String
    public var modified: Double?
    public var size: Int?
}

public struct SearchHit: Hashable, Sendable, Codable {
    public var container: String
    public var item: String?
    public var title: String
}

/// Everything one sidecar contributes, as rows.
struct IndexEntry {
    var container: IndexedContainer
    var items: [IndexedItem]
    var presentations: [IndexedPresentation]
    var externalRefs: [IndexedExternalRef]
    var sidecar: IndexedSidecar

    init(sidecar: Sidecar, document: Data, library: String, folder: String, parent: ContainerID?, modified: Date?, size: Int?) {
        let container = sidecar.container
        self.container = IndexedContainer(
            id: container.id.rawValue, library: library, folder: folder, parent: parent?.rawValue,
            type: container.type.rawValue, title: container.title, displayTitle: container.displayTitle,
            year: container.year, typeLabel: container.typeLabel, outline: container.outline,
            listed: container.listed, document: document
        )
        var items: [IndexedItem] = []
        var position = 0
        for sequence in container.sequences {
            for entry in sequence.items {
                guard let id = entry.id else { continue }
                items.append(IndexedItem(container: container.id.rawValue, id: id, position: position, sequence: sequence.id, isExtra: false, type: entry.type?.rawValue, title: entry.title, childContainer: entry.container?.rawValue))
                position += 1
            }
        }
        for entry in container.extras {
            guard let id = entry.id else { continue }
            items.append(IndexedItem(container: container.id.rawValue, id: id, position: position, sequence: nil, isExtra: true, type: entry.type?.rawValue, title: entry.title, childContainer: entry.container?.rawValue))
            position += 1
        }
        self.items = items
        self.presentations = sidecar.presentations.sorted(by: { $0.key < $1.key }).flatMap { item, presentations in
            presentations.map { presentation in
                let path = folder.isEmpty ? presentation.file : "\(folder)/\(presentation.file)"
                return IndexedPresentation(
                    id: IndexedPresentation.id(library: library, path: path), library: library,
                    container: container.id.rawValue, item: item, alternative: presentation.alternative,
                    profile: presentation.profile, file: presentation.file, path: path
                )
            }
        }
        var refs = container.externalRefs.map { IndexedExternalRef(container: container.id.rawValue, item: nil, provider: $0.provider.rawValue, value: $0.value) }
        for entry in container.sequences.flatMap(\.items) + container.extras {
            for ref in entry.externalRefs {
                refs.append(IndexedExternalRef(container: container.id.rawValue, item: entry.id, provider: ref.provider.rawValue, value: ref.value))
            }
        }
        self.externalRefs = Array(Set(refs))
        self.sidecar = IndexedSidecar(library: library, path: folder.isEmpty ? SidecarFile.fileName : "\(folder)/\(SidecarFile.fileName)", container: container.id.rawValue, modified: modified?.timeIntervalSince1970, size: size)
    }
}
