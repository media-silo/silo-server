// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SmdKit
import SmdSidecar

/// What making a tree of containers in a library is asked to do: file each one as a placement
/// would, beneath the container that holds the top or at the top of the library, and place nothing.
/// `Smddb.md`, *What the silo adds*.
public struct MakingRequest: Sendable {
    /// The container that is to hold the top of the tree: its folder, and the container above it,
    /// nil for one at the top of the library, so the index can re-read its sidecar under its parent.
    public struct Holder: Sendable {
        public var folder: URL
        public var parent: ContainerID?

        public init(folder: URL, parent: ContainerID?) {
            self.folder = folder
            self.parent = parent
        }
    }

    public var library: URL
    /// Nil for a tree filed at the top of the library.
    public var holder: Holder?
    /// The tree, in any order: one container named as a child by none of the others, and every
    /// other named as a child by one of them.
    public var containers: [Container]
    /// The attributions of each container's own fields, by the container's id, written into its new
    /// sidecar so that it is never in the library with an outline that does not say whose it is.
    public var attributions: [ContainerID: [Attribution]]

    public init(
        library: URL,
        holder: Holder?,
        containers: [Container],
        attributions: [ContainerID: [Attribution]] = [:]
    ) {
        self.library = library
        self.holder = holder
        self.containers = containers
        self.attributions = attributions
    }
}

/// The computed set of writes making a tree would make: shown before it is applied, and refused whole
/// when any finding is an error, as a placement is.
public struct Making: Sendable {
    /// Folders to create, parents first.
    public var folders: [URL]
    /// The new sidecars from the top of the tree down, then the holder's, so that an interrupted apply
    /// leaves a sidecar nothing references rather than a reference to one that is not there.
    public var sidecars: [SidecarWrite]
    public var findings: [Finding]

    public var errors: [Finding] { findings.filter { $0.severity == .error } }
    public var isApplicable: Bool { errors.isEmpty }

    /// The declared write targets, one per line, relative to the library, in a placement's words.
    public func describe(relativeTo library: URL) -> [String] {
        folders.map { "create   \(LibraryWalker.relativePath(of: $0, in: library))/" }
            + sidecars.map {
                "\($0.creates ? "write   " : "update  ") \(LibraryWalker.relativePath(of: $0.url, in: library))"
            }
    }
}

public enum MakingError: Error, Equatable, LocalizedError {
    case empty
    /// The containers do not form one tree, and why.
    case notATree(String)
    case refused([Finding])

    public var errorDescription: String? {
        switch self {
        case .empty: "there is nothing to make"
        case .notATree(let reason): "the containers are not one tree: \(reason)"
        case .refused(let findings): "refused:\n" + findings.map { "  \($0)" }.joined(separator: "\n")
        }
    }
}

public enum Maker {
    /// Works out every write making the tree would make, without making any.
    public static func compute(_ request: MakingRequest) throws -> Making {
        let tree = try Tree(request.containers)
        var findings: [Finding] = []
        var folders: [URL] = []
        var writes: [SidecarWrite] = []
        var folderOf: [ContainerID: URL] = [:]

        let holder = try request.holder.map { try reading($0, top: tree.top, in: request.library) }
        findings += holder?.findings ?? []
        let base = request.holder?.folder ?? request.library

        for container in tree.order {
            let parent = tree.parents[container.id]
            let name =
                if let parent, let parentContainer = request.containers.first(where: { $0.id == parent }) {
                    LibraryLayout.folderName(for: container, in: parentContainer)
                } else if let holder {
                    holder.folder ?? LibraryLayout.folderName(for: container)
                } else {
                    LibraryLayout.folderName(for: container)
                }
            let folder = (parent.flatMap { folderOf[$0] } ?? base).appendingPathComponent(name, isDirectory: true)
            folderOf[container.id] = folder
            let url = folder.appendingPathComponent(LibraryLayout.sidecarFileName)
            let path = LibraryWalker.relativePath(of: url, in: request.library)
            if FileManager.default.fileExists(atPath: url.path) {
                findings.append(occupied(folder, by: container, in: request.library))
            } else if !FileManager.default.fileExists(atPath: folder.path) {
                folders.append(folder)
            }

            var sidecar = Sidecar(container: container, attributions: request.attributions[container.id] ?? [])
            for child in container.childContainerIDs {
                guard let made = request.containers.first(where: { $0.id == child }) else { continue }
                sidecar.children[child] = LibraryLayout.childPath(for: made, in: container)
            }
            findings += Validator.check(sidecar).filter { $0.severity == .error }.map {
                var located = $0
                located.path = path
                return located
            }
            writes.append(
                SidecarWrite(
                    url: url,
                    data: try SidecarFile.data(for: sidecar),
                    creates: true,
                    parent: parent ?? holder?.id
                )
            )
        }
        if let write = holder?.write { writes.append(write) }
        return Making(folders: folders, sidecars: writes, findings: findings)
    }

    /// The holder's sidecar as the tree would leave it: its id, the update that records the top's
    /// path when that is news, and its refusal when it does not name the top or cannot be read.
    private struct HolderReading {
        var id: ContainerID?
        /// The top's folder within the holder's: where the holder records it, or else numbered among
        /// the holder's children.
        var folder: String?
        var write: SidecarWrite?
        var findings: [Finding] = []
    }

    private static func reading(_ holder: MakingRequest.Holder, top: Container, in library: URL) throws -> HolderReading
    {
        let url = holder.folder.appendingPathComponent(LibraryLayout.sidecarFileName)
        let path = LibraryWalker.relativePath(of: url, in: library)
        var reading = HolderReading()
        let existing: Data
        var sidecar: Sidecar
        do {
            existing = try Data(contentsOf: url)
            sidecar = try SidecarFile.sidecar(from: existing)
        } catch {
            reading.findings.append(Finding(.error, path: path, "unreadable: \(error.localizedDescription)"))
            return reading
        }
        reading.id = sidecar.container.id
        if !sidecar.container.childContainerIDs.contains(top.id) {
            reading.findings.append(
                Finding(.error, path: path, "\(sidecar.container.id) does not name \(top.id) as a child")
            )
        }
        let folder =
            LibraryLayout.recordedFolder(of: top.id, in: sidecar)
            ?? LibraryLayout.folderName(for: top, in: sidecar.container)
        reading.folder = folder
        let childPath = LibraryLayout.childPath(folder: folder)
        if sidecar.children[top.id] != childPath {
            sidecar.children[top.id] = childPath
            reading.write = SidecarWrite(
                url: url,
                data: try SidecarFile.data(for: sidecar, updating: existing),
                creates: false,
                parent: holder.parent
            )
        }
        return reading
    }

    /// Why a folder that already holds a sidecar cannot take the container: it is there already, or
    /// another container is, or what is there cannot be read.
    private static func occupied(_ folder: URL, by container: Container, in library: URL) -> Finding {
        let url = folder.appendingPathComponent(LibraryLayout.sidecarFileName)
        let path = LibraryWalker.relativePath(of: url, in: library)
        guard let held = try? SidecarFile.sidecar(from: Data(contentsOf: url)).container.id else {
            return Finding(.error, path: path, "unreadable: the folder for \(container.displayTitle) holds a sidecar")
        }
        if held == container.id {
            let relativeFolder = LibraryWalker.relativePath(of: folder, in: library)
            return Finding(.error, path: path, "container \(container.id) is already at \"\(relativeFolder)\"")
        }
        return Finding(.error, path: path, "the folder for \(container.displayTitle) already holds \(held)")
    }

    /// Makes the writes in the order the computation lists them: folders, then the sidecars. Refused
    /// whole, touching nothing, when the computation has an error.
    public static func apply(_ making: Making) throws {
        guard making.isApplicable else { throw MakingError.refused(making.errors) }
        for folder in making.folders {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        for write in making.sidecars {
            try write.data.write(to: write.url, options: .atomic)
        }
    }

    /// The top of the tree, every container from the top down with each parent before its children,
    /// and each container's parent within the tree. Thrown when the containers are not one tree.
    private struct Tree {
        var top: Container
        var order: [Container] = []
        var parents: [ContainerID: ContainerID] = [:]

        init(_ containers: [Container]) throws {
            guard !containers.isEmpty else { throw MakingError.empty }
            var byID: [ContainerID: Container] = [:]
            for container in containers {
                guard byID[container.id] == nil else { throw MakingError.notATree("\(container.id) is given twice") }
                byID[container.id] = container
            }
            var parents: [ContainerID: ContainerID] = [:]
            for container in containers {
                for child in container.childContainerIDs where byID[child] != nil {
                    if let other = parents[child], other != container.id {
                        throw MakingError.notATree("\(child) is named as a child by \(other) and by \(container.id)")
                    }
                    parents[child] = container.id
                }
            }
            let tops = containers.filter { parents[$0.id] == nil }
            guard tops.count == 1, let top = tops.first else {
                throw MakingError.notATree(
                    tops.isEmpty
                        ? "every container is named as a child by another"
                        : "\(tops.map(\.id.value).joined(separator: ", ")) are each named as a child by none of the others"
                )
            }
            var order: [Container] = []
            var queue = [top]
            while !queue.isEmpty {
                let container = queue.removeFirst()
                order.append(container)
                queue += container.childContainerIDs.compactMap { byID[$0] }.filter { parents[$0.id] == container.id }
            }
            guard order.count == containers.count else {
                let unreached = containers.filter { candidate in !order.contains { $0.id == candidate.id } }
                throw MakingError.notATree(
                    "\(unreached.map(\.id.value).joined(separator: ", ")) cannot be reached from \(top.id)"
                )
            }
            self.top = top
            self.order = order
            self.parents = parents
        }
    }
}
