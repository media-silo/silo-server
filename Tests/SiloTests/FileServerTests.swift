// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import BasicContainers
import FileServing
import Foundation
import HTTPAPIs
import HTTPTypes
import Logging
import NIOHTTPServer
import SiloApp
import SiloKit
import SiloWorker
import Testing

@testable import silo

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The file a node serves and the fetch another node makes of it, over a real socket: the two
/// halves of principle 6, files moving between the machines that have them.
struct FileServerTests {
    /// The header timer runs while a handler answers, so every server of the silo's, the API and a
    /// participant's file server, is made from one configuration that gives it an hour; the idle and
    /// body timers keep the library's defaults.
    @Test func everyServerKeepsAConnectionOpenWhileItAnswers() async throws {
        let library = NIOHTTPServerConfiguration.ConnectionTimeouts()
        let configuration = try NIOHTTPServerConfiguration.silo(host: "127.0.0.1", port: 0)
        #expect(configuration.connectionTimeouts.readHeader == .seconds(3600))
        #expect(library.readHeader == .seconds(30), "the library's own, which a slow answer outlasts")
        #expect(configuration.connectionTimeouts.idle == library.idle)
        #expect(configuration.connectionTimeouts.readBody == library.readBody)
        #expect(configuration.supportedHTTPVersions == [.http1_1])

        // The silo's API server is made from it: it binds where the silo's configuration says.
        let state = FileManager.default.temporaryDirectory.appendingPathComponent("silo-api-\(UUID().uuidString)")
        let api = try AppBootstrap(config: SiloConfig(host: "127.0.0.1", port: 0, stateDirectory: state)).createServer()
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await api.serve { _, _, _, _ in } }
            defer { group.cancelAll() }
            let bound = try await api.listeningAddresses.first?.port
            #expect((bound ?? 0) > 0)
        }
    }

    @Test func aPublishedFileIsFetchedByRangeWithItsSecretAndByNothingElse() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("silo-files-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data((0..<5000).map { UInt8($0 % 253) })
        let held = root.appendingPathComponent("rip.mkv")
        try bytes.write(to: held)

        let server = try FileServer(host: "127.0.0.1", port: 0, advertisedHost: "127.0.0.1")
        let serving = Task { try await server.run() }
        defer { serving.cancel() }
        let port = try await server.boundPort
        var published = server.publish(held, at: "job-1/source")
        published.url = URL(string: "http://127.0.0.1:\(port)/files/job-1/source")!
        #expect(published.sizeBytes == 5000)
        #expect(server.published == ["job-1/source"])

        func fetch(_ path: String, secret: String?, range: String? = nil) async throws -> (Int, Data, String?) {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
            if let secret { request.setValue(secret, forHTTPHeaderField: "x-silo-secret") }
            if let range { request.setValue(range, forHTTPHeaderField: "Range") }
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as! HTTPURLResponse
            return (http.statusCode, data, http.value(forHTTPHeaderField: "Content-Range"))
        }

        let whole = try await fetch("/files/job-1/source", secret: published.secret)
        #expect(whole.0 == 200)
        #expect(whole.1 == bytes)
        let part = try await fetch("/files/job-1/source", secret: published.secret, range: "bytes=1000-1999")
        #expect(part.0 == 206)
        #expect(part.1 == bytes[1000...1999])
        #expect(part.2 == "bytes 1000-1999/5000")
        #expect(try await fetch("/files/job-1/source", secret: "wrong").0 == 404)
        #expect(try await fetch("/files/job-1/source", secret: nil).0 == 404)
        #expect(try await fetch("/files/job-2/source", secret: published.secret).0 == 404)

        // A node fetches it whole, then resumes an interrupted fetch from what it has.
        let fetched = root.appendingPathComponent("fetched.mkv")
        try await RangeDownloader.download(published, to: fetched)
        #expect(try Data(contentsOf: fetched) == bytes)

        let partial = root.appendingPathComponent("partial.mkv")
        try bytes[..<1234].write(to: partial)
        try await RangeDownloader.download(published, to: partial)
        #expect(try Data(contentsOf: partial) == bytes, "resumed from byte 1234")

        server.unpublish("job-1/source")
        #expect(try await fetch("/files/job-1/source", secret: published.secret).0 == 404)
    }

    /// A holder that sends the head of a gigabyte and 64 KB of it, then nothing more for ten minutes.
    struct Trickle: HTTPServerRequestHandler {
        static let sent = 64 * 1024

        func handle(
            request: HTTPRequest,
            requestContext: consuming NIOHTTPServer.RequestContext,
            reader: consuming sending NIOHTTPServer.Reader,
            responseSender: consuming sending NIOHTTPServer.ResponseSender
        ) async throws {
            var writer = try await responseSender.send(
                HTTPResponse(status: .ok, headerFields: [.contentLength: String(1 << 30)])
            )
            var chunk = UniqueArray<UInt8>(copying: [UInt8](repeating: 0x2A, count: Self.sent))
            try await writer.write(buffer: &chunk)
            try await Task.sleep(for: .seconds(600))
        }
    }

    /// Cancelling the task that awaits a fetch cancels the transfer, rather than leaving it to run to
    /// the end of a file that may be many gigabytes, and keeps what arrived for the next attempt.
    @Test(.timeLimit(.minutes(1))) func aCancelledFetchStopsAndKeepsWhatArrived() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("silo-files-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let server = NIOHTTPServer(
            logger: Logger(label: "silo.tests.trickle"),
            configuration: try .init(
                bindTarget: .hostAndPort(host: "127.0.0.1", port: 0),
                supportedHTTPVersions: [.http1_1],
                transportSecurity: .plaintext
            )
        )
        let serving = Task { try await server.serve(handler: Trickle()) }
        defer { serving.cancel() }
        let port = try #require(try await server.listeningAddresses.first?.port)
        let source = FileRef(holder: "elsewhere", url: URL(string: "http://127.0.0.1:\(port)/slow")!, secret: "s")

        let fetched = root.appendingPathComponent("fetched.mkv")
        let fetching = Task { try await RangeDownloader.download(source, to: fetched) }
        func size() -> Int64 {
            (try? FileManager.default.attributesOfItem(atPath: fetched.path)[.size] as? NSNumber)?.int64Value ?? 0
        }
        while size() < Int64(Trickle.sent) {
            try await Task.sleep(for: .milliseconds(20))
        }
        let cancelled = ContinuousClock.now
        fetching.cancel()
        await #expect(throws: CancellationError.self) { try await fetching.value }
        #expect(ContinuousClock.now - cancelled < .seconds(10), "the transfer was cancelled, not run out")
        #expect(size() == Int64(Trickle.sent), "what arrived is kept, for the next attempt to resume from")
    }

    /// A fetch whose task was cancelled before it began asks the holder for nothing.
    @Test func aFetchFromACancelledTaskIsNeverStarted() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("silo-files-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // Nothing listens here: a request that went out would fail as a refused connection.
        let source = FileRef(holder: "elsewhere", url: URL(string: "http://127.0.0.1:9/never")!, secret: "s")
        let fetched = root.appendingPathComponent("fetched.mkv")
        let fetching = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await RangeDownloader.download(source, to: fetched)
        }
        await #expect(throws: CancellationError.self) { try await fetching.value }
    }

    /// A holder nobody answers for fails the fetch as the connection did.
    @Test func aFetchFromAHolderThatIsNotThereFailsAsTheConnectionDid() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("silo-files-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = FileRef(holder: "elsewhere", url: URL(string: "http://127.0.0.1:9/never")!, secret: "s")
        await #expect(throws: URLError.self) {
            try await RangeDownloader.download(source, to: root.appendingPathComponent("fetched.mkv"))
        }
    }

    /// A holder that answers anything but 200 or 206 fails the fetch with its status.
    @Test func aFetchTheHolderRefusesFailsWithItsStatus() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("silo-files-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let server = try FileServer(host: "127.0.0.1", port: 0, advertisedHost: "127.0.0.1")
        let serving = Task { try await server.run() }
        defer { serving.cancel() }
        let port = try await server.boundPort
        // Nothing is published at this path, so the holder answers 404.
        let source = FileRef(holder: "elsewhere", url: URL(string: "http://127.0.0.1:\(port)/files/gone")!, secret: "s")
        let error = await #expect(throws: WorkerError.self) {
            try await RangeDownloader.download(source, to: root.appendingPathComponent("fetched.mkv"))
        }
        #expect(error?.description == "fetching a source failed: the holder answered 404")
    }

    /// A file longer than the socket buffer arrives whole every time. The server closes a connection whose
    /// request was never read to its end, dropping what of the response is still queued, so before the
    /// handler read its requests a three-megabyte file came back short on some of thirty fetches.
    @Test func aLargeFileArrivesWholeEveryTime() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("silo-files-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data(repeating: 0x2A, count: 3 << 20)
        let held = root.appendingPathComponent("rip.mkv")
        try bytes.write(to: held)

        let server = try FileServer(host: "127.0.0.1", port: 0, advertisedHost: "127.0.0.1")
        let serving = Task { try await server.run() }
        defer { serving.cancel() }
        let port = try await server.boundPort
        let published = server.publish(held, at: "job-1/source")
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/files/job-1/source")!)
        request.setValue(published.secret, forHTTPHeaderField: "x-silo-secret")

        var whole = 0
        for _ in 0..<30 {
            if let (data, _) = try? await URLSession.shared.data(for: request), data == bytes { whole += 1 }
        }
        #expect(whole == 30)
    }
}
