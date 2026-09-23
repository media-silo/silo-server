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

    @Provides
    package static func jobs(config: SiloConfig) throws -> JobStore {
        try JobStore(folder: config.stateDirectory.appendingPathComponent("jobs", isDirectory: true))
    }

    @Provides
    package static func nodes(config: SiloConfig) throws -> NodeStore {
        try NodeStore(folder: config.stateDirectory.appendingPathComponent("nodes", isDirectory: true))
    }

    @Provides
    package static func identity(config: SiloConfig) throws -> ServerIdentity {
        try loadServerIdentity(from: config.stateDirectory, named: config.name)
    }

    /// Boot is the one place a reset can happen: the operator's `operator-credential.reset` —
    /// the filesystem's deliberate act, not a network route's — is processed here, its effect
    /// logged loudly, its file gone before the first request. A rotated credential still means
    /// a credential, so a reset never returns the silo to bootstrap.
    @Provides
    package static func operatorCredential(config: SiloConfig) throws -> OperatorCredential {
        let credential = OperatorCredential(file: config.stateDirectory.appendingPathComponent("operator-credential.json"))
        let reset = try processOperatorCredentialReset(
            from: config.stateDirectory.appendingPathComponent("operator-credential.reset"),
            into: credential
        )
        switch reset {
        case .rotated:
            Logger(label: "silo.credential").warning("operator credential rotated from operator-credential.reset; the file is gone")
        case .ignored:
            Logger(label: "silo.credential").warning("operator-credential.reset was empty — removed, the credential is unchanged")
        case nil:
            break
        }
        return credential
    }
}
