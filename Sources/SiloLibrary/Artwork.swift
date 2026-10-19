// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation

/// A container's artwork: images beside its `container.smd`, found by name, which the sidecar lists
/// none of. They are the names a media server already looks for in a folder, and the library already
/// gives every container a folder of its own. `Containers.md`, *Artwork*.
public enum Artwork {
    /// The kinds, in the order they are listed.
    public static let kinds = ["poster", "fanart", "banner", "logo", "thumb"]
    /// The largest image the silo takes.
    public static let maximumSize = 25 * 1024 * 1024

    public enum Format: String, Hashable, Sendable, CaseIterable {
        case jpg, png

        public var contentType: String {
            switch self {
            case .jpg: "image/jpeg"
            case .png: "image/png"
            }
        }

        /// The format an image's bytes are, told by their signature rather than by anything said of
        /// them; nil for anything else.
        public init?(signatureOf data: Data) {
            if data.starts(with: [0xFF, 0xD8, 0xFF]) {
                self = .jpg
            } else if data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
                self = .png
            } else {
                return nil
            }
        }
    }

    /// The file a kind is in the folder, as `<kind>.jpg` or `<kind>.png`; the `.jpg` when it is both.
    /// Asked of the folder each time, since a changed image changes no sidecar.
    public static func file(of kind: String, in folder: URL) -> (url: URL, format: Format)? {
        for format in Format.allCases {
            let url = folder.appendingPathComponent("\(kind).\(format.rawValue)")
            if FileManager.default.fileExists(atPath: url.path) { return (url, format) }
        }
        return nil
    }

    /// The kinds the folder holds, in the order they are listed.
    public static func held(in folder: URL) -> [String] {
        kinds.filter { file(of: $0, in: folder) != nil }
    }

    /// A warning, on the sidecar, for each kind the folder holds in both formats.
    public static func findings(in folder: URL, sidecar: String) -> [Finding] {
        kinds.compactMap { kind in
            let both = Format.allCases.allSatisfy { FileManager.default.fileExists(atPath: folder.appendingPathComponent("\(kind).\($0.rawValue)").path) }
            return both ? Finding(.warning, path: sidecar, "\(kind) is both \(kind).jpg and \(kind).png") : nil
        }
    }
}
