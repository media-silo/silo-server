// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension SiloClient {
    /// A store's creation, as the create route takes it.
    public struct StoreCreate: Hashable, Sendable, Codable {
        public var documents: [String]
        public var parent: String?
        public var attributions: [CreateAttribution]?

        public init(documents: [String], parent: String?, attributions: [CreateAttribution]?) {
            self.documents = documents
            self.parent = parent
            self.attributions = attributions
        }
    }

    /// A store's edit, as the edit route takes it; an empty base for a container an earlier step of the
    /// store makes, which the silo makes on what that step made.
    public struct StoreEdit: Hashable, Sendable, Codable {
        public var container: String
        public var document: String
        public var basedOn: String
        public var attributions: [Container.Attribution]?
        public var declined: [Container.ExternalRef]?

        public init(
            container: String,
            document: String,
            basedOn: String,
            attributions: [Container.Attribution]?,
            declined: [Container.ExternalRef]?
        ) {
            self.container = container
            self.document = document
            self.basedOn = basedOn
            self.attributions = attributions
            self.declined = declined
        }
    }

    /// A store's put or removal of an artwork kind, as the artwork route takes it.
    public struct StoreArtwork: Hashable, Sendable, Codable {
        public var container: String
        public var kind: String
        /// The digest of the blob put; absent in a removal.
        public var image: String?
        public var provider: String?
        public var value: String?
        public var read: String?

        public init(container: String, kind: String, image: String? = nil, attribution: ArtworkAttribution? = nil) {
            self.container = container
            self.kind = kind
            self.image = image
            provider = attribution?.provider
            value = attribution?.value
            read = attribution?.read
        }
    }

    /// One step of a store: exactly one of a creation, an edit, a put of artwork from a blob, or a
    /// removal of artwork, each in the terms of the route that makes it alone.
    public struct StoreStep: Hashable, Sendable, Codable {
        public var create: StoreCreate?
        public var edit: StoreEdit?
        public var putArtwork: StoreArtwork?
        public var removeArtwork: StoreArtwork?

        public static func create(_ create: StoreCreate) -> StoreStep { StoreStep(create: create) }
        public static func edit(_ edit: StoreEdit) -> StoreStep { StoreStep(edit: edit) }
        public static func putArtwork(_ artwork: StoreArtwork) -> StoreStep { StoreStep(putArtwork: artwork) }
        public static func removeArtwork(_ artwork: StoreArtwork) -> StoreStep { StoreStep(removeArtwork: artwork) }
    }

    public enum StoreState: String, Hashable, Sendable, Codable {
        case underWay
        case made
        case refused
    }

    /// A store as the silo says it: under way, made or refused; how many of its steps are made; the
    /// step under way or refused, by its index; and a refusal's reason and findings.
    public struct StoreRecord: Hashable, Sendable, Codable {
        public var key: String
        public var state: StoreState
        public var made: Int
        public var steps: Int
        public var step: Int?
        public var reason: String?
        public var findings: [LastWalk.Finding]?
    }

    private struct StoreRequest: Encodable {
        var key: String
        var steps: [StoreStep]
    }

    /// Hands the silo a store of steps to make in a library under a key: taken at once, or, for a key
    /// the library has a store of the same steps for, that store. Refused with `status(409, _)` for a
    /// key that names a store of other steps. Operator only.
    public func createStore(_ steps: [StoreStep], key: String, in library: String) async throws -> StoreRecord {
        try await send("POST", "/v1/libraries/\(library)/stores", body: StoreRequest(key: key, steps: steps))
    }

    /// A library's store under a key, as far as it has got; `status(404, _)` when the library has none.
    /// Operator only.
    public func store(_ key: String, in library: String) async throws -> StoreRecord {
        try await send("GET", "/v1/libraries/\(library)/stores/\(key)")
    }

    /// Whether the silo holds the image a store would put, by its digest. Operator only.
    public func holdsBlob(_ digest: String) async throws -> Bool {
        let (data, status) = try await request("GET", "/v1/blobs/\(digest)", data: nil, contentType: nil)
        switch status {
        case 200: return true
        case 404: return false
        default: throw SiloClientError.status(status, String(bytes: data, encoding: .utf8) ?? "")
        }
    }

    /// Holds an image a store will put under its digest, the SHA-256 of its bytes. Refused with
    /// `status(400, _)` when the bytes are not the digest's, `status(415, _)` for anything not a JPEG or
    /// a PNG, and `status(413, _)` for an image over 25 MB. Operator only.
    public func putBlob(_ image: Data, digest: String) async throws {
        let (data, status) = try await request(
            "PUT",
            "/v1/blobs/\(digest)",
            data: image,
            contentType: "application/octet-stream"
        )
        guard (200..<300).contains(status) else {
            throw SiloClientError.status(status, String(bytes: data, encoding: .utf8) ?? "")
        }
    }
}
