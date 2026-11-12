// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

#if canImport(SwiftUI)
import SiloAdminKit
import SmdKit
import Testing
@testable import SiloAdmin

/// Which of a stop's groups shows each difference.
struct DifferenceGroupsTests {
    /// A container's first date, cast, and directors and writers are among its fields with its title,
    /// year and outline, so a stop shows them to be ticked; a reference is not one.
    @Test func datesAndCreditsAreAStopsFields() throws {
        let fields: [ReviewWalk.Difference] = [
            .title("Rose"), .year(2005), .outline("Rose meets the Doctor.", record: "1001"),
            .premiered(try #require(CalendarDate("2005-03-26"))), .cast([]), .crew([]),
        ]
        #expect(fields.filter { !$0.isField }.isEmpty)
        let reference = ReviewWalk.Difference.reference(item: nil, try ExternalRef(provider: .tmdb, value: "1001"))
        #expect(!reference.isField)
    }

    /// The crew is said each with their job in brackets, and the cast each as the character they play.
    @Test func creditsAreSaidWithEachRole() {
        let crew = [
            ReviewWalk.Person(name: "Keith Boak", role: "Director"),
            ReviewWalk.Person(name: "Russell T Davies", role: "Writer"),
            ReviewWalk.Person(name: "Phil Collinson"),
        ]
        #expect(DifferenceLabel.crew(crew) == "Keith Boak [Director], Russell T Davies [Writer], Phil Collinson")
        let cast = [
            ReviewWalk.Person(name: "Billie Piper", role: "Rose Tyler"), ReviewWalk.Person(name: "Noel Clarke"),
        ]
        #expect(DifferenceLabel.cast(cast) == "Billie Piper as Rose Tyler; Noel Clarke")
    }
}
#endif
