// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloStore
import Testing

struct BlobStoreTests {
    @Test func aBlobIsKeptADayUnlessAStoreNamesIt() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let blobs = try BlobStore(folder: folder)
        let named = try blobs.put(Data([0xFF, 0xD8, 0xFF, 0x01]))
        let unnamed = try blobs.put(Data([0xFF, 0xD8, 0xFF, 0x02]))
        #expect(try blobs.put(Data([0xFF, 0xD8, 0xFF, 0x01])) == named, "put again, a blob is held once")
        #expect(blobs.data(of: "not a digest") == nil)

        blobs.sweep(now: Date().addingTimeInterval(BlobStore.lifetime / 2))
        #expect(blobs.data(of: named) != nil && blobs.data(of: unnamed) != nil, "within a day both are kept")

        blobs.sweep(now: Date().addingTimeInterval(2 * BlobStore.lifetime), keeping: [named])
        #expect(blobs.data(of: named) == Data([0xFF, 0xD8, 0xFF, 0x01]), "a store under way keeps what it names")
        #expect(blobs.data(of: unnamed) == nil)
    }
}
