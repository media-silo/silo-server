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
            let jobs = try await connection.client().jobs(state: state)
            if jobs.isEmpty { print("no jobs"); return }
            for job in jobs { print(Jobs.line(job)) }
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
            print(Jobs.line(try await connection.client().cancel(id)))
        }
    }

    struct Retry: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Offer a failed or cancelled job again.")

        @OptionGroup var connection: Connection
        @Argument var id: String

        mutating func run() async throws {
            print(Jobs.line(try await connection.client().retry(id)))
        }
    }

    struct Place: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Have the silo fetch an encoded job's output and place it.")

        @OptionGroup var connection: Connection
        @Argument var id: String

        mutating func run() async throws {
            let job = try await connection.client().place(id)
            print(Jobs.line(job))
            for write in job.placement?.writes ?? [] { print("  \(write)") }
        }
    }

    static func line(_ job: Job) -> String {
        var parts = [job.id, job.state.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)]
        if let progress = job.progress?.fraction, job.state == .encoding { parts.append(String(format: "%3.0f%%", progress * 100)) }
        parts.append(job.source.url.lastPathComponent)
        if let assignment = job.assignment { parts.append("-> \(assignment.item)\(assignment.profile.map { " (\($0))" } ?? "")") }
        if let placement = job.placement { parts.append("at \(placement.destination)") }
        if let failure = job.failure { parts.append("! \(failure)") }
        return parts.joined(separator: "  ")
    }
}

extension JobState: ExpressibleByArgument {}
