// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation

// MARK: - Containers

extension SiloClient {
    /// A container as a summary: what a library's list of its containers, and a container's children,
    /// say of each.
    public struct ContainerSummary: Hashable, Sendable, Codable, Identifiable {
        public var id: String
        public var library: String
        public var type: String
        public var title: String
        public var displayTitle: String
        public var year: Int?
        public var typeLabel: String?
        public var outline: String?
        public var listed: Bool
        public var parent: String?
    }

    /// A container as a library's sidecar says it, with that library's presentations of each item.
    public struct Container: Hashable, Sendable, Codable, Identifiable {
        public struct Alternative: Hashable, Sendable, Codable {
            public var id: String
            public var sequence: String
            public var title: String?
            public var outline: String?
        }

        public struct Participant: Hashable, Sendable, Codable {
            public var name: String
            public var role: String?
        }

        public struct Feature: Hashable, Sendable, Codable {
            public var id: String
            public var type: String
            public var title: String?
            public var participants: [Participant]
        }

        public struct ExternalRef: Hashable, Sendable, Codable {
            public var provider: String
            public var value: String
        }

        /// One presentation of an item in the library: the name it is shown under, its profile and
        /// alternative, and its file beside the sidecar.
        public struct Presentation: Hashable, Sendable, Codable, Identifiable {
            public var id: String
            public var alternative: String?
            public var profile: String?
            public var displayName: String?
            public var file: String
        }

        public struct Item: Hashable, Sendable, Codable {
            public var id: String?
            public var type: String?
            public var title: String?
            public var outline: String?
            public var optional: Bool
            /// The child container the item is, when it is one.
            public var container: String?
            public var externalRefs: [ExternalRef]
            public var presentations: [Presentation]
        }

        public struct Sequence: Hashable, Sendable, Codable {
            public var id: String?
            public var exploded: String
            public var items: [Item]
        }

        public var id: String
        public var library: String
        public var type: String
        public var title: String
        public var displayTitle: String
        public var year: Int?
        public var typeLabel: String?
        public var outline: String?
        public var listed: Bool
        public var parent: String?
        public var defaultAlternative: String?
        public var alternatives: [Alternative]
        public var features: [Feature]
        public var sequences: [Sequence]
        public var extrasAnchor: String?
        public var extras: [Item]
        public var children: [ContainerSummary]
        public var externalRefs: [ExternalRef]
    }

    /// A container in one library: the library, its sidecar's path in it, the digest an edit names as
    /// its base, the artwork kinds its folder holds, and the container as the sidecar says it.
    public struct LibraryContainer: Hashable, Sendable, Codable {
        public var library: String
        public var path: String
        public var digest: String
        public var artwork: [String]
        public var container: Container
    }

    /// What an edit wrote, or would write: the sidecar's bytes as text, their digest, and what the
    /// silo found in them.
    public struct ContainerEditResult: Hashable, Sendable, Codable {
        public var applied: Bool
        public var sidecar: String
        public var digest: String
        public var findings: [LastWalk.Finding]
        /// The folders the edit moved, or would move; none from a silo that moves none.
        public var moves: [FolderMove]

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            applied = try container.decode(Bool.self, forKey: .applied)
            sidecar = try container.decode(String.self, forKey: .sidecar)
            digest = try container.decode(String.self, forKey: .digest)
            findings = try container.decode([LastWalk.Finding].self, forKey: .findings)
            moves = try container.decodeIfPresent([FolderMove].self, forKey: .moves) ?? []
        }
    }

    /// A folder renamed, or to be renamed, by its path in the library before and after.
    public struct FolderMove: Hashable, Sendable, Codable {
        public var from: String
        public var to: String

        public init(from: String, to: String) {
            self.from = from
            self.to = to
        }
    }

    /// What laying a library out again did, or would do: the moves, and any rename that failed.
    public struct LayoutResult: Hashable, Sendable, Codable {
        public var applied: Bool
        public var moves: [FolderMove]
        public var findings: [LastWalk.Finding]
    }

    private struct LayoutRequest: Codable {
        var dryRun: Bool?
    }

    /// Renames every folder in the library not named as the layout names its container, or with
    /// `dryRun` answers the moves it would make and moves nothing.
    public func layOut(_ library: String, dryRun: Bool) async throws -> LayoutResult {
        try await send("POST", "/v1/libraries/\(library)/layout", body: LayoutRequest(dryRun: dryRun ? true : nil))
    }

    /// The artwork kinds a container's folder may hold, in the order the silo lists them.
    public static let artworkKinds = ["poster", "fanart", "banner", "logo", "thumb"]

    /// The containers at the top of a library, listed or not.
    public func containers(in library: String) async throws -> [ContainerSummary] {
        try await send("GET", "/v1/libraries/\(library)/containers")
    }

    public func container(_ id: String, in library: String) async throws -> LibraryContainer {
        try await send("GET", "/v1/libraries/\(library)/containers/\(id)")
    }

    /// The library's sidecar for a container, as its bytes.
    public func sidecar(of id: String, in library: String) async throws -> Data {
        let (data, status) = try await request(
            "GET",
            "/v1/libraries/\(library)/containers/\(id)/smd",
            data: nil,
            contentType: nil
        )
        guard (200..<300).contains(status) else {
            throw SiloClientError.status(status, String(decoding: data, as: UTF8.self))
        }
        return data
    }

    private struct ContainerEdit: Codable {
        var document: String
        var basedOn: String
        var dryRun: Bool?
    }

    /// Sets a container's own fields in a library's sidecar from its repository document, onto the
    /// sidecar whose digest is `basedOn`. Refused with `status(409, _)`, naming the digest the library
    /// holds, when that is no longer it, and with `status(422, _)` carrying the result and its findings
    /// when they refuse it. Operator only.
    public func edit(
        container id: String,
        in library: String,
        document: String,
        basedOn: String,
        dryRun: Bool = false
    ) async throws -> ContainerEditResult {
        try await send(
            "PUT",
            "/v1/libraries/\(library)/containers/\(id)",
            body: ContainerEdit(document: document, basedOn: basedOn, dryRun: dryRun ? true : nil)
        )
    }

    /// Where a kind of a container's artwork is served, openly.
    public func artworkURL(_ kind: String, of id: String, in library: String) -> URL {
        URL(string: "/v1/libraries/\(library)/containers/\(id)/artwork/\(kind)", relativeTo: baseURL)!.absoluteURL
    }

    /// What the silo answered a put of artwork with.
    public struct ArtworkPut: Hashable, Sendable, Codable {
        public var kind: String
        public var format: String
    }

    /// Puts an image as a kind of a container's artwork. Refused with `status(415, _)` for anything
    /// not a JPEG or a PNG by its bytes, and `status(413, _)` for an image over 25 MB. Operator only.
    public func putArtwork(_ image: Data, as kind: String, of id: String, in library: String) async throws -> ArtworkPut
    {
        let (data, status) = try await request(
            "PUT",
            "/v1/libraries/\(library)/containers/\(id)/artwork/\(kind)",
            data: image,
            contentType: "application/octet-stream"
        )
        guard (200..<300).contains(status) else {
            throw SiloClientError.status(status, String(decoding: data, as: UTF8.self))
        }
        return try Self.decoder.decode(ArtworkPut.self, from: data)
    }

    /// Removes a kind of a container's artwork. Operator only.
    public func removeArtwork(_ kind: String, of id: String, in library: String) async throws {
        let (data, status) = try await request(
            "DELETE",
            "/v1/libraries/\(library)/containers/\(id)/artwork/\(kind)",
            data: nil,
            contentType: nil
        )
        guard (200..<300).contains(status) else {
            throw SiloClientError.status(status, String(decoding: data, as: UTF8.self))
        }
    }
}
