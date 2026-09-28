// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import OpenAPIRuntime  // swiftlint:disable:this unused_import
import SiloAPI
import SiloStore
import Wire
import WireMVC
import WireOpenAPI

/// A settings patch that cannot be applied; nothing was changed.
package struct BadSettings: Error {
    package var reason: String
}

/// The settings route: every key of both files and the state directory, read; and the settings an
/// operator route may change, patched. A patch is written to `settings.json` and applied by the
/// services that follow the settings — the embedded node, the advertiser, the server's name — with
/// no restart. Behind the operator gate, like every route that changes the silo.
@Singleton
@OpenAPIController(spec: "SiloAPI")
@Middleware(RouteMiddleware.requireOperator)
package struct SettingsController {
    private let config: SiloConfig
    private let settings: SettingsStore

    @Inject
    package init(config: SiloConfig, settings: SettingsStore) {
        self.config = config
        self.settings = settings
    }

    @Operation
    package func getSettings() async throws -> Components.Schemas.SettingsReport {
        report(settings.current)
    }

    /// All of the body or none of it: every field is checked before the store is touched.
    @Operation
    @ErrorResponse(BadSettings.self, .badRequest, { Components.Schemas.Problem(detail: $0.reason) })
    package func updateSettings(@JSONBody body: Components.Schemas.SettingsPatch) async throws -> Components.Schemas.SettingsReport {
        if let name = body.name, name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw BadSettings(reason: "the name cannot be empty")
        }
        let changed = try settings.update { settings in
            if let name = body.name { settings.name = name }
            if let embeddedNode = body.embeddedNode { settings.embeddedNode = embeddedNode }
            if let advertise = body.advertise { settings.advertise = advertise }
        }
        return report(changed)
    }

    private func report(_ settings: Settings) -> Components.Schemas.SettingsReport {
        Components.Schemas.SettingsReport(
            editable: Components.Schemas.EditableSettings(name: settings.name, embeddedNode: settings.embeddedNode, advertise: settings.advertise),
            readOnly: Components.Schemas.MachineSettings(
                serverID: config.serverID,
                host: config.host,
                port: config.port,
                stateDirectory: config.stateDirectory.path,
                libraries: settings.libraries.map { Components.Schemas.LibrarySetting(id: $0.id, path: $0.root.path) }
            )
        )
    }
}
