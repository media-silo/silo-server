// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import ArgumentParser

/// The operator's command line. Each subcommand arrives with the part of the silo it operates;
/// `encode` is first because it needs no server at all.
@main
struct SiloCtl: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "silo-ctl",
        abstract: "Operate a silo: encode, place, and later browse, approve and queue.",
        subcommands: [Encode.self, Place.self]
    )
}
