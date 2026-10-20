// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloStore

/// What the silo is told at start, from `silo.json`: who it is, where it listens, and the library
/// roots within which a library added over the network must lie; and where its own state lives. Read
/// once, before the graph, and handed in as an input. The name, the libraries, the embedded node and
/// advertising are not here: they are the settings store's, since routes change them while the silo
/// runs.
package struct SiloConfig: Sendable {
    package var serverID: String
    package var host: String
    package var port: Int
    package var stateDirectory: URL
    package var libraryRoots: [URL]

    package init(
        serverID: String = UUID().uuidString.lowercased(),
        host: String,
        port: Int,
        stateDirectory: URL,
        libraryRoots: [URL] = []
    ) {
        self.serverID = serverID
        self.host = host
        self.port = port
        self.stateDirectory = stateDirectory
        self.libraryRoots = libraryRoots
    }

    /// `silo.json`, as startup opened it.
    package init(silo: SiloFile, stateDirectory: URL) {
        self.init(
            serverID: silo.serverID,
            host: silo.host,
            port: silo.port,
            stateDirectory: stateDirectory,
            libraryRoots: silo.libraryRoots.map { URL(fileURLWithPath: $0, isDirectory: true) }
        )
    }
}
