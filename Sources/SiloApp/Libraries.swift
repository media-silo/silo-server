// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import Logging
import SiloLibrary
import SiloStore
import SmdKit
import Synchronization

/// What a library's most recent walk found: when it ran, whether the library was available, and the
/// report — the counts and findings when the walk was applied, and why it was not when it was not.
package struct LastWalk: Hashable, Sendable {
    package var walkedAt: Date
    package var available: Bool
    package var report: ScanReport
}

/// A library id another library has already.
package struct LibraryTaken: Error {
    package var reason: String
}

/// A path that once its links are resolved lies within none of `silo.json`'s library roots — or any
/// path, when the roots are empty.
package struct OutsideTheRoots: Error {
    package var reason: String
}

/// A library that cannot be added as it was asked for: a path that is not absolute, or not a folder
/// that exists, or an empty id.
package struct BadLibrary: Error {
    package var reason: String
}

/// The libraries the silo serves, as `settings.json` holds them and the library routes change them
/// while it runs, and keeping the index current with them, which is the server's job and nobody
/// else's. Each is walked at boot, when its folder comes back, and every five minutes
/// regardless; a placement re-reads only the sidecars it wrote, and a request that finds a file gone
/// re-reads its container. A library whose folder is missing, or whose last walk found nothing where
/// the index holds something, is unavailable — kept in the index, listed as such, and answering 503
/// for its media — rather than fatal. `Libraries.md`, *Keeping the index current* and *Unavailable
/// libraries*.
package final class Libraries: Sendable {
    private let config: SiloConfig
    private let settings: SettingsStore
    private let index: Index
    private let checks: CheckSignal
    private let logger = Logger(label: "silo.libraries")
    private let state = Mutex(State())

    private struct State {
        /// Why each unavailable library is unavailable; a library not here is available.
        var unavailable: [String: LibraryUnavailable] = [:]
        var lastWalks: [String: LastWalk] = [:]
        var lanes: [String: LibraryLane] = [:]
    }

    package init(config: SiloConfig, settings: SettingsStore, index: Index, checks: CheckSignal) {
        self.config = config
        self.settings = settings
        self.index = index
        self.checks = checks
    }

    package var all: [LibraryConfig] {
        settings.current.libraries
    }

    package func library(_ id: String) -> LibraryConfig? {
        all.first { $0.id == id }
    }

    /// Where the network may add a library: `silo.json`'s roots, which only the machine's owner writes.
    package var roots: [URL] {
        config.libraryRoots
    }

    // MARK: - Adding and removing

    /// Adds a library over the network: the path absolute, a folder that exists, and once its links
    /// are resolved within one of the roots; the id new. Written to `settings.json`, walked, and only
    /// then answered, so it is served at once. Libraries written into the file by hand are not held to
    /// the roots — the roots bound what the network may add, and what the owner wrote is theirs.
    package func add(id: String, path: String) async throws -> LibraryConfig {
        guard !id.isEmpty, !id.contains("/") else { throw BadLibrary(reason: "a library's id must be a name, without a slash") }
        guard path.hasPrefix("/") else { throw BadLibrary(reason: "\(path) is not an absolute path") }
        let library = LibraryConfig(id: id, root: URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL)
        guard Indexer.folderExists(library) else { throw BadLibrary(reason: "\(path) is not a folder that exists") }
        guard !roots.isEmpty else { throw OutsideTheRoots(reason: "this silo's silo.json names no library roots, so nothing can be added over the network") }
        let resolved = library.root.resolvingSymlinksInPath().path
        guard roots.contains(where: { Self.path(resolved, liesWithin: $0.resolvingSymlinksInPath().path) }) else {
            throw OutsideTheRoots(reason: "\(path) lies within none of the library roots: \(roots.map(\.path).joined(separator: ", "))")
        }
        try settings.update { settings in
            guard !settings.libraries.contains(where: { $0.id == id }) else { throw LibraryTaken(reason: "there is already a library \(id)") }
            settings.libraries.append(library)
        }
        logger.info("added \(id) at \(library.root.path)")
        try await walk(library)
        return library
    }

    /// Removes a library: it leaves `settings.json` and its rows leave the index, after any walk of it
    /// already running; nothing on disk is touched — no sidecar, no media file. The files are the
    /// household's.
    package func remove(_ id: String) async throws {
        guard let library = library(id) else { throw NoSuchLibrary() }
        try settings.update { $0.libraries.removeAll { $0.id == id } }
        try await lane(of: id).exclusively { [self] in try index.forget(library: id) }
        state.withLock { state in
            state.unavailable[id] = nil
            state.lastWalks[id] = nil
            state.lanes[id] = nil
        }
        logger.info("removed \(id); \(library.root.path) is left as it was")
    }

    /// Whether `path` is `root` or inside it, by whole components: `/srv/media2` is not within `/srv/media`.
    static func path(_ path: String, liesWithin root: String) -> Bool {
        root == "/" || path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    // MARK: - Walking

    /// Walks every library, as the boot does before the first request is answered and so before
    /// anything else could reach the index. A library that cannot be walked is reported and left
    /// unavailable; the boot never stops for one.
    package func walkAtBoot() throws {
        for library in all {
            _ = try walkNow(library, logging: true)
        }
    }

    /// Walks one library, joining a walk of it that is already running or waiting, so that the tick,
    /// an addition and a returning folder landing together walk it once and share the report.
    @discardableResult
    package func walk(_ library: LibraryConfig) async throws -> LastWalk {
        try await lane(of: library.id).walk { [self] in try walkNow(library, logging: false) }
    }

    /// The tick's walk: every library, each independently of the others, so that a slow share never
    /// holds up a local disk. An unavailable library is looked for and walked when it is back.
    package func walkEvery() async {
        await withTaskGroup(of: Void.self) { group in
            for library in all {
                group.addTask { [self] in
                    do {
                        try await walk(library)
                    } catch {
                        logger.error("the walk of \(library.id) stopped: \(error)")
                    }
                }
            }
        }
    }

    /// Re-reads, in order, the sidecars a placement wrote — root first, so a container it created is
    /// indexed under the parent that now names it — and walks nothing. It waits for a running walk of
    /// the library, so a walk that read a sidecar before the placement wrote it cannot index the old
    /// one after this has indexed the new.
    package func reread(_ writes: [SidecarWrite], in library: LibraryConfig) async throws {
        try await lane(of: library.id).exclusively { [self] in
            for write in writes {
                let folder = LibraryWalker.relativePath(of: write.url.deletingLastPathComponent(), in: library.root)
                _ = try Indexer.refresh(folder: folder, parent: write.parent, in: library, index: index)
            }
        }
    }

    /// Re-reads one container's sidecar, as the media route does when it finds one of the container's
    /// files gone, so a deletion is noticed the first time anyone trips over it.
    package func refresh(_ container: ContainerID, in library: LibraryConfig) async throws {
        guard let row = try index.container(container) else { return }
        try await lane(of: library.id).exclusively { [self] in
            _ = try Indexer.refresh(folder: row.folder, parent: row.parent.flatMap(ContainerID.init), in: library, index: index)
        }
    }

    /// The walk itself, run by the lane or by the boot: applied, or refused with the library reported
    /// unavailable and the index left as it was, and kept as the library's last walk either way.
    private func walkNow(_ library: LibraryConfig, logging always: Bool) throws -> LastWalk {
        let previous = lastWalk(of: library.id)
        let walk: LastWalk
        do {
            let report = try Indexer.scan(library, into: index)
            walk = LastWalk(walkedAt: .now, available: true, report: report)
            if always || report.read > 0 || report.removed > 0 {
                logger.info("walked \(library.id): \(report.read) read, \(report.unchanged) unchanged, \(report.removed) removed")
            }
            // The same findings at every tick are said once, when they first appear.
            if always || previous?.report.findings != report.findings {
                for finding in report.findings {
                    logger.warning("\(library.id): \(finding)")
                }
            }
            // A walk that read something may have found a container's rules moved to another version.
            if !always, report.read > 0 || report.removed > 0 { checks.request() }
            record(library, nil)
        } catch let reason as LibraryUnavailable {
            var report = ScanReport()
            report.findings = [Finding(.error, "not applied: \(reason)")]
            walk = LastWalk(walkedAt: .now, available: false, report: report)
            record(library, reason)
        }
        state.withLock { $0.lastWalks[library.id] = walk }
        return walk
    }

    private func lane(of id: String) -> LibraryLane {
        state.withLock { state in
            if let lane = state.lanes[id] { return lane }
            let lane = LibraryLane()
            state.lanes[id] = lane
            return lane
        }
    }

    // MARK: - Availability

    /// The library's most recent walk; nil for one never walked.
    package func lastWalk(of id: String) -> LastWalk? {
        state.withLock { $0.lastWalks[id] }
    }

    /// Whether a library is available, as a request reaching for it finds it: a folder that has gone
    /// makes it unavailable at once, and one that has come back is walked before the answer.
    package func reach(_ library: LibraryConfig) async throws -> Bool {
        if !Indexer.folderExists(library) {
            record(library, .missing)
            return false
        }
        guard isAvailable(library.id) else { return try await walk(library).available }
        return true
    }

    /// Whether a library is available, noticing a folder that has gone but walking nothing.
    package func availability(of library: LibraryConfig) -> Bool {
        if !Indexer.folderExists(library) { record(library, .missing) }
        return isAvailable(library.id)
    }

    package func isAvailable(_ id: String) -> Bool {
        state.withLock { $0.unavailable[id] == nil }
    }

    /// Records a library's availability, logging a change of it once rather than at every look.
    private func record(_ library: LibraryConfig, _ reason: LibraryUnavailable?) {
        let changed = state.withLock { state -> Bool in
            let was = state.unavailable[library.id]
            state.unavailable[library.id] = reason
            return (was == nil) != (reason == nil)
        }
        guard changed else { return }
        if let reason {
            logger.warning("\(library.id) is unavailable: \(reason) (\(library.root.path)); its index is kept, and its media answer 503")
        } else {
            logger.info("\(library.id) is available again")
        }
    }
}

/// One library's walks and re-reads, one at a time and in the order they were asked for. A walk asked
/// for while another is running, or waiting its turn, joins that one rather than queueing behind it;
/// a re-read always takes its own turn, since it must index what was written after any walk began.
package actor LibraryLane {
    private var walking: Task<LastWalk, any Error>?
    private var held = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    package init() {}

    package func walk(_ body: @escaping @Sendable () throws -> LastWalk) async throws -> LastWalk {
        if let walking { return try await walking.value }
        let task = Task.detached { [self] in
            await acquire()
            let result = Result { try body() }
            await walked()
            return try result.get()
        }
        walking = task
        return try await task.value
    }

    /// Runs `body` with the library to itself, after whatever holds it now. The body runs off the
    /// lane, which only orders turns, so that joining a walk never waits behind the walk itself.
    package nonisolated func exclusively<T: Sendable>(_ body: @Sendable () throws -> T) async throws -> T {
        await acquire()
        let result = Result { try body() }
        await release()
        return try result.get()
    }

    /// A walk is over: a walk asked for from now on is a new one.
    private func walked() {
        walking = nil
        release()
    }

    private func acquire() async {
        guard held else {
            held = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    /// Hands the library to the next in line, which then holds it; or frees it.
    private func release() {
        if waiting.isEmpty {
            held = false
        } else {
            waiting.removeFirst().resume()
        }
    }
}
