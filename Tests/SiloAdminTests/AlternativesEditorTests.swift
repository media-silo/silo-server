// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

#if canImport(SwiftUI)
import SiloAdminKit
import SmdKit
import Testing
@testable import SiloAdmin

/// What the alternatives editor reads from a drop, and how it words a container's extras.
struct AlternativesEditorTests {
    /// A special, and a drafted alternative's entry, survive being dragged as text, and anything else
    /// dropped is no drag of the editor's.
    @Test func aDragIsReadBackFromItsText() {
        #expect(AlternativeDrag(AlternativeDrag.special(3761).payload) == .special(3761))
        let entry = AlternativeDrag.entry(draft: "4C2A-11:9", position: 2)
        #expect(AlternativeDrag(entry.payload) == entry, "a draft id holding the separator")
        for stray in ["The Daleks", "silo-special:", "silo-special:pilot", "silo-entry:2", "silo-entry:x:draft"] {
            #expect(AlternativeDrag(stray) == nil, "\(stray)")
        }
    }

    /// A new container in an alternative is shown as a container, and taking it out says it goes.
    @Test func aContainerInAnAlternativeIsShownAndRemovedAsOne() {
        #expect(DraftAlternative.Entry.container("00000000000001e8").symbol == "folder")
        #expect(DraftAlternative.Entry.container("00000000000001e8").removal.contains("gone"))
        #expect(
            DraftAlternative.Entry.special(3761).symbol == "film"
                && DraftAlternative.Entry.item("part-1").removal == "Not played by the alternative."
        )
    }

    @Test func anExtrasTypeIsWordedAsASentence() {
        #expect(ExtrasDropZones.title(of: .behindTheScenes) == "Behind the scenes")
        #expect(ExtrasDropZones.title(of: .trailer) == "Trailer")
    }
}
#endif
