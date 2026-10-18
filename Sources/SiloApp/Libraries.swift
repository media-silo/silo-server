// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import Logging
import SiloStore
import Synchronization

/// The libraries the silo serves, and whether each is available: a library whose folder is missing,
/// or whose last walk found nothing where the index holds something, is unavailable — kept in the
/// index, listed as such, and answering 503 for its media — rather than fatal. `Libraries.md`,
/// *Unavailable libraries*.
package final class Libraries: Sendable {
    private let config: SiloConfig
    private let index: Index
    private let logger = Logger(label: "silo.libraries")
    /// Why each unavailable library is unavailable; a library not here is available.
    private let unavailable = Mutex<[String: LibraryUnavailable]>([:])

    package init(config: SiloConfig, index: Index) {
        self.config = config
        self.index = index
    }

    package var all: [LibraryConfig] {
        config.libraries
    }

    package func library(_ id: String) -> LibraryConfig? {
        config.library(id)
    }

    /// Walks every library, as the boot does before the first request is answered. A library that
    /// cannot be walked is reported and left unavailable; the boot never stops for one.
    package func walkAll() throws {
        for library in all {
            try walk(library)
        }
    }

    /// Walks one library and records whether it is available. The report when the walk was applied;
    /// nil when the library is unavailable and the index was left as it was.
    @discardableResult
    package func walk(_ library: LibraryConfig) throws -> ScanReport? {
        do {
            let report = try Indexer.scan(library, into: index)
            logger.info("scanned \(library.id): \(report.read) read, \(report.unchanged) unchanged, \(report.removed) removed")
            for finding in report.findings {
                logger.warning("\(library.id): \(finding)")
            }
            record(library, nil)
            return report
        } catch let reason as LibraryUnavailable {
            record(library, reason)
            return nil
        }
    }

    /// Whether a library is available, as a request reaching for it finds it: a folder that has gone
    /// makes it unavailable at once, and one that has come back is walked before the answer.
    package func reach(_ library: LibraryConfig) throws -> Bool {
        if !folderExists(library) {
            record(library, .missing)
            return false
        }
        guard isAvailable(library.id) else { return try walk(library) != nil }
        return true
    }

    /// Whether a library is available, noticing a folder that has gone but walking nothing.
    package func availability(of library: LibraryConfig) -> Bool {
        if !folderExists(library) { record(library, .missing) }
        return isAvailable(library.id)
    }

    package func isAvailable(_ id: String) -> Bool {
        unavailable.withLock { $0[id] == nil }
    }

    private func folderExists(_ library: LibraryConfig) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: library.root.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// Records a library's availability, logging a change of it once rather than at every look.
    private func record(_ library: LibraryConfig, _ reason: LibraryUnavailable?) {
        let changed = unavailable.withLock { current -> Bool in
            let was = current[library.id]
            current[library.id] = reason
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
