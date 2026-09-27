// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

/// Where a daemon keeps its state: the folder its environment names, or a well-known place on the
/// machine. `Configuration.md`, *Where the state directory lives*: the working directory plays no
/// part, so the same binary started from anywhere is the same silo, and the folder the reset file
/// goes in is findable without reading the service definition.
///
/// The silo and `silo-node` resolve theirs the same way, each from its own variable and under its own
/// folder name, so the two never share a folder on one machine.
public struct StateDirectory: Sendable, Equatable {
    /// Which daemon the folder is for: its variable, and its folder name on each platform.
    public struct Owner: Sendable, Equatable {
        public var variable: String
        public var macOSFolder: String
        public var linuxFolder: String

        public static let silo = Owner(variable: "SILO_STATE_DIR", macOSFolder: "Silo", linuxFolder: "silo")
        public static let node = Owner(variable: "SILO_NODE_STATE_DIR", macOSFolder: "Silo Node", linuxFolder: "silo-node")
    }

    /// Which table the default comes from. Its own type rather than `#if os`, so both tables are
    /// tested on whichever machine runs the suite.
    public enum Platform: Sendable, Equatable {
        case macOS
        case linux

        public static var current: Platform {
            #if os(macOS)
            .macOS
            #else
            .linux
            #endif
        }
    }

    /// What supplied the folder, for the boot's log line.
    public enum Source: Sendable, Equatable, CustomStringConvertible {
        case variable(String)
        case platformDefault

        public var description: String {
            switch self {
            case .variable(let name): name
            case .platformDefault: "platform default"
            }
        }
    }

    public var url: URL
    public var source: Source

    public init(url: URL, source: Source) {
        self.url = url
        self.source = source
    }

    /// The owner's variable when it is set and not empty — a relative value keeping its meaning
    /// against the working directory, since an explicit answer is the deployment's to give — and
    /// otherwise the platform default, chosen by whether the process runs as root. systemd's
    /// `STATE_DIRECTORY` is deliberately not read: every child of a unit that sets it inherits it.
    public static func resolve(
        for owner: Owner,
        environment: [String: String],
        isRoot: Bool,
        home: String,
        platform: Platform
    ) -> StateDirectory {
        if let explicit = environment[owner.variable], !explicit.isEmpty {
            return StateDirectory(url: URL(fileURLWithPath: explicit, isDirectory: true), source: .variable(owner.variable))
        }
        let path: String
        switch (platform, isRoot) {
        case (.macOS, true):
            path = "/Library/Application Support/\(owner.macOSFolder)"
        case (.macOS, false):
            path = home + "/Library/Application Support/\(owner.macOSFolder)"
        case (.linux, true):
            path = "/var/lib/\(owner.linuxFolder)"
        case (.linux, false):
            // The XDG specification says a relative value is invalid and to be ignored.
            let stateHome = environment["XDG_STATE_HOME"].flatMap { $0.hasPrefix("/") ? $0 : nil } ?? home + "/.local/state"
            path = stateHome + "/\(owner.linuxFolder)"
        }
        return StateDirectory(url: URL(fileURLWithPath: path, isDirectory: true), source: .platformDefault)
    }

    /// The same, from this process: its environment, its effective user, its home, its platform.
    public static func resolve(for owner: Owner) -> StateDirectory {
        resolve(
            for: owner,
            environment: ProcessInfo.processInfo.environment,
            isRoot: geteuid() == 0,
            home: NSHomeDirectory(),
            platform: .current
        )
    }
}
