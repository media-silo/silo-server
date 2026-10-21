// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloKit
import SmdKit
import SmdSidecar

/// Where things go in a library. `Silo.md`, *Layout*: every container has a folder named from
/// its display title, after its position among its parent's children for a child, nested as the tree nests, with `container.smd` inside; a presentation is
/// `{item} - {display name}.mkv` beside it, or under `extras/` for an extra; a path in a sidecar
/// is relative to the folder holding it and never leaves the container's folder.
public enum LibraryLayout {
    public static let sidecarFileName = SidecarFile.fileName
    public static let extrasFolder = "extras"

    /// A title as a folder or file name: the two characters no filesystem here allows in a name
    /// replaced, whitespace collapsed, and nothing that would hide the entry or walk out of the
    /// folder. Empty after all that, the caller falls back to an id.
    public static func sanitise(_ name: String) -> String {
        var text =
            name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\0", with: "")
        text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        while text.hasPrefix(".") { text.removeFirst() }
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// A child's place among its parent's children: counted from one, in the order the parent's
    /// sequences and then its extras name its distinct children, and how many there are.
    public struct Position: Hashable, Sendable {
        public var number: Int
        public var count: Int

        public init(number: Int, count: Int) {
            self.number = number
            self.count = count
        }

        /// Where the child is among the parent's children, or nil when the parent does not hold it.
        public init?(of child: ContainerID, among children: [ContainerID]) {
            var seen: Set<ContainerID> = []
            let distinct = children.filter { seen.insert($0).inserted }
            guard let index = distinct.firstIndex(of: child) else { return nil }
            self.init(number: index + 1, count: distinct.count)
        }

        public init?(of child: ContainerID, in parent: Container) {
            self.init(of: child, among: parent.childContainerIDs)
        }

        /// The number padded with zeros to two digits, or to as many as the count needs.
        public var prefix: String {
            let width = max(2, String(count).count)
            let digits = String(number)
            return String(repeating: "0", count: max(0, width - digits.count)) + digits + " - "
        }
    }

    /// A root's folder: its display title.
    public static func folderName(for container: Container) -> String {
        folderName(displayTitle: container.displayTitle, id: container.id)
    }

    /// A child's folder: its position among its parent's children, then its display title. A
    /// container the parent does not hold is named as a root is.
    public static func folderName(for container: Container, in parent: Container?) -> String {
        folderName(
            displayTitle: container.displayTitle,
            id: container.id,
            position: parent.flatMap { Position(of: container.id, in: $0) }
        )
    }

    public static func folderName(displayTitle: String, id: ContainerID, position: Position? = nil) -> String {
        let sanitised = sanitise(displayTitle)
        let name = sanitised.isEmpty ? id.value : sanitised
        return (position?.prefix ?? "") + name
    }

    /// The warning for a container's folder that is not named as the layout would name it now: its
    /// display title, after its position for a container held as a child.
    public static func folderFinding(
        folder relativeFolder: String,
        displayTitle: String,
        id: ContainerID,
        position: Position? = nil
    ) -> Finding? {
        let name = (relativeFolder as NSString).lastPathComponent
        let expected = folderName(displayTitle: displayTitle, id: id, position: position)
        guard !name.isEmpty, name != expected else { return nil }
        return Finding(
            .warning,
            path: "\(relativeFolder)/\(sidecarFileName)",
            "folder \"\(name)\" is not the name the layout would give it, \"\(expected)\""
        )
    }

    /// The `smd` path a parent's sidecar records for a child: the child's folder, inside the
    /// parent's, and the sidecar in it.
    public static func childPath(for child: Container, in parent: Container) -> String {
        childPath(folder: folderName(for: child, in: parent))
    }

    public static func childPath(folder: String) -> String {
        "\(folder)/\(sidecarFileName)"
    }

    /// The child's folder a parent's sidecar records, relative to the parent's folder, when it
    /// records one that is a sidecar inside it.
    public static func recordedFolder(of child: ContainerID, in sidecar: Sidecar) -> String? {
        guard let path = sidecar.children[child], isInside(path), path.hasSuffix("/\(sidecarFileName)") else {
            return nil
        }
        return String(path.dropLast(sidecarFileName.count + 1))
    }

    /// `{item} - {display name}.ext`, or `{item}.ext` for the unqualified presentation of the
    /// default alternative. The item is its title, or its id when it has none.
    public static func fileName(for item: Entry, displayName: String?, fileExtension: String) -> String {
        var stem = sanitise(item.title ?? "")
        if stem.isEmpty { stem = item.id?.value ?? "item" }
        if let displayName, !sanitise(displayName).isEmpty {
            stem += " - \(sanitise(displayName))"
        }
        return "\(stem).\(fileExtension)"
    }

    /// The path a sidecar records for a presentation of an item, relative to the sidecar's folder.
    public static func relativePath(
        for item: Entry,
        isExtra: Bool,
        displayName: String?,
        fileExtension: String
    ) -> String {
        let name = fileName(for: item, displayName: displayName, fileExtension: fileExtension)
        return isExtra ? "\(extrasFolder)/\(name)" : name
    }

    /// Whether a relative path stays inside the folder it is relative to: not absolute, and no
    /// component that climbs.
    public static func isInside(_ relativePath: String) -> Bool {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else { return false }
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        return !components.contains("..") && !components.contains("")
    }
}
