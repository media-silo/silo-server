// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SmdKit
import SmdSidecar

/// Where things go in a library. `Silo.md`, *Layout*: every container has a folder named from
/// its display title, nested as the tree nests, with `container.smd` inside; a presentation is
/// `{item} - {display name}.mkv` beside it, or under `extras/` for an extra; a path in a sidecar
/// is relative to the folder holding it and never leaves the container's folder.
public enum LibraryLayout {
    public static let sidecarFileName = SidecarFile.fileName
    public static let extrasFolder = "extras"

    /// A title as a folder or file name: the two characters no filesystem here allows in a name
    /// replaced, whitespace collapsed, and nothing that would hide the entry or walk out of the
    /// folder. Empty after all that, the caller falls back to an id.
    public static func sanitise(_ name: String) -> String {
        var text = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\0", with: "")
        text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        while text.hasPrefix(".") { text.removeFirst() }
        return text.trimmingCharacters(in: .whitespaces)
    }

    public static func folderName(for container: Container) -> String {
        let name = sanitise(container.displayTitle)
        return name.isEmpty ? container.id.rawValue : name
    }

    /// The `smd` path a parent's sidecar records for a child: the child's folder, inside the
    /// parent's, and the sidecar in it.
    public static func childPath(for child: Container) -> String {
        "\(folderName(for: child))/\(sidecarFileName)"
    }

    /// `{item} - {display name}.ext`, or `{item}.ext` for the unqualified presentation of the
    /// default alternative. The item is its title, or its id when it has none.
    public static func fileName(for item: Entry, displayName: String?, fileExtension: String) -> String {
        var stem = sanitise(item.title ?? "")
        if stem.isEmpty { stem = item.id ?? "item" }
        if let displayName, !sanitise(displayName).isEmpty {
            stem += " - \(sanitise(displayName))"
        }
        return "\(stem).\(fileExtension)"
    }

    /// The path a sidecar records for a presentation of an item, relative to the sidecar's folder.
    public static func relativePath(for item: Entry, isExtra: Bool, displayName: String?, fileExtension: String) -> String {
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
