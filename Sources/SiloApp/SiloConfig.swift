// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloStore

/// What the silo is told at start: who it is and where it listens, from `silo.json`; where its
/// own state lives; and the libraries, the embedded node and advertising as `settings.json` had them
/// at startup. Read once, before the graph, and handed in as an input. The name is not here: it is
/// the settings store's, since setup changes it while the silo runs.
package struct SiloConfig: Sendable {
    package var serverID: String
    package var host: String
    package var port: Int
    package var stateDirectory: URL
    package var libraries: [LibraryConfig]
    /// Whether the silo runs a node inside itself, so that one machine is the whole pipeline.
    package var embeddedNode: Bool
    /// Whether the silo says where it is through Bonjour.
    package var advertise: Bool

    package init(serverID: String = UUID().uuidString.lowercased(), host: String, port: Int, stateDirectory: URL, libraries: [LibraryConfig], embeddedNode: Bool = false, advertise: Bool = false) {
        self.serverID = serverID
        self.host = host
        self.port = port
        self.stateDirectory = stateDirectory
        self.libraries = libraries
        self.embeddedNode = embeddedNode
        self.advertise = advertise
    }

    /// The two files, as startup opened them. A library whose folder does not exist stops the boot,
    /// naming the library.
    package init(silo: SiloFile, settings: Settings, stateDirectory: URL) throws {
        for library in settings.libraries where !FileManager.default.fileExists(atPath: library.root.path) {
            throw SiloConfigError.missingLibrary(library)
        }
        self.init(
            serverID: silo.serverID,
            host: silo.host,
            port: silo.port,
            stateDirectory: stateDirectory,
            libraries: settings.libraries,
            embeddedNode: settings.embeddedNode,
            advertise: settings.advertise
        )
    }

    package func library(_ id: String) -> LibraryConfig? {
        libraries.first { $0.id == id }
    }
}

package enum SiloConfigError: Error, CustomStringConvertible {
    case missingLibrary(LibraryConfig)

    package var description: String {
        switch self {
        case .missingLibrary(let library): "library \(library.id) is at \(library.root.path), which does not exist"
        }
    }
}
