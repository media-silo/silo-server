// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloKit
import Testing
@testable import SiloStore

struct SourceStoreTests {
    static let spec = InputSpec(streams: [InputSpec.Stream(index: 0, kind: .audio, codec: "ac3", channels: 2)])
    static let discTitle = NaturalKey(scheme: "discTitle", value: "3F1AC2E9/00004")

    static func copy(on node: String) -> FileRef {
        FileRef(holder: node, url: URL(string: "http://\(node).local:8743/files/t.mkv")!, secret: "s-\(node)")
    }

    @Test func aSourceIsRegisteredWithAMintedID() throws {
        let store = SourceStore()
        let (source, created) = try store.register(Self.spec, key: nil, copy: Self.copy(on: "ripper"))
        #expect(created)
        #expect(UUID(uuidString: source.id) != nil)
        #expect(source.id == source.id.lowercased())
        #expect(source.copies.map(\.holder) == ["ripper"])
        #expect(store.source(source.id) == source)
    }

    @Test func aNaturalKeyFindsTheSourceAlreadyRegistered() throws {
        let store = SourceStore()
        let (first, _) = try store.register(Self.spec, key: Self.discTitle, copy: Self.copy(on: "ripper"))
        let (second, created) = try store.register(Self.spec, key: Self.discTitle, copy: Self.copy(on: "laptop"))
        #expect(!created)
        #expect(second.id == first.id)
        #expect(Set(second.copies.map(\.holder)) == ["ripper", "laptop"])
        #expect(store.all().count == 1)
    }

    @Test func theSameKeyDescribedOtherwiseIsRefused() throws {
        let store = SourceStore()
        let (first, _) = try store.register(Self.spec, key: Self.discTitle, copy: nil)
        var other = Self.spec
        other.streams.append(InputSpec.Stream(index: 1, kind: .audio, codec: "ac3", channels: 2))
        #expect(throws: SourceStoreError.keyDescribedOtherwise(key: Self.discTitle, source: first.id)) {
            try store.register(other, key: Self.discTitle, copy: Self.copy(on: "laptop"))
        }
        #expect(store.source(first.id)?.copies.isEmpty == true, "and nothing changed")
    }

    @Test func noKeyIsNeverMatched() throws {
        let store = SourceStore()
        _ = try store.register(Self.spec, key: nil, copy: nil)
        _ = try store.register(Self.spec, key: nil, copy: nil)
        #expect(store.all().count == 2)
    }

    @Test func aNodeHoldsAFileOnceAndTheLastCopyCanGo() throws {
        let store = SourceStore()
        let (source, _) = try store.register(Self.spec, key: nil, copy: Self.copy(on: "ripper"))
        var moved = Self.copy(on: "ripper")
        moved.url = URL(string: "http://ripper.local:8743/files/moved.mkv")!
        let held = try store.update(source.id) { $0.hold(moved) }
        #expect(held?.copies == [moved], "a node's second copy replaces its first")
        let gone = try store.update(source.id) { $0.copies.removeAll { $0.holder == "ripper" } }
        #expect(gone?.copies.isEmpty == true)
        #expect(store.source(source.id) != nil, "a source with no copy is kept")
        #expect(try store.update("nothing") { _ in } == nil)
    }

    @Test func sourcesSurviveARestart() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SourceStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let (source, _) = try SourceStore(folder: folder).register(Self.spec, key: Self.discTitle, copy: Self.copy(on: "ripper"))
        let reopened = try SourceStore(folder: folder)
        #expect(reopened.source(source.id)?.input == Self.spec)
        #expect(reopened.source(source.id)?.key == Self.discTitle)
        #expect(reopened.source(source.id)?.copies.map(\.holder) == ["ripper"])
    }
}
