// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloClient

// MARK: - Libraries

extension AdminConsole {
    /// The libraries a with-access silo lists, each with its standard.
    public func libraries(of silo: Silo) async throws -> [SiloClient.Library] {
        try await withOperator(silo) { try await $0.libraries() }
    }

    /// Names a library's standard, or clears it with nil; the library as the silo answers.
    public func setStandard(_ ruleset: String?, of library: String, on silo: Silo) async throws -> SiloClient.Library {
        do {
            return try await withOperator(silo) { try await $0.setStandard(ruleset, of: library) }
        } catch SiloClientError.status(let status, let body) where status == 400 || status == 404 {
            throw SettingsRefused(reason: Self.detail(body).isEmpty ? "no ruleset \(ruleset ?? "")" : Self.detail(body))
        }
    }

    /// Each library's last walk, by its id, for the libraries a with-access silo lists. A library
    /// whose walk cannot be read is left out.
    public func lastWalks(of silo: Silo) async throws -> [String: SiloClient.LastWalk] {
        try await withOperator(silo) { client in
            var walks: [String: SiloClient.LastWalk] = [:]
            for library in try await client.libraries() {
                walks[library.id] = try? await client.lastWalk(of: library.id)
            }
            return walks
        }
    }

    /// Adds a library at `path` on the silo's machine, making its missing folders with `create`; the
    /// library as the silo answers, walked. The silo's refusal — outside its roots, a taken id, a
    /// folder that is not there — comes back as `SettingsRefused` in its own words.
    public func addLibrary(
        id: String,
        path: String,
        create: Bool = false,
        on silo: Silo
    ) async throws -> SiloClient.Library {
        do {
            return try await withOperator(silo) { try await $0.addLibrary(id: id, path: path, create: create) }
        } catch SiloClientError.status(let status, let body) where [400, 403, 409, 422].contains(status) {
            throw SettingsRefused(reason: Self.detail(body))
        }
    }

    /// What adding a library at `path` would find on the silo's machine, and the refusal it would
    /// meet; nothing is added or made.
    public func checkLibrary(
        id: String,
        path: String,
        create: Bool,
        on silo: Silo
    ) async throws -> SiloClient.LibraryCheck {
        try await withOperator(silo) { try await $0.checkLibrary(id: id, path: path, create: create) }
    }

    /// Removes a library, leaving its files on the silo's machine. A refusal — a live job filing into
    /// it — comes back as `SettingsRefused`, naming the job.
    public func removeLibrary(_ library: String, on silo: Silo) async throws {
        do {
            try await withOperator(silo) { try await $0.removeLibrary(library) }
        } catch SiloClientError.status(let status, let body) where status == 404 || status == 409 {
            throw SettingsRefused(
                reason: Self.detail(body).isEmpty ? "the silo has no library \(library)" : Self.detail(body)
            )
        }
    }

    /// Lays a library out again: with `dryRun`, the moves it would make; otherwise the moves made, and
    /// any rename that failed as a finding. A library the silo does not serve, or cannot reach now,
    /// comes back as `SettingsRefused`.
    public func layOut(_ library: String, on silo: Silo, dryRun: Bool) async throws -> SiloClient.LayoutResult {
        do {
            return try await withOperator(silo) { try await $0.layOut(library, dryRun: dryRun) }
        } catch SiloClientError.status(let status, _) where status == 404 || status == 503 {
            throw SettingsRefused(
                reason: status == 404
                    ? "the silo has no library \(library)"
                    : "\(library) is unavailable: its folder is missing, or holds nothing where the silo's index holds something"
            )
        }
    }

    /// The path a library added within `root` is at: the folder named inside it, or the root itself.
    public static func path(_ folder: String, within root: String) -> String {
        let inside = folder.trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespaces))
        guard !inside.isEmpty else { return root }
        return (root.hasSuffix("/") ? root : root + "/") + inside
    }
}

extension SiloClient.LibraryCheck {
    /// The path as far as it exists: up to the deepest folder along it that is there, or nothing
    /// when not even the first is.
    public var present: String {
        components.last { $0.state == .folder }?.path ?? ""
    }

    /// The rest of the path, from the first folder that is missing or is not a folder: what the
    /// console shows apart, to be made or refused.
    public var absent: String {
        String(path.dropFirst(present.count))
    }

    /// Whether the silo refuses the path itself, as against the name the library would have. The silo
    /// judges the path before the name, so a refusal that is not a path's — outside the roots or where a
    /// drive mounts (403), a file in the way, folders missing and not asked for — leaves the path good.
    public func refusesPath(create: Bool) -> Bool {
        guard let refusal else { return false }
        return refusal.status == 403 || components.contains { $0.state == .notAFolder } || !creates.isEmpty && !create
    }
}
