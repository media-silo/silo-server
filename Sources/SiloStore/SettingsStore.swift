// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import Synchronization

/// What an operator route may change: the name, the libraries, the embedded node, advertising. The
/// contents of `settings.json` in the state directory.
public struct Settings: Hashable, Sendable {
    public var name: String
    public var libraries: [LibraryConfig]
    public var embeddedNode: Bool
    public var advertise: Bool

    public init(name: String, libraries: [LibraryConfig] = [], embeddedNode: Bool = false, advertise: Bool = true) {
        self.name = name
        self.libraries = libraries
        self.embeddedNode = embeddedNode
        self.advertise = advertise
    }
}

/// `settings.json`, managed by the silo. Opened at startup with the treatment `silo.json` gets —
/// created, filled, never repaired — so the name is fixed at first boot rather than following the
/// host name; after that the silo holds the settings in memory and writes the file whole,
/// atomically, whenever a setting changes. A key the silo does not know is kept through every write.
/// An edit made by hand while the silo runs is overwritten by the next change.
///
/// A `Sendable` class for the reason the other stores are: a change and its write are one section
/// under one lock, and nothing inside it suspends.
public final class SettingsStore: Sendable {
    public static let fileName = "settings.json"

    public let file: URL
    private let state: Mutex<(values: [String: JSONValue], settings: Settings)>

    private init(file: URL, values: [String: JSONValue], settings: Settings) {
        self.file = file
        state = Mutex((values, settings))
    }

    /// In memory only, for tests: changes are held and never written.
    public convenience init(_ settings: Settings) {
        self.init(file: URL(fileURLWithPath: "/dev/null"), values: [:], settings: settings)
    }

    /// Opens `settings.json` in `folder`; `defaultName` is the name a first boot fixes.
    public static func open(in folder: URL, defaultName: String) throws -> (SettingsStore, ConfigurationFileReport) {
        let file = folder.appendingPathComponent(fileName)
        let (values, report) = try ConfigurationFile.open(file, defaults: [
            "name": { .string(defaultName) },
            "libraries": { .array([]) },
            "embeddedNode": { .bool(false) },
            "advertise": { .bool(true) },
        ])
        return (SettingsStore(file: file, values: values, settings: try settings(from: values, file: file)), report)
    }

    /// The settings as they stand.
    public var current: Settings {
        state.withLock { $0.settings }
    }

    /// Changes the settings and writes the file whole before the change is seen; a change that
    /// fails to write is not applied. Answers the settings as they then stand.
    @discardableResult
    public func update(_ change: (inout Settings) throws -> Void) throws -> Settings {
        try state.withLock { state in
            var settings = state.settings
            try change(&settings)
            var values = state.values
            values["name"] = .string(settings.name)
            values["libraries"] = .array(settings.libraries.map { .object(["id": .string($0.id), "path": .string($0.root.path)]) })
            values["embeddedNode"] = .bool(settings.embeddedNode)
            values["advertise"] = .bool(settings.advertise)
            if file.path != "/dev/null" {
                try ConfigurationFile.write(values, to: file)
            }
            state = (values, settings)
            return settings
        }
    }

    private static func settings(from values: [String: JSONValue], file: URL) throws -> Settings {
        guard case .array(let entries)? = values["libraries"] else {
            throw ConfigurationFile.wrongKind("libraries", "a list of libraries, each an id and a path", file)
        }
        let libraries = try entries.map { entry -> LibraryConfig in
            guard case .object(let library) = entry, case .string(let id)? = library["id"], case .string(let path)? = library["path"], !id.isEmpty, !path.isEmpty else {
                throw ConfigurationFile.wrongKind("libraries", "a list of libraries, each an id and a path", file)
            }
            return LibraryConfig(id: id, root: URL(fileURLWithPath: path, isDirectory: true))
        }
        return Settings(
            name: try ConfigurationFile.string("name", in: values, file: file),
            libraries: libraries,
            embeddedNode: try ConfigurationFile.bool("embeddedNode", in: values, file: file),
            advertise: try ConfigurationFile.bool("advertise", in: values, file: file)
        )
    }
}
