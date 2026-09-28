// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation

/// Any JSON value, kept exactly: the form a configuration file is held in, so that a key the silo
/// does not know survives the silo writing the file back. Decoded in a fixed order — a boolean
/// before a number, an integer before a double — so a value reads the same on every platform.
public enum JSONValue: Hashable, Sendable, Codable {
    case null
    case bool(Bool)
    case integer(Int)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

/// A configuration file the silo will not start over: one that does not parse, or a key whose value
/// is not the kind the key takes. The file is left exactly as it was.
public struct ConfigurationFileError: Error, CustomStringConvertible, Equatable {
    public var file: URL
    public var reason: String

    public init(file: URL, reason: String) {
        self.file = file
        self.reason = reason
    }

    public var description: String {
        "\(file.lastPathComponent) at \(file.path): \(reason)"
    }
}

/// What opening a configuration file did, for the boot to log.
public struct ConfigurationFileReport: Hashable, Sendable {
    /// The file did not exist, and was written with every key at its default.
    public var created: Bool
    /// Keys the file lacked, added at their defaults and written back.
    public var filled: [String]
    /// Keys the silo does not know, logged by name and kept.
    public var unknown: [String]

    public init(created: Bool = false, filled: [String] = [], unknown: [String] = []) {
        self.created = created
        self.filled = filled
        self.unknown = unknown
    }

    /// Whether the key was given its default by this opening, rather than read.
    public func defaulted(_ key: String) -> Bool {
        created || filled.contains(key)
    }
}

/// The startup treatment `silo.json` and `settings.json` share (`Configuration.md`): created with
/// every key at its default when missing; filled, key by key, where incomplete; never rewritten when
/// complete; never repaired when malformed; unknown keys reported and kept.
enum ConfigurationFile {
    /// Opens `file`, giving each key in `defaults` its default where the file lacks it. The defaults
    /// are closures so that a minted value — a ServerID — is minted only when it is needed.
    static func open(_ file: URL, defaults: [String: () -> JSONValue]) throws -> ([String: JSONValue], ConfigurationFileReport) {
        guard FileManager.default.fileExists(atPath: file.path) else {
            let values = defaults.mapValues { $0() }
            try write(values, to: file)
            return (values, ConfigurationFileReport(created: true))
        }
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch {
            throw ConfigurationFileError(file: file, reason: "cannot be read: \(error.localizedDescription)")
        }
        var values: [String: JSONValue]
        do {
            values = try JSONDecoder().decode([String: JSONValue].self, from: data)
        } catch {
            throw ConfigurationFileError(file: file, reason: "does not parse as a JSON object: \(parseFailure(error))")
        }
        let filled = defaults.keys.filter { values[$0] == nil }.sorted()
        for key in filled {
            values[key] = defaults[key]?()
        }
        if !filled.isEmpty {
            try write(values, to: file)
        }
        let unknown = values.keys.filter { defaults[$0] == nil }.sorted()
        return (values, ConfigurationFileReport(filled: filled, unknown: unknown))
    }

    /// What a decoding failure comes to, in words a person editing the file can act on.
    private static func parseFailure(_ error: any Error) -> String {
        guard let error = error as? DecodingError else { return "\(error)" }
        switch error {
        case .dataCorrupted(let context):
            if let underlying = context.underlyingError as NSError?, let detail = underlying.userInfo[NSDebugDescriptionErrorKey] as? String {
                return detail
            }
            return context.debugDescription
        case .typeMismatch:
            return "the top level is not an object"
        default:
            return "\(error)"
        }
    }

    /// Writes the whole file atomically: keys sorted, indented, and paths left readable.
    static func write(_ values: [String: JSONValue], to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(values)
        data.append(UInt8(ascii: "\n"))
        try data.write(to: file, options: .atomic)
    }

    // The readers a typed file uses to take its keys out, each naming the key it refuses.

    static func string(_ key: String, in values: [String: JSONValue], file: URL) throws -> String {
        guard case .string(let value)? = values[key] else { throw wrongKind(key, "a string", file) }
        return value
    }

    static func integer(_ key: String, in values: [String: JSONValue], file: URL) throws -> Int {
        guard case .integer(let value)? = values[key] else { throw wrongKind(key, "a whole number", file) }
        return value
    }

    static func bool(_ key: String, in values: [String: JSONValue], file: URL) throws -> Bool {
        guard case .bool(let value)? = values[key] else { throw wrongKind(key, "true or false", file) }
        return value
    }

    static func wrongKind(_ key: String, _ kind: String, _ file: URL) -> ConfigurationFileError {
        ConfigurationFileError(file: file, reason: "\"\(key)\" must be \(kind)")
    }
}

/// `silo.json`: what no operator route changes. The ServerID, the bind host and the port, read once
/// at startup; the silo writes the file only then, to create it or fill a key it lacks, so an
/// owner's edit never races a route and takes effect at the next restart.
public struct SiloFile: Hashable, Sendable {
    public static let fileName = "silo.json"
    public static let defaultHost = "0.0.0.0"
    public static let defaultPort = 8742

    public var serverID: String
    public var host: String
    public var port: Int

    public init(serverID: String, host: String = SiloFile.defaultHost, port: Int = SiloFile.defaultPort) {
        self.serverID = serverID
        self.host = host
        self.port = port
    }

    /// Opens `silo.json` in `folder`, minting the ServerID where the file has none.
    public static func open(in folder: URL) throws -> (SiloFile, ConfigurationFileReport) {
        let file = folder.appendingPathComponent(fileName)
        let (values, report) = try ConfigurationFile.open(file, defaults: [
            "serverID": { .string(UUID().uuidString.lowercased()) },
            "host": { .string(defaultHost) },
            "port": { .integer(defaultPort) },
        ])
        let serverID = try ConfigurationFile.string("serverID", in: values, file: file)
        guard !serverID.isEmpty else { throw ConfigurationFile.wrongKind("serverID", "a non-empty string", file) }
        let port = try ConfigurationFile.integer("port", in: values, file: file)
        guard (0...65535).contains(port) else { throw ConfigurationFile.wrongKind("port", "a port number, 0 to 65535", file) }
        return (SiloFile(serverID: serverID, host: try ConfigurationFile.string("host", in: values, file: file), port: port), report)
    }
}

/// Whether a state directory already holds a silo's state — an operator credential, nodes, jobs —
/// so that a ServerID minted over it can be logged as the new server it makes.
public func stateDirectoryHoldsState(_ folder: URL) -> Bool {
    let manager = FileManager.default
    if manager.fileExists(atPath: folder.appendingPathComponent("operator-credential.json").path) { return true }
    for name in ["nodes", "jobs"] {
        let contents = (try? manager.contentsOfDirectory(atPath: folder.appendingPathComponent(name).path)) ?? []
        if contents.contains(where: { !$0.hasPrefix(".") }) { return true }
    }
    return false
}
