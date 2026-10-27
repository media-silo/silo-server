// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

#if canImport(SwiftUI)
import Testing
@testable import SiloAdmin

/// How a suggested renaming words the parts it titles.
struct GroupingSuggestionTests {
    /// The parts are worded by their own numbers, not counted from one, so a run that starts at a later
    /// part says so.
    @Test func aRenamingIsWordedByThePartsNumbers() {
        let story = GroupingSuggestion(title: "Invasion of the Dinosaurs", members: ["e1", "e2"], parts: [1, 6])
        #expect(story.renamed(as: "Part") == "Part 1 to 6")
        let later = GroupingSuggestion(title: "Planet of Evil", members: ["e3", "e4"], parts: [3, 4])
        #expect(later.renamed(as: "Episode") == "Episode 3 to 4")
    }
}
#endif
