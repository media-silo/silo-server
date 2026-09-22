// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import OpenAPIRuntime  // swiftlint:disable:this unused_import
import SiloAPI
import SiloKit
import SiloStore
import Wire
import WireMVC
import WireOpenAPI

/// The operations that change the silo: a scan, and storing a ruleset. Grouped here so that one
/// middleware on the controller is the whole of the operator gate.
@Singleton
@OpenAPIController(spec: "SiloAPI")
@Middleware(RouteMiddleware.requireOperator)
package struct OperatorController {
    private let config: SiloConfig
    private let index: Index
    private let store: RulesetStore

    @Inject
    package init(config: SiloConfig, index: Index, store: RulesetStore) {
        self.config = config
        self.index = index
        self.store = store
    }

    @Operation
    @ErrorResponse(NoSuchLibrary.self, .notFound)
    package func scanLibrary(@Path library: String) async throws -> Components.Schemas.ScanReport {
        guard let library = config.library(library) else { throw NoSuchLibrary() }
        let report = try Indexer.scan(library, into: index)
        return Components.Schemas.ScanReport(read: report.read, unchanged: report.unchanged, removed: report.removed, findings: report.findings.map(Mapping.finding))
    }

    @Operation
    @ErrorResponse(BadRuleset.self, .badRequest, { Components.Schemas.Problem(detail: $0.reason) })
    package func storeRuleset(@Path name: String, @JSONBody body: Components.Schemas.RulesetDocument) async throws -> Components.Schemas.RulesetDocument {
        let data = Data(body.document.utf8)
        let version: Int
        do {
            version = try store.store(data, as: name)
        } catch let error as RulesetFileError {
            throw BadRuleset(reason: error.description)
        } catch let error as RulesetStoreError {
            throw BadRuleset(reason: error.description)
        }
        return Components.Schemas.RulesetDocument(name: name, version: version, document: body.document)
    }
}
