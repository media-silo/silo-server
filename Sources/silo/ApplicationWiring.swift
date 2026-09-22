// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import Logging
import SiloApp
import SiloStore
import Wire

/// The bindings the controllers ask for and nothing else provides: the index, brought up to date
/// with every library before the first request, and the ruleset store.
package enum ApplicationWiring {
    @Provides
    package static func index(config: SiloConfig) throws -> Index {
        try FileManager.default.createDirectory(at: config.stateDirectory, withIntermediateDirectories: true)
        let index = try Index(at: config.stateDirectory.appendingPathComponent("index.sqlite"))
        let logger = Logger(label: "silo.index")
        for library in config.libraries {
            let report = try Indexer.scan(library, into: index)
            logger.info("scanned \(library.id): \(report.read) read, \(report.unchanged) unchanged, \(report.removed) removed")
            for finding in report.findings {
                logger.warning("\(library.id): \(finding)")
            }
        }
        return index
    }

    @Provides
    package static func rulesets(config: SiloConfig) throws -> RulesetStore {
        try RulesetStore(folder: config.stateDirectory.appendingPathComponent("rulesets", isDirectory: true))
    }
}
