// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import Testing
@testable import SiloKit

struct StateDirectoryTests {
    private func resolve(
        _ environment: [String: String] = [:],
        root: Bool,
        on platform: StateDirectory.Platform,
        for owner: StateDirectory.Owner = .silo
    ) -> StateDirectory {
        StateDirectory.resolve(for: owner, environment: environment, isRoot: root, home: "/home/ada", platform: platform)
    }

    @Test(arguments: [
        (StateDirectory.Platform.macOS, true, "/Library/Application Support/Silo"),
        (.macOS, false, "/home/ada/Library/Application Support/Silo"),
        (.linux, true, "/var/lib/silo"),
        (.linux, false, "/home/ada/.local/state/silo"),
    ])
    func theDefaultIsTheMachinesAndTheUsers(platform: StateDirectory.Platform, root: Bool, path: String) {
        let resolved = resolve(root: root, on: platform)
        #expect(resolved.url.path == path)
        #expect(resolved.source == .platformDefault)
    }

    @Test(arguments: [
        (StateDirectory.Platform.macOS, true, "/Library/Application Support/Silo Node"),
        (.macOS, false, "/home/ada/Library/Application Support/Silo Node"),
        (.linux, true, "/var/lib/silo-node"),
        (.linux, false, "/home/ada/.local/state/silo-node"),
    ])
    func theNodeKeepsAFolderOfItsOwn(platform: StateDirectory.Platform, root: Bool, path: String) {
        #expect(resolve(root: root, on: platform, for: .node).url.path == path)
    }

    @Test func theVariableWinsAndSaysSo() {
        let resolved = resolve(["SILO_STATE_DIR": "/srv/silo"], root: true, on: .linux)
        #expect(resolved.url.path == "/srv/silo")
        #expect(resolved.source == .variable("SILO_STATE_DIR"))
        #expect(resolved.source.description == "SILO_STATE_DIR")
    }

    @Test func anEmptyVariableIsUnset() {
        #expect(resolve(["SILO_STATE_DIR": ""], root: true, on: .linux).url.path == "/var/lib/silo")
    }

    @Test func aRelativeVariableKeepsItsMeaning() {
        let resolved = resolve(["SILO_STATE_DIR": "scratch/state"], root: false, on: .macOS)
        #expect(resolved.url.path == URL(fileURLWithPath: "scratch/state", isDirectory: true).path)
    }

    @Test func anInheritedStateDirectoryChangesNothing() {
        #expect(resolve(["STATE_DIRECTORY": "/var/lib/other"], root: true, on: .linux).url.path == "/var/lib/silo")
    }

    @Test func theNodeDoesNotReadTheSilosVariable() {
        let environment = ["SILO_STATE_DIR": "/var/lib/silo"]
        #expect(resolve(environment, root: true, on: .linux, for: .node).url.path == "/var/lib/silo-node")
        #expect(resolve(["SILO_NODE_STATE_DIR": "/srv/node"], root: true, on: .linux, for: .node).url.path == "/srv/node")
    }

    @Test func anAbsoluteXDGStateHomeIsHonouredAndARelativeOneIgnored() {
        #expect(resolve(["XDG_STATE_HOME": "/data/state"], root: false, on: .linux).url.path == "/data/state/silo")
        #expect(resolve(["XDG_STATE_HOME": "state"], root: false, on: .linux).url.path == "/home/ada/.local/state/silo")
    }
}
