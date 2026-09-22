// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SmdKit
import SmdSidecar

/// What a placement is asked to do: put one file into a library as one presentation of one item.
public struct PlacementRequest: Sendable {
    public var library: URL
    /// The container the item is in and every container above it, root first. The lineage is
    /// what decides the folder; the last container is the one the item belongs to.
    public var lineage: [Container]
    public var item: String
    /// The presentation to record. Its `file` is ignored: the layout decides the name.
    public var presentation: Presentation
    /// The finished file, where it is now.
    public var source: URL
    public var fileExtension: String

    public init(library: URL, lineage: [Container], item: String, presentation: Presentation, source: URL, fileExtension: String? = nil) {
        self.library = library
        self.lineage = lineage
        self.item = item
        self.presentation = presentation
        self.source = source
        let ext = source.pathExtension
        self.fileExtension = fileExtension ?? (ext.isEmpty ? "mkv" : ext)
    }
}

/// A sidecar to write: the bytes, and whether the file is new.
public struct SidecarWrite: Hashable, Sendable {
    public var url: URL
    public var data: Data
    public var creates: Bool
}

/// The computed, auditable set of writes a placement makes. `Silo.md`, principle 5: shown before
/// it is applied, and refused whole when any finding is an error.
public struct Placement: Sendable {
    public var source: URL
    public var destination: URL
    /// Folders to create, parents first.
    public var folders: [URL]
    /// Sidecars to write, root first and the item's container last, so that a crash between two
    /// leaves a file nothing references rather than a reference to nothing.
    public var sidecars: [SidecarWrite]
    /// The presentation as it will be recorded, with the file the layout gave it.
    public var presentation: Presentation
    public var findings: [Finding]

    public var errors: [Finding] { findings.filter { $0.severity == .error } }
    public var isApplicable: Bool { errors.isEmpty }

    /// The declared write targets, one per line, relative to the library.
    public func describe(relativeTo library: URL) -> [String] {
        var lines: [String] = []
        for folder in folders { lines.append("create   \(LibraryWalker.relativePath(of: folder, in: library))/") }
        lines.append("place    \(source.path) -> \(LibraryWalker.relativePath(of: destination, in: library))")
        for write in sidecars {
            lines.append("\(write.creates ? "write   " : "update  ") \(LibraryWalker.relativePath(of: write.url, in: library))")
        }
        return lines
    }
}

public enum PlacementError: Error, LocalizedError {
    case emptyLineage
    case brokenLineage(parent: ContainerID, child: ContainerID)
    case unknownItem(String, in: ContainerID)
    case refused([Finding])

    public var errorDescription: String? {
        switch self {
        case .emptyLineage: "a placement needs at least the container the item is in"
        case .brokenLineage(let parent, let child): "\(parent) does not hold \(child)"
        case .unknownItem(let item, let container): "\(container) has no item \(item)"
        case .refused(let findings): "refused:\n" + findings.map { "  \($0)" }.joined(separator: "\n")
        }
    }
}

public enum Placer {
    /// Works out every write a placement would make, without making any.
    public static func compute(_ request: PlacementRequest) throws -> Placement {
        guard let target = request.lineage.last else { throw PlacementError.emptyLineage }
        for (parent, child) in zip(request.lineage, request.lineage.dropFirst()) {
            guard parent.childContainerIDs.contains(child.id) else {
                throw PlacementError.brokenLineage(parent: parent.id, child: child.id)
            }
        }
        let entries = target.sequences.flatMap(\.items).map { ($0, false) } + target.extras.map { ($0, true) }
        guard let (entry, isExtra) = entries.first(where: { $0.0.id == request.item }) else {
            throw PlacementError.unknownItem(request.item, in: target.id)
        }

        var findings: [Finding] = []
        var folders: [URL] = []
        var writes: [SidecarWrite] = []
        var folder = request.library
        var sidecars: [(container: Container, folder: URL, existing: Data?, sidecar: Sidecar)] = []

        for container in request.lineage {
            folder = folder.appendingPathComponent(LibraryLayout.folderName(for: container), isDirectory: true)
            let sidecarURL = folder.appendingPathComponent(LibraryLayout.sidecarFileName)
            var existing: Data?
            var sidecar = Sidecar(container: container)
            if FileManager.default.fileExists(atPath: sidecarURL.path) {
                do {
                    let data = try Data(contentsOf: sidecarURL)
                    let found = try SidecarFile.sidecar(from: data)
                    if found.container.id != container.id {
                        findings.append(Finding(.error, path: LibraryWalker.relativePath(of: sidecarURL, in: request.library), "the folder for \(container.displayTitle) already holds \(found.container.id)"))
                    }
                    // The container as the repository has it, with the library's facts as the
                    // sidecar on disk has them: an update never rewrites the container's fields,
                    // but the value carried through the placement is the current one.
                    sidecar = Sidecar(container: container, children: found.children, presentations: found.presentations)
                    existing = data
                } catch {
                    findings.append(Finding(.error, path: LibraryWalker.relativePath(of: sidecarURL, in: request.library), "unreadable: \(error.localizedDescription)"))
                }
            } else if !FileManager.default.fileExists(atPath: folder.path) {
                folders.append(folder)
            }
            sidecars.append((container, folder, existing, sidecar))
        }

        // Ancestors learn where their child is, and are written only when that is news.
        for index in sidecars.indices.dropLast() {
            let child = sidecars[index + 1].container
            let path = LibraryLayout.childPath(for: child)
            if sidecars[index].sidecar.children[child.id] != path {
                sidecars[index].sidecar.children[child.id] = path
                writes.append(try write(sidecars[index]))
            }
        }

        // The item's container gets the presentation.
        var last = sidecars[sidecars.count - 1]
        var presentation = request.presentation
        let displayName = last.sidecar.displayName(of: presentation)
        presentation.file = LibraryLayout.relativePath(for: entry, isExtra: isExtra, displayName: displayName, fileExtension: request.fileExtension)
        let destination = last.folder.appendingPathComponent(presentation.file)
        if let alternative = presentation.alternative, !target.alternatives.contains(where: { $0.id == alternative }) {
            findings.append(Finding(.error, "\(target.displayTitle) has no alternative \(alternative)"))
        }
        for track in presentation.tracks where !target.features.contains(where: { $0.id == track.feature }) {
            findings.append(Finding(.error, "\(target.displayTitle) has no feature \(track.feature)"))
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            findings.append(Finding(.error, path: LibraryWalker.relativePath(of: destination, in: request.library), "already exists; nothing is overwritten"))
        }
        if !FileManager.default.fileExists(atPath: request.source.path) {
            findings.append(Finding(.error, "the source \(request.source.path) is not there"))
        }
        if isExtra {
            let extras = last.folder.appendingPathComponent(LibraryLayout.extrasFolder, isDirectory: true)
            if !FileManager.default.fileExists(atPath: extras.path) { folders.append(extras) }
        }
        last.sidecar.presentations[request.item, default: []].append(presentation)
        findings += Validator.check(last.sidecar).filter { $0.severity == .error }
        sidecars[sidecars.count - 1] = last
        writes.append(try write(last))

        return Placement(source: request.source, destination: destination, folders: folders, sidecars: writes, presentation: presentation, findings: findings)
    }

    private static func write(_ entry: (container: Container, folder: URL, existing: Data?, sidecar: Sidecar)) throws -> SidecarWrite {
        let url = entry.folder.appendingPathComponent(LibraryLayout.sidecarFileName)
        if let existing = entry.existing {
            return SidecarWrite(url: url, data: try SidecarFile.data(for: entry.sidecar, updating: existing), creates: false)
        }
        return SidecarWrite(url: url, data: try SidecarFile.data(for: entry.sidecar), creates: true)
    }

    /// Makes the writes, in the order the placement lists them: folders, then the file, then the
    /// sidecars root first. Refused whole when the placement has an error.
    public static func apply(_ placement: Placement, move: Bool = true) throws {
        guard placement.isApplicable else { throw PlacementError.refused(placement.errors) }
        for folder in placement.folders {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        if move {
            try FileManager.default.moveItem(at: placement.source, to: placement.destination)
        } else {
            try FileManager.default.copyItem(at: placement.source, to: placement.destination)
        }
        for write in placement.sidecars {
            try write.data.write(to: write.url, options: .atomic)
        }
    }
}
