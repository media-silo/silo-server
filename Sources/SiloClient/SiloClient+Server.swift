// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation

// MARK: - Server

extension SiloClient {
    /// Who the silo says it is, openly: its id, its name, and whether it still waits on a setup.
    public struct ServerInfo: Hashable, Sendable, Codable {
        public var id: String
        public var name: String
        public var bootstrap: Bool

        public init(id: String, name: String, bootstrap: Bool) {
            self.id = id
            self.name = name
            self.bootstrap = bootstrap
        }
    }

    /// What the verify probe answers: whether the client's token is the operator's own
    /// (`active`) or a live staged passkey (`pending`, with the deadline it can still be
    /// confirmed by). Anything else is a 401, thrown as `status(401, _)`.
    public enum OperatorStatus: Hashable, Sendable {
        case active
        case pending(confirmBy: Date)

        private struct Wire: Decodable {
            var phase: String
            var confirmBy: Date?
        }

        init(decoding data: Data) throws {
            let wire = try SiloClient.decoder.decode(Wire.self, from: data)
            switch (wire.phase, wire.confirmBy) {
            case ("active", nil): self = .active
            case ("pending", let confirmBy?): self = .pending(confirmBy: confirmBy)
            default: throw SiloClientError.status(200, "an OperatorStatus the client does not know")
            }
        }
    }

    /// What staging tells its stager: the name the setup would take and its deadline.
    public struct SetupStage: Hashable, Sendable, Codable {
        public var id: String
        public var name: String
        public var confirmBy: Date

        public init(id: String, name: String, confirmBy: Date) {
            self.id = id
            self.name = name
            self.confirmBy = confirmBy
        }
    }

    struct SetupRequest: Codable {
        var name: String?
        var passkey: String
    }
    struct SetupConflict: Codable { var confirmBy: Date }

    public func server() async throws -> ServerInfo {
        try await send("GET", "/v1/server")
    }

    /// The verify-access probe: what the client's token amounts to — `active` for the
    /// operator's own, `pending` with its deadline for a live staged passkey — so a 401 here
    /// names the credential and not the server or its node subsystem.
    public func verifyAccess() async throws -> OperatorStatus {
        let (data, status) = try await request("GET", "/v1/operator", body: Nothing?.none)
        guard (200..<300).contains(status) else {
            throw SiloClientError.status(status, String(decoding: data, as: UTF8.self))
        }
        return try OperatorStatus(decoding: data)
    }

    /// Stages the server's only setup. While a stage stands this throws `conflict(confirmBy:)`
    /// carrying the standing stage's deadline; once the server is set up, `status(410, _)`.
    public func setup(name: String? = nil, passkey: String) async throws -> SetupStage {
        do {
            return try await send("POST", "/v1/setup", body: SetupRequest(name: name, passkey: passkey))
        } catch SiloClientError.status(409, let body) {
            if let conflict = try? Self.decoder.decode(SetupConflict.self, from: Data(body.utf8)) {
                throw SiloClientError.conflict(confirmBy: conflict.confirmBy)
            }
            throw SiloClientError.status(409, body)
        }
    }

    /// Spends the staged setup: the passkey travels as the bearer, not as the client's token.
    public func confirmSetup(bearer: String) async throws -> ServerInfo {
        try await send("POST", "/v1/setup/confirm", body: Nothing?.none, headers: ["Authorization": "Bearer \(bearer)"])
    }

    // MARK: - Settings

    /// What `GET /v1/settings` reports: what a route changes, under `editable`, and what none does —
    /// `silo.json`, the state directory, the libraries — under `readOnly`.
    public struct SettingsReport: Hashable, Sendable, Codable {
        public struct Editable: Hashable, Sendable, Codable {
            public var name: String
            public var embeddedNode: Bool
            public var advertise: Bool
            /// Changed through the library routes, not the settings patch.
            public var libraries: [Library]

            public init(name: String, embeddedNode: Bool, advertise: Bool, libraries: [Library] = []) {
                self.name = name
                self.embeddedNode = embeddedNode
                self.advertise = advertise
                self.libraries = libraries
            }
        }

        public struct Library: Hashable, Sendable, Codable {
            public var id: String
            public var path: String

            public init(id: String, path: String) {
                self.id = id
                self.path = path
            }
        }

        public struct Machine: Hashable, Sendable, Codable {
            public var serverID: String
            public var host: String
            public var port: Int
            /// Where a library added over the network must lie; empty, nothing can be.
            public var libraryRoots: [String]
            public var stateDirectory: String

            public init(serverID: String, host: String, port: Int, libraryRoots: [String], stateDirectory: String) {
                self.serverID = serverID
                self.host = host
                self.port = port
                self.libraryRoots = libraryRoots
                self.stateDirectory = stateDirectory
            }
        }

        public var editable: Editable
        public var readOnly: Machine

        public init(editable: Editable, readOnly: Machine) {
            self.editable = editable
            self.readOnly = readOnly
        }
    }

    /// Any of the editable settings; what is left `nil` is left out of the body, and unchanged.
    public struct SettingsPatch: Hashable, Sendable, Codable {
        public var name: String?
        public var embeddedNode: Bool?
        public var advertise: Bool?

        public init(name: String? = nil, embeddedNode: Bool? = nil, advertise: Bool? = nil) {
            self.name = name
            self.embeddedNode = embeddedNode
            self.advertise = advertise
        }
    }

    /// The silo's settings and the facts of its machine. Operator only.
    public func settings() async throws -> SettingsReport {
        try await send("GET", "/v1/settings")
    }

    /// Changes the editable settings, all of the patch or none of it; a refusal is `status(400, _)`
    /// carrying the silo's reason. Operator only.
    public func updateSettings(_ patch: SettingsPatch) async throws -> SettingsReport {
        try await send("PATCH", "/v1/settings", body: patch)
    }
}
