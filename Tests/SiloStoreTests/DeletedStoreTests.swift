// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import Testing

@testable import SiloStore

/// The silo's record of what it deleted: by kind and id, for thirty days, across a restart.
struct DeletedStoreTests {
    static func file() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("DeletedStore-\(UUID().uuidString)/deleted.json")
    }

    @Test func aDeleteIsRecordedByKindAndSurvivesARestart() throws {
        let file = Self.file()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let deleted = try DeletedStore(file: file)
        #expect(!deleted.holds(.trial, "t"), "an id never deleted")
        try deleted.record(.trial, "t")
        #expect(deleted.holds(.trial, "t"))
        #expect(!deleted.holds(.recipe, "t"), "a trial's id is not a recipe's")

        let restarted = try DeletedStore(file: file)
        #expect(restarted.holds(.trial, "t"), "the record across a restart")
        try restarted.forget(.trial, "t")
        #expect(!restarted.holds(.trial, "t"))
        #expect(!(try DeletedStore(file: file)).holds(.trial, "t"), "and an id taken off it stays off")
    }

    @Test func aDeleteLongAgoIsNotHeld() throws {
        let file = Self.file()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let longAgo = Date.now.addingTimeInterval(-31 * 24 * 60 * 60)
        let lately = Date.now.addingTimeInterval(-29 * 24 * 60 * 60)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([
            DeletedStore.Entry(kind: .recipe, id: "old", when: longAgo),
            DeletedStore.Entry(kind: .recipe, id: "recent", when: lately),
        ])
        .write(to: file)

        let deleted = try DeletedStore(file: file)
        #expect(!deleted.holds(.recipe, "old"), "a recipe discarded thirty-one days ago")
        #expect(deleted.holds(.recipe, "recent"), "and one discarded twenty-nine days ago")
        try deleted.record(.library, "films")
        let kept = String(decoding: try Data(contentsOf: file), as: UTF8.self)
        #expect(!kept.contains("\"old\""), "an entry past thirty days is dropped when the record is written")
    }
}
