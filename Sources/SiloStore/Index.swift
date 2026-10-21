// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Crypto
import Foundation
import GRDB
import SiloLibrary
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
        // Wait on a lock rather than fail: the operator's command line and the silo may open one
        // index file, and a scan holds it for a moment.
        var configuration = GRDB.Configuration()
        configuration.busyMode = .timeout(5)
        queue =
            try url.map { try DatabaseQueue(path: $0.path, configuration: configuration) }
            ?? DatabaseQueue(configuration: configuration)
        try Self.migrator.migrate(queue)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        // A container is keyed by its library and its id, since one container may be filed in several
        // libraries, each with a sidecar of its own.
        migrator.registerMigration("v1") { db in
            try db.create(table: "container") { table in
                table.column("library", .text).notNull()
                table.column("id", .text).notNull()
                table.column("folder", .text).notNull()
                table.column("parent", .text)
                table.column("type", .text).notNull()
                table.column("title", .text).notNull()
                table.column("displayTitle", .text).notNull().indexed()
                table.column("year", .integer)
                table.column("typeLabel", .text)
                table.column("outline", .text)
                table.column("listed", .boolean).notNull()
                table.column("document", .blob).notNull()
                table.primaryKey(["library", "id"])
            }
            try db.create(index: "container_parent", on: "container", columns: ["library", "parent"])
            try db.create(index: "container_id", on: "container", columns: ["id"])
            try db.create(table: "item") { table in
                table.column("library", .text).notNull()
                table.column("container", .text).notNull()
                table.column("id", .text).notNull()
                table.column("position", .integer).notNull()
                table.column("sequence", .text)
                table.column("isExtra", .boolean).notNull()
                table.column("type", .text)
                table.column("title", .text).indexed()
                table.column("childContainer", .text)
                table.primaryKey(["library", "container", "id"])
                table.foreignKey(
                    ["library", "container"],
                    references: "container",
                    columns: ["library", "id"],
                    onDelete: .cascade
                )
            }
            try db.create(table: "presentation") { table in
                table.primaryKey("id", .text)
                table.column("library", .text).notNull()
                table.column("container", .text).notNull()
                table.column("item", .text).notNull()
                table.column("alternative", .text)
                table.column("profile", .text)
                table.column("file", .text).notNull()
                table.column("path", .text).notNull()
                table.foreignKey(
                    ["library", "container"],
                    references: "container",
                    columns: ["library", "id"],
                    onDelete: .cascade
                )
            }
            try db.create(index: "presentation_container", on: "presentation", columns: ["library", "container"])
            try db.create(table: "externalRef") { table in
                table.column("library", .text).notNull()
                table.column("container", .text).notNull()
                table.column("item", .text)
                table.column("provider", .text).notNull()
                table.column("value", .text).notNull()
                table.uniqueKey(["library", "container", "item", "provider", "value"])
                table.foreignKey(
                    ["library", "container"],
                    references: "container",
                    columns: ["library", "id"],
                    onDelete: .cascade
                )
            }
            try db.create(index: "externalRef_lookup", on: "externalRef", columns: ["provider", "value"])
            try db.create(table: "sidecar") { table in
                table.column("library", .text).notNull()
                table.column("path", .text).notNull()
                table.column("container", .text).notNull()
                table.column("modified", .double)
                table.column("size", .integer)
                table.primaryKey(["library", "path"])
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

    /// The container as one library holds it.
    public func container(_ id: ContainerID, in library: String) throws -> IndexedContainer? {
        try queue.read { db in try IndexedContainer.fetchOne(db, key: ["library": library, "id": id.value]) }
    }

    /// The container as each library that holds it holds it, in no particular order: the caller knows
    /// the order the libraries are listed in, and the index does not.
    public func containers(_ id: ContainerID) throws -> [IndexedContainer] {
        try queue.read { db in try IndexedContainer.filter(Column("id") == id.value).fetchAll(db) }
    }

    /// The container's sidecar in one library, parsed from the bytes the row keeps.
    public func sidecar(_ id: ContainerID, in library: String) throws -> Sidecar? {
        guard let row = try container(id, in: library) else { return nil }
        return try SidecarFile.sidecar(from: row.document)
    }

    public func children(of id: ContainerID, in library: String) throws -> [IndexedContainer] {
        try queue.read { db in
            try IndexedContainer.filter(Column("library") == library && Column("parent") == id.value).order(
                Column("displayTitle")
            ).fetchAll(db)
        }
    }

    public func items(of id: ContainerID, in library: String) throws -> [IndexedItem] {
        try queue.read { db in
            try IndexedItem.filter(Column("library") == library && Column("container") == id.value).order(
                Column("position")
            ).fetchAll(db)
        }
    }

    public func presentations(of id: ContainerID, in library: String) throws -> [IndexedPresentation] {
        try queue.read { db in
            try IndexedPresentation.filter(Column("library") == library && Column("container") == id.value).order(
                Column("item"),
                Column("id")
            ).fetchAll(db)
        }
    }

    public func presentation(_ id: String) throws -> IndexedPresentation? {
        try queue.read { db in try IndexedPresentation.fetchOne(db, key: id) }
    }

    /// Containers a provider's id names, directly or through one of their items: once for each library
    /// that holds one.
    public func lookup(provider: Provider, value: String) throws -> [IndexedContainer] {
        try queue.read { db in
            try IndexedContainer.fetchAll(
                db,
                sql: """
                    SELECT * FROM container WHERE (library, id) IN (SELECT library, container FROM externalRef WHERE provider = ? AND value = ?)
                    ORDER BY displayTitle, library
                    """,
                arguments: [provider.rawValue, value]
            )
        }
    }

    /// Containers and items whose title contains the text, case-insensitively. A container in several
    /// libraries is one hit, since a hit names the container and not where it is held.
    public func search(_ text: String, limit: Int = 50) throws -> [SearchHit] {
        let pattern = "%\(text.replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_"))%"
        return try queue.read { db in
            let containers =
                try IndexedContainer
                .filter(sql: "displayTitle LIKE ? ESCAPE '\\'", arguments: [pattern])
                .order(Column("displayTitle")).limit(limit).fetchAll(db)
            let items =
                try IndexedItem
                .filter(sql: "title LIKE ? ESCAPE '\\'", arguments: [pattern])
                .order(Column("title")).limit(limit).fetchAll(db)
            var seen: Set<SearchHit> = []
            return
                (containers.map { SearchHit(container: $0.id, item: nil, title: $0.displayTitle) }
                + items.map { SearchHit(container: $0.container, item: $0.id, title: $0.title ?? $0.id) })
                .filter { seen.insert($0).inserted }
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
            try IndexedContainer.deleteOne(db, key: ["library": entry.container.library, "id": entry.container.id])
            try entry.container.insert(db)
            for item in entry.items { try item.insert(db) }
            for presentation in entry.presentations { try presentation.insert(db) }
            for ref in entry.externalRefs { try ref.insert(db) }
            try IndexedSidecar.filter(
                Column("library") == entry.sidecar.library && Column("path") == entry.sidecar.path
            ).deleteAll(db)
            try entry.sidecar.insert(db)
        }
    }

    /// Forgets the sidecars at these paths, and each one's container with it unless the library's row
    /// for that container is now another folder's: a second sidecar for a container is not indexed,
    /// and forgetting it leaves the first.
    func remove(sidecarsAt paths: [String], in library: String) throws {
        try queue.write { db in
            for path in paths {
                if let row = try IndexedSidecar.filter(Column("library") == library && Column("path") == path).fetchOne(
                    db
                ) {
                    let folder =
                        path == SidecarFile.fileName ? "" : String(path.dropLast(SidecarFile.fileName.count + 1))
                    try IndexedContainer.filter(
                        Column("library") == library && Column("id") == row.container && Column("folder") == folder
                    ).deleteAll(db)
                    try row.delete(db)
                }
            }
        }
    }

    /// Forgets everything the index holds for a library: a library removed is no longer served.
    public func forget(library: String) throws {
        try queue.write { db in
            try IndexedContainer.filter(Column("library") == library).deleteAll(db)
            try IndexedSidecar.filter(Column("library") == library).deleteAll(db)
        }
    }

    func setParent(_ parent: ContainerID?, of child: ContainerID, in library: String) throws {
        try queue.write { db in
            try db.execute(
                sql: "UPDATE container SET parent = ? WHERE library = ? AND id = ?",
                arguments: [parent?.value, library, child.value]
            )
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

    /// What an edit names to say which sidecar it was made from: the SHA-256 of the sidecar's bytes
    /// as the index read them, in lowercase hexadecimal.
    public var digest: String { Self.digest(of: document) }

    public static func digest(of document: Data) -> String {
        SHA256.hash(data: document).map { String(format: "%02x", $0) }.joined()
    }
}

public struct IndexedItem: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "item"

    public var library: String
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

    /// What the presentation is, hashed: its library, container, item, alternative and profile. Where
    /// its file is plays no part, so a move changes no id.
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

    public static func id(
        library: String,
        container: String,
        item: String,
        alternative: String?,
        profile: String?
    ) -> String {
        // FNV-1a, 64 bits: stable, dependency-free, and not asked to resist anything.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "\(library)|\(container)|\(item)|\(alternative ?? "")|\(profile ?? "")".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return String(format: "%016llx", hash)
    }

    /// The id of the presentation a placement records.
    public static func id(library: String, placed placement: Placement) -> String {
        id(
            library: library,
            container: placement.container.value,
            item: placement.item,
            alternative: placement.presentation.alternative,
            profile: placement.presentation.profile
        )
    }
}

public struct IndexedExternalRef: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "externalRef"

    public var library: String
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
    /// Presentations not indexed, because another before them in the sidecar has their id or names
    /// their file.
    var findings: [Finding] = []

    init(
        sidecar: Sidecar,
        document: Data,
        library: String,
        folder: String,
        parent: ContainerID?,
        modified: Date?,
        size: Int?
    ) {
        let container = sidecar.container
        self.container = IndexedContainer(
            id: container.id.value,
            library: library,
            folder: folder,
            parent: parent?.value,
            type: container.type.rawValue,
            title: container.title.rawValue,
            displayTitle: container.displayTitle,
            year: container.year,
            typeLabel: container.typeLabel,
            outline: container.outline,
            listed: container.listed,
            document: document
        )
        self.items = Self.items(of: container, library: library)
        // The walk does not trust a sidecar to have been validated: the first of two presentations
        // sharing an id or a file is indexed, and the second reported.
        var presentations: [IndexedPresentation] = []
        var ids: Set<String> = []
        var files: Set<String> = []
        for (item, itemPresentations) in sidecar.presentations.sorted(by: { $0.key < $1.key }) {
            for presentation in itemPresentations {
                let id = IndexedPresentation.id(
                    library: library,
                    container: container.id.value,
                    item: item,
                    alternative: presentation.alternative,
                    profile: presentation.profile
                )
                guard ids.insert(id).inserted else {
                    findings.append(
                        Finding(.error, "item \(item) has two presentations for the same alternative and profile")
                    )
                    continue
                }
                guard files.insert(presentation.file).inserted else {
                    findings.append(
                        Finding(.error, "item \(item): \"\(presentation.file)\" is named by another presentation")
                    )
                    continue
                }
                presentations.append(
                    IndexedPresentation(
                        id: id,
                        library: library,
                        container: container.id.value,
                        item: item,
                        alternative: presentation.alternative,
                        profile: presentation.profile,
                        file: presentation.file,
                        path: folder.isEmpty ? presentation.file : "\(folder)/\(presentation.file)"
                    )
                )
            }
        }
        self.presentations = presentations
        self.externalRefs = Self.externalRefs(of: container, library: library)
        self.sidecar = IndexedSidecar(
            library: library,
            path: folder.isEmpty ? SidecarFile.fileName : "\(folder)/\(SidecarFile.fileName)",
            container: container.id.value,
            modified: modified?.timeIntervalSince1970,
            size: size
        )
    }

    /// The container's items, sequences' first in order and then its extras, positioned in that order.
    private static func items(of container: Container, library: String) -> [IndexedItem] {
        var items: [IndexedItem] = []
        var position = 0
        for sequence in container.sequences {
            for entry in sequence.items {
                guard let id = entry.id?.value else { continue }
                items.append(
                    IndexedItem(
                        library: library,
                        container: container.id.value,
                        id: id,
                        position: position,
                        sequence: sequence.id,
                        isExtra: false,
                        type: entry.indexedType,
                        title: entry.title,
                        childContainer: entry.childContainer?.value
                    )
                )
                position += 1
            }
        }
        for entry in container.extras {
            guard let id = entry.id?.value else { continue }
            items.append(
                IndexedItem(
                    library: library,
                    container: container.id.value,
                    id: id,
                    position: position,
                    sequence: nil,
                    isExtra: true,
                    type: entry.indexedType,
                    title: entry.title,
                    childContainer: entry.childContainer?.value
                )
            )
            position += 1
        }
        return items
    }

    /// The container's references and its items', once each.
    private static func externalRefs(of container: Container, library: String) -> [IndexedExternalRef] {
        var refs = container.externalRefs.map {
            IndexedExternalRef(
                library: library,
                container: container.id.value,
                item: nil,
                provider: $0.provider.rawValue,
                value: $0.value
            )
        }
        for entry in container.sequences.flatMap(\.items) + container.extras {
            for ref in entry.externalRefs {
                refs.append(
                    IndexedExternalRef(
                        library: library,
                        container: container.id.value,
                        item: entry.id?.value,
                        provider: ref.provider.rawValue,
                        value: ref.value
                    )
                )
            }
        }
        return Array(Set(refs))
    }
}

extension Entry {
    /// What the index records as an item's type: a leaf's own, or `container` for a child, as the
    /// sidecar's `<item type>` spells it.
    fileprivate var indexedType: String? {
        type?.rawValue ?? (childContainer != nil ? "container" : nil)
    }
}
