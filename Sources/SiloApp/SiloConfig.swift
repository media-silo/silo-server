// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Configuration
import Foundation
import SiloStore

/// What the silo is told at start: where it listens, where its own state lives, which libraries it
/// serves, and the operator's token. Read once, before the graph, and handed in as an input.
package struct SiloConfig: Sendable {
    package var host: String
    package var port: Int
    package var stateDirectory: URL
    package var libraries: [LibraryConfig]
    package var operatorToken: String?
    /// Whether the silo runs a node inside itself, so that one machine is the whole pipeline.
    package var embeddedNode: Bool

    package init(host: String, port: Int, stateDirectory: URL, libraries: [LibraryConfig], operatorToken: String?, embeddedNode: Bool = false) {
        self.host = host
        self.port = port
        self.stateDirectory = stateDirectory
        self.libraries = libraries
        self.operatorToken = operatorToken
        self.embeddedNode = embeddedNode
    }

    /// `SILO_LIBRARIES` is `name=path,name=path`, or one bare path, which is the library `main`.
    package init(reading config: ConfigReader) throws {
        let libraries = config.string(forKey: "SILO_LIBRARIES", default: "")
        var parsed: [LibraryConfig] = []
        for entry in libraries.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !entry.isEmpty {
            if let separator = entry.firstIndex(of: "="), !entry[..<separator].contains("/") {
                parsed.append(LibraryConfig(id: String(entry[..<separator]), root: URL(fileURLWithPath: String(entry[entry.index(after: separator)...]), isDirectory: true)))
            } else {
                parsed.append(LibraryConfig(id: "main", root: URL(fileURLWithPath: entry, isDirectory: true)))
            }
        }
        for library in parsed where !FileManager.default.fileExists(atPath: library.root.path) {
            throw SiloConfigError.missingLibrary(library)
        }
        self.init(
            host: config.string(forKey: "SILO_HOST", default: "0.0.0.0"),
            port: config.int(forKey: "SILO_PORT", default: 8080),
            stateDirectory: URL(fileURLWithPath: config.string(forKey: "SILO_STATE_DIR", default: "silo-state"), isDirectory: true),
            libraries: parsed,
            operatorToken: config.string(forKey: "SILO_OPERATOR_TOKEN").flatMap { $0.isEmpty ? nil : $0 },
            embeddedNode: config.bool(forKey: "SILO_EMBEDDED_NODE", default: false)
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
