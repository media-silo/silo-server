// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

#if canImport(SwiftUI)
import Foundation
import Testing
@testable import SiloAdmin

/// How an image fetched to be seen whole is named for Quick Look to read it.
struct ArtworkPreviewTests {
    /// A PNG is named as one by its bytes, whatever its URL says, and anything else is read as a JPEG.
    @Test func anImageIsNamedForWhatItsBytesAre() {
        #expect(ArtworkPreview.fileExtension(of: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])) == "png")
        #expect(ArtworkPreview.fileExtension(of: Data([0xFF, 0xD8, 0xFF, 0xE0])) == "jpg")
        #expect(ArtworkPreview.fileExtension(of: Data()) == "jpg")
    }
}
#endif
