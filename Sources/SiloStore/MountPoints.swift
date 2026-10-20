// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloKit

/// Where drives mount on this machine, as far as the silo can know without asking anything to mount:
/// the folders whose children are mount points by convention, and the mount points `/etc/fstab` and
/// the machine's systemd mount and automount units declare. A folder made in either place while its drive is away would be made on the disk
/// beneath, and the drive, when it comes back, would mount beside it or over it.
public struct MountPoints: Sendable {
    /// Folders each of whose children is where a drive mounts; `*` stands for any one component.
    public var holders: [String]
    /// A mount point some file on the machine declares, and the file that declares it.
    public struct Declared: Hashable, Sendable {
        public var path: String
        public var by: String

        public init(path: String, by: String) {
            self.path = path
            self.by = by
        }
    }

    /// The mount points the machine's fstab and systemd units declare.
    public var declared: [Declared]
    /// Whether something is mounted on a folder. Asked of the filesystem each time, as availability is.
    public var isMounted: @Sendable (String) -> Bool

    public init(
        holders: [String],
        declared: [Declared],
        isMounted: @escaping @Sendable (String) -> Bool = MountPoints.isMounted
    ) {
        self.holders = holders
        self.declared = declared
        self.isMounted = isMounted
    }

    /// The folders a platform mounts drives in: `/Volumes` on macOS; on Linux `/media` and the
    /// per-user folders within it and within `/run/media` that desktop automounters use, and `/mnt`.
    public static func holders(platform: StateDirectory.Platform) -> [String] {
        switch platform {
        case .macOS: ["/Volumes"]
        case .linux: ["/media", "/media/*", "/run/media/*", "/mnt"]
        }
    }

    /// The mount points an fstab declares: each entry's second field, with the `\040` fstab writes
    /// for a space read back, leaving out swap, which mounts nowhere.
    public static func declared(fstab: String, by file: String = "/etc/fstab") -> [Declared] {
        fstab.split(separator: "\n").compactMap { line in
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count >= 2, !fields[0].hasPrefix("#"), fields[1].hasPrefix("/") else { return nil }
            return Declared(path: String(fields[1]).replacingOccurrences(of: "\\040", with: " "), by: file)
        }
    }

    /// The mount point a systemd mount or automount unit declares: the `Where=` of its `[Mount]` or
    /// `[Automount]` section.
    public static func declared(unit: String, by file: String) -> Declared? {
        var section = ""
        for line in unit.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if line.hasPrefix("[") {
                section = line
            } else if section == "[Mount]" || section == "[Automount]", let equals = line.firstIndex(of: "="),
                line[..<equals].trimmingCharacters(in: .whitespaces) == "Where"
            {
                // systemd allows space either side of the `=`.
                let path = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
                return path.hasPrefix("/") ? Declared(path: path, by: file) : nil
            }
        }
        return nil
    }

    /// The folders systemd reads the machine's own units from, as against the units a distribution
    /// ships and may never enable.
    public static let unitFolders = ["/etc/systemd/system", "/run/systemd/system"]

    /// The mount points the mount and automount units in `folders` declare, and the ones enabled
    /// there through `.wants` and `.requires` links, wherever the unit they link to lives. A unit a
    /// distribution ships but nobody enabled is not read: `tmp.mount` declares `/tmp` on machines
    /// where nothing mounts there.
    public static func declared(units folders: [String]) -> [Declared] {
        let files = FileManager.default
        var found: [Declared] = []
        func read(_ path: String) {
            guard path.hasSuffix(".mount") || path.hasSuffix(".automount"),
                let text = try? String(contentsOfFile: path, encoding: .utf8),
                let declared = declared(unit: text, by: path),
                !found.contains(where: { $0.path == declared.path })
            else { return }
            found.append(declared)
        }
        for folder in folders {
            for name in ((try? files.contentsOfDirectory(atPath: folder)) ?? []).sorted() {
                let path = folder + "/" + name
                if name.hasSuffix(".wants") || name.hasSuffix(".requires") {
                    for linked in ((try? files.contentsOfDirectory(atPath: path)) ?? []).sorted() {
                        read(path + "/" + linked)
                    }
                } else {
                    read(path)
                }
            }
        }
        return found
    }

    /// This machine's.
    public static var system: MountPoints {
        let fstab = (try? String(contentsOfFile: "/etc/fstab", encoding: .utf8)) ?? ""
        return MountPoints(
            holders: holders(platform: .current),
            declared: declared(fstab: fstab) + declared(units: unitFolders)
        )
    }

    /// Whether a drive is mounted on `path`: its device is not its parent's. The top of the
    /// filesystem is always mounted.
    @Sendable public static func isMounted(_ path: String) -> Bool {
        let parent = (path as NSString).deletingLastPathComponent
        guard path != "/", parent != path else { return true }
        let device = { (path: String) in
            (try? FileManager.default.attributesOfItem(atPath: path))?[.systemNumber] as? Int
        }
        guard let own = device(path), let above = device(parent) else { return false }
        return own != above
    }

    /// Why folders may not be made starting in `parent`, the deepest folder of a path that exists, with
    /// `along` the folders above it that exist: nil when they may. Said of the path as "it", following
    /// the path it is about.
    public func reasonNotToMake(in parent: String, along existing: [String]) -> String? {
        let resolved = URL(fileURLWithPath: parent).resolvingSymlinksInPath().path
        if holders.contains(where: { Self.path(parent, matches: $0) || Self.path(resolved, matches: $0) }) {
            return "it would be created where drives are mounted"
        }
        for folder in existing {
            if let declared = declared.first(where: { $0.path == folder }), !isMounted(folder) {
                return
                    "it would be created in \(folder), which \(declared.by) declares as a mount point and has nothing mounted on it"
            }
        }
        return nil
    }

    /// Whether `path` is `pattern`, component by component, with `*` matching any one component.
    static func path(_ path: String, matches pattern: String) -> Bool {
        let names = path.split(separator: "/")
        let wanted = pattern.split(separator: "/")
        return names.count == wanted.count && zip(names, wanted).allSatisfy { $1 == "*" || $0 == $1 }
    }
}
