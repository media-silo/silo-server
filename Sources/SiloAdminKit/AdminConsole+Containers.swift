// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloClient

// MARK: - Containers

extension AdminConsole {
    /// A library's container as the console shows it: as the library's sidecar says it, the sidecar's
    /// bytes, and what the library's last walk reported on that sidecar, in the walk's words.
    public struct OpenedContainer: Hashable, Sendable {
        public var container: SiloClient.LibraryContainer
        public var sidecar: Data
        public var findings: [SiloClient.LastWalk.Finding]
    }

    /// The containers at the top of a library, listed or not.
    public func containers(in library: String, of silo: Silo) async throws -> [SiloClient.ContainerSummary] {
        try await withOperator(silo) { try await $0.containers(in: library) }
    }

    /// A container in a library, with its sidecar and the last walk's findings on it. The findings are
    /// the walk's, matched by the sidecar's path; the console adds no reading of its own.
    public func open(container id: String, in library: String, of silo: Silo) async throws -> OpenedContainer {
        try await withOperator(silo) { client in
            let container = try await client.container(id, in: library)
            let sidecar = try await client.sidecar(of: id, in: library)
            let walk = try? await client.lastWalk(of: library)
            return OpenedContainer(
                container: container,
                sidecar: sidecar,
                findings: (walk?.report.findings ?? []).filter { $0.path == container.path }
            )
        }
    }

    /// What the silo made of a container draft, asked as a dry run: what it would write and its
    /// findings, refused or not; that the sidecar has moved on since the draft's base; or why the
    /// document could not be read, in the silo's words.
    public enum ContainerCheck: Hashable, Sendable {
        case wouldWrite(SiloClient.ContainerEditResult)
        case refused(SiloClient.ContainerEditResult)
        case behind(String)
        case unreadable(String)
    }

    /// Checks a container draft with the silo as a store would, storing nothing.
    public func check(_ draft: ContainerDraft, of silo: Silo) async throws -> ContainerCheck {
        do {
            return .wouldWrite(
                try await withOperator(silo) {
                    try await $0.edit(
                        container: draft.container,
                        in: draft.library,
                        document: draft.text,
                        basedOn: draft.base,
                        dryRun: true
                    )
                }
            )
        } catch SiloClientError.status(422, let body) {
            guard
                let result = try? SiloClient.decoder.decode(SiloClient.ContainerEditResult.self, from: Data(body.utf8))
            else { return .unreadable(Self.detail(body)) }
            return .refused(result)
        } catch SiloClientError.status(409, let body) {
            return .behind(Self.detail(body))
        } catch SiloClientError.status(400, let body) {
            return .unreadable(Self.detail(body))
        }
    }

    /// How a container store ended: the sidecar the silo wrote, which ends the draft; the findings
    /// that refused it, which keep it; or the sidecar that landed first, which keeps it for the
    /// operator to re-base or discard. The console never merges.
    public enum ContainerStoreOutcome: Hashable, Sendable {
        case stored(SiloClient.ContainerEditResult)
        case refused(SiloClient.ContainerEditResult)
        case landedFirst(OpenedContainer)
    }

    /// Stores a container draft onto the sidecar it was based on. A document the silo cannot read is
    /// `StoreRefused`, in its words.
    public func store(_ draft: ContainerDraft, of silo: Silo) async throws -> ContainerStoreOutcome {
        do {
            return .stored(
                try await withOperator(silo) {
                    try await $0.edit(
                        container: draft.container,
                        in: draft.library,
                        document: draft.text,
                        basedOn: draft.base
                    )
                }
            )
        } catch SiloClientError.status(422, let body) {
            guard
                let result = try? SiloClient.decoder.decode(SiloClient.ContainerEditResult.self, from: Data(body.utf8))
            else { throw StoreRefused(reason: Self.detail(body)) }
            return .refused(result)
        } catch SiloClientError.status(409, _) {
            return .landedFirst(try await open(container: draft.container, in: draft.library, of: silo))
        } catch SiloClientError.status(let status, let body) where status == 400 || status == 404 {
            throw StoreRefused(
                reason: Self.detail(body).isEmpty ? "the library no longer holds the container" : Self.detail(body)
            )
        }
    }

    /// Where a kind of a container's artwork is served; the silo serves it to anyone who asks.
    public nonisolated func artworkURL(_ kind: String, of container: String, in library: String, of silo: Silo) -> URL {
        SiloClient(baseURL: silo.url).artworkURL(kind, of: container, in: library)
    }

    /// Puts an image as a kind of a container's artwork. The silo's refusal — not a JPEG or a PNG,
    /// or too large — comes back as `SettingsRefused` in words.
    public func putArtwork(
        _ image: Data,
        as kind: String,
        of container: String,
        in library: String,
        on silo: Silo
    ) async throws {
        do {
            _ = try await withOperator(silo) { try await $0.putArtwork(image, as: kind, of: container, in: library) }
        } catch SiloClientError.status(415, _) {
            throw SettingsRefused(reason: "the silo takes artwork as a JPEG or a PNG, and this is neither")
        } catch SiloClientError.status(413, _) {
            throw SettingsRefused(reason: "the silo takes artwork up to 25 MB, and this is larger")
        } catch SiloClientError.status(404, _) {
            throw SettingsRefused(reason: "the library no longer holds the container")
        }
    }

    /// Removes a kind of a container's artwork.
    public func removeArtwork(_ kind: String, of container: String, in library: String, on silo: Silo) async throws {
        do {
            try await withOperator(silo) { try await $0.removeArtwork(kind, of: container, in: library) }
        } catch SiloClientError.status(404, _) {
            throw SettingsRefused(reason: "the container has no \(kind)")
        }
    }
}
