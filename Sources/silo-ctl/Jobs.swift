// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import ArgumentParser
import Foundation
import SiloClient
import SiloKit

/// The silo's queue from the operator's side.
struct Jobs: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "The queue: list, show, cancel, retry and place jobs on a silo.",
        subcommands: [List.self, Show.self, Cancel.self, Retry.self, Place.self]
    )

    struct Connection: ParsableArguments {
        @Option(help: "The silo's URL. Defaults to SILO_URL.")
        var silo: String?

        @Option(help: "The operator's token. Defaults to SILO_TOKEN.")
        var token: String?

        func client() throws -> SiloClient {
            let environment = ProcessInfo.processInfo.environment
            guard let text = silo ?? environment["SILO_URL"], let url = URL(string: text) else {
                throw ValidationError("give --silo or set SILO_URL")
            }
            return SiloClient(baseURL: url, token: token ?? environment["SILO_TOKEN"])
        }
    }

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List jobs, oldest first.")

        @OptionGroup var connection: Connection

        @Option(help: "Only jobs in this state.")
        var state: JobState?

        mutating func run() async throws {
            let client = try connection.client()
            let jobs = try await client.jobs(state: state)
            if jobs.isEmpty { print("no jobs"); return }
            let lines = Jobs.Lines(client: client)
            for job in jobs { print(await lines.line(job)) }
        }
    }

    struct Show: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "One job, whole, as JSON.")

        @OptionGroup var connection: Connection
        @Argument var id: String

        mutating func run() async throws {
            let job = try await connection.client().job(id)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            print(String(decoding: try encoder.encode(job), as: UTF8.self))
        }
    }

    struct Cancel: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Cancel a job; one a node is on stops at its next report.")

        @OptionGroup var connection: Connection
        @Argument var id: String

        mutating func run() async throws {
            let client = try connection.client()
            print(await Jobs.Lines(client: client).line(try await client.cancel(id)))
        }
    }

    struct Retry: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Offer a failed or cancelled job again.")

        @OptionGroup var connection: Connection
        @Argument var id: String

        mutating func run() async throws {
            let client = try connection.client()
            print(await Jobs.Lines(client: client).line(try await client.retry(id)))
        }
    }

    struct Place: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Have the silo fetch an encoded job's output and place it.")

        @OptionGroup var connection: Connection
        @Argument var id: String

        mutating func run() async throws {
            let client = try connection.client()
            let job = try await client.place(id)
            print(await Jobs.Lines(client: client).line(job))
            for write in job.placement?.writes ?? [] { print("  \(write)") }
        }
    }

    /// A job as one line: its id, its state, the percent done when encoding, `-> item (profile)` from
    /// its recipe's binding and output, where it was placed, and why it failed. A job keeps its
    /// recipe by id, so the recipe and its binding are fetched, each binding once.
    final class Lines {
        let client: SiloClient
        private var bindings: [String: Binding] = [:]

        init(client: SiloClient) {
            self.client = client
        }

        func line(_ job: Job) async -> String {
            var parts = [job.id, job.state.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)]
            if let progress = job.progress?.fraction, job.state == .encoding { parts.append(String(format: "%3.0f%%", progress * 100)) }
            if let recipe = try? await client.recipe(job.recipe), let binding = await binding(recipe.binding) {
                parts.append("-> \(binding.item)\(recipe.recipe.output.profile.map { " (\($0))" } ?? "")")
            }
            if let placement = job.placement { parts.append("at \(placement.destination)") }
            if let failure = job.failure { parts.append("! \(failure)") }
            return parts.joined(separator: "  ")
        }

        private func binding(_ id: String) async -> Binding? {
            if let known = bindings[id] { return known }
            let fetched = try? await client.binding(id).binding
            bindings[id] = fetched
            return fetched
        }
    }
}

extension JobState: ExpressibleByArgument {}
