// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import ArgumentParser
import Encoder
import Foundation
import SiloKit
import SmdKit

/// Encode one file by one ruleset, with no server: probe it, say what it is, resolve the recipe,
/// show it, run it, and check the output has the layout the recipe promised.
struct Encode: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Encode one file from a ruleset file, and verify the output's stream layout."
    )

    @Option(name: .customLong("ruleset"), help: "The ruleset XML file.")
    var rulesetPath: String

    @Option(help: "The item's kind: episode, movie, featurette, interview, trailer…")
    var kind: String?

    @Option(help: "The profile being made: mobile, sdr…; none for the unqualified presentation.")
    var profile: String?

    @Option(help: "The disc format the file came from: dvd, bluray or uhd.")
    var format: SourceFormat?

    @Option(name: .customLong("makemkv"), help: "A JSON file of what MakeMKV recorded about the title (MakeMKVFacts).")
    var makeMKVPath: String?

    @Option(help: "An audio stream, from one, that is a commentary. Repeatable; also maps it as feature \"commentary\".")
    var commentary: [Int] = []

    @Option(help: "An audio stream, from one, that is descriptive audio. Repeatable.")
    var descriptive: [Int] = []

    @Option(help: "An audio stream, from one, that is an isolated music track. Repeatable; maps it as feature \"music\".")
    var music: [Int] = []

    @Flag(name: .customLong("dry-run"), help: "Resolve and show the recipe; encode nothing.")
    var dryRun = false

    @Flag(help: "Print the recipe as JSON instead of a table.")
    var json = false

    @Argument(help: "The file to encode.")
    var input: String

    @Argument(help: "Where to write the result. Required unless --dry-run.")
    var output: String?

    mutating func validate() throws {
        if !dryRun && output == nil {
            throw ValidationError("an output path is required unless --dry-run is given")
        }
    }

    mutating func run() async throws {
        let ruleset = try RulesetFile.ruleset(from: Data(contentsOf: URL(fileURLWithPath: rulesetPath)))
        let makeMKV = try makeMKVPath.map { try JSONDecoder().decode(MakeMKVFacts.self, from: Data(contentsOf: URL(fileURLWithPath: $0))) }

        let inputURL = URL(fileURLWithPath: input)
        let probe = try FFprobe()
        let probed = try await probe.probe(inputURL)

        var roles: [Int: AudioRole] = [:]
        var mappings: [TrackMapping] = []
        for index in commentary { roles[index] = .commentary; mappings.append(TrackMapping(feature: "commentary", audio: index)) }
        for index in descriptive { roles[index] = .descriptive }
        for index in music { roles[index] = .isolatedMusic; mappings.append(TrackMapping(feature: "music", audio: index)) }

        let facts = SourceFacts(
            probe: probed, makeMKV: makeMKV, roles: roles,
            kind: kind.map(EntryType.init(rawValue:)), profile: profile, format: format
        )

        let recipe: Recipe
        do {
            recipe = try RecipeResolver.resolve(facts, with: ruleset, mappings: mappings)
        } catch {
            for hint in facts.hints { printError("hint: \(hint)") }
            printError("error: \(error)")
            throw ExitCode.failure
        }

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(decoding: try encoder.encode(recipe), as: UTF8.self))
        } else {
            print(Self.describe(recipe, facts: facts, mappings: mappings))
        }
        for hint in facts.hints { print("hint: \(hint)") }
        for warning in recipe.warnings { print("warning: \(warning)") }

        guard !dryRun, let output else { return }
        let outputURL = URL(fileURLWithPath: output)
        let ffmpeg = try FFmpeg()
        let arguments = recipe.ffmpegArguments(input: inputURL, output: outputURL)
        let duration = facts.duration
        try await ffmpeg.run(arguments) { progress in
            var line = "encoding"
            if let seconds = progress.seconds {
                if let duration, duration > 0 { line += String(format: " %3.0f%%", min(100, seconds / duration * 100)) }
                line += String(format: " %.1fs", seconds)
            }
            if let fps = progress.fps { line += String(format: " %.0f fps", fps) }
            if let speed = progress.speed { line += String(format: " %.2fx", speed) }
            FileHandle.standardError.write(Data(("\r" + line.padding(toLength: 60, withPad: " ", startingAt: 0)).utf8))
        }
        FileHandle.standardError.write(Data("\n".utf8))

        let result = try await probe.probe(outputURL)
        let mismatches = recipe.verify(against: result, source: facts)
        if mismatches.isEmpty {
            print("layout verified: \(recipe.layout.streams.count) streams as the recipe promised")
        } else {
            for mismatch in mismatches { printError("layout mismatch: \(mismatch)") }
            throw ExitCode.failure
        }
    }

    static func describe(_ recipe: Recipe, facts: SourceFacts, mappings: [TrackMapping]) -> String {
        var lines = ["ruleset \(recipe.ruleset)"]
        for decision in recipe.decisions {
            let what: String = switch decision.kind {
            case .video:
                facts.video.map { "\($0.codec) \($0.width)x\($0.height)\($0.interlaced ? " interlaced" : "")\($0.hdr.map { " \($0.rawValue)" } ?? "")" } ?? "?"
            case .audio:
                facts.audio.first { $0.index == decision.sourceIndex }.map {
                    "\($0.codec)\($0.profile.map { " \($0)" } ?? "") \($0.channels)ch \($0.language ?? "und") \($0.role.rawValue)\($0.lossless ? " lossless" : "")\($0.core ? " core" : "")"
                } ?? "?"
            case .subtitle:
                facts.subtitles.first { $0.index == decision.sourceIndex }.map {
                    "\($0.codec) \($0.language ?? "und")\($0.forced ? " forced" : "")"
                } ?? "?"
            }
            let action: String = switch decision.action {
            case .copy: "copy"
            case .drop: "drop"
            case .encode(let settings): "encode \(settings.codec)"
            }
            let placed = recipe.layout.outputIndex(of: decision.kind, sourceIndex: decision.sourceIndex).map { " => \(decision.kind.rawValue) \($0)" } ?? ""
            lines.append("\(decision.kind.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)) \(decision.sourceIndex)  \(what) -> \(action) (\(decision.rule))\(placed)")
        }
        for track in recipe.tracks(for: mappings) {
            var where_ = [String]()
            if let audio = track.audio { where_.append("audio \(audio)") }
            if let subtitle = track.subtitle { where_.append("subtitle \(subtitle)") }
            lines.append("track \(track.feature) -> \(where_.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }

    private func printError(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }
}

extension SourceFormat: ExpressibleByArgument {}
