// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import FileServing
import Foundation
import SiloKit
import SiloWorker
import Testing
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The file a node serves and the fetch another node makes of it, over a real socket: the two
/// halves of principle 6, files moving between the machines that have them.
struct FileServerTests {
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
}
