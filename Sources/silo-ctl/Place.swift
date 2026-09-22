// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import ArgumentParser
import Foundation
import SiloLibrary
import SmdKit
import SmdSidecar

/// Place a finished file into a library folder as a presentation of an item, with no server: the
/// container tree comes from a clone of the data repository, the writes are shown first, and the
/// sidecars are written last.
struct Place: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Place a finished file into a library as a presentation of an item."
    )

    @Option(help: "The library folder.")
    var library: String

    @Option(help: "A clone of the data repository, where the container tree is read from.")
    var repository: String

    @Option(help: "The container the item is in, by id.")
    var container: String

    @Option(help: "The item, by id.")
    var item: String

    @Option(help: "The alternative the presentation belongs to; none for the default.")
    var alternative: String?

    @Option(help: "The profile: mobile, sdr…; none for the unqualified presentation.")
    var profile: String?

    @Option(help: "A feature at this file's streams, as feature=audio:N or feature=audio:N,subtitle:M. Repeatable.")
    var track: [String] = []

    @Option(help: "A chapter's name, as N=title. Repeatable.")
    var chapter: [String] = []

    @Option(help: "Where the file was ripped from, as disc=playlist.")
    var source: String?

    @Flag(help: "Copy the file into place rather than moving it.")
    var copy = false

    @Flag(name: .customLong("dry-run"), help: "Show the writes; make none.")
    var dryRun = false

    @Argument(help: "The finished file.")
    var file: String

    mutating func run() async throws {
        guard let id = ContainerID(container) else {
            throw ValidationError("\(container) is not a container id: sixteen lowercase hex characters")
        }
        let repository = LocalRepository(root: URL(fileURLWithPath: self.repository))
        let containers = try await repository.containers()
        var byID: [ContainerID: Container] = [:]
        var parent: [ContainerID: ContainerID] = [:]
        for container in containers {
            byID[container.id] = container
            for child in container.childContainerIDs { parent[child] = container.id }
        }
        guard byID[id] != nil else { throw ValidationError("the repository has no container \(id)") }
        var lineage: [Container] = []
        var cursor: ContainerID? = id
        while let current = cursor, let container = byID[current] {
            lineage.insert(container, at: 0)
            cursor = parent[current]
        }

        var presentation = Presentation(alternative: alternative, profile: profile, file: "")
        presentation.tracks = try track.map(Self.parseTrack)
        presentation.chapters = try chapter.map(Self.parseChapter)
        if let source {
            let parts = source.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { throw ValidationError("--source takes disc=playlist") }
            presentation.source = SourceRef(disc: parts[0], playlist: parts[1])
        }

        let libraryURL = URL(fileURLWithPath: library, isDirectory: true)
        let request = PlacementRequest(library: libraryURL, lineage: lineage, item: item, presentation: presentation, source: URL(fileURLWithPath: file))
        let placement = try Placer.compute(request)
        for line in placement.describe(relativeTo: libraryURL) { print(line) }
        for finding in placement.findings { print(finding) }
        guard placement.isApplicable else { throw ExitCode.failure }
        guard !dryRun else { return }
        try Placer.apply(placement, move: !copy)
        print("placed as \(placement.presentation.file)")
    }

    static func parseTrack(_ text: String) throws -> TrackMapping {
        let parts = text.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { throw ValidationError("--track takes feature=audio:N[,subtitle:M]") }
        var mapping = TrackMapping(feature: parts[0])
        for stream in parts[1].split(separator: ",") {
            let pair = stream.split(separator: ":").map(String.init)
            guard pair.count == 2, let index = Int(pair[1]) else { throw ValidationError("--track takes feature=audio:N[,subtitle:M]") }
            switch pair[0] {
            case "audio": mapping.audio = index
            case "subtitle": mapping.subtitle = index
            default: throw ValidationError("--track streams are audio or subtitle")
            }
        }
        return mapping
    }

    static func parseChapter(_ text: String) throws -> Chapter {
        let parts = text.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2, let index = Int(parts[0]) else { throw ValidationError("--chapter takes N=title") }
        return Chapter(index: index, title: parts[1])
    }
}
