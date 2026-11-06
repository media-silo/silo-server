// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SmdKit

/// What a provider's terms say about the content read from it: how long it may be kept, and whether
/// it is free for smddb to take.
extension Provider {
    /// The months a provider's terms let content read from it be kept, or nil where they set no limit.
    /// TMDb's forbid keeping anything read from it for longer than six months.
    public var keepsContentForMonths: Int? {
        self == .tmdb ? 6 : nil
    }

    /// Whether the provider releases its content as CC0, so that an attributed field may go to smddb.
    public var releasesContentAsCC0: Bool {
        self == .wikidata
    }
}

extension CalendarDate {
    /// Today, in the calendar and time zone the silo runs in.
    public static var today: CalendarDate {
        let components = Calendar(identifier: .gregorian).dateComponents(in: .current, from: Date())
        return CalendarDate(year: components.year ?? 1970, month: components.month ?? 1, day: components.day ?? 1)!
    }

    /// The same day `months` later, or that month's last day when it is shorter.
    public func adding(months: Int) -> CalendarDate {
        let index = year * 12 + (month - 1) + months
        let (later, month) = (index / 12, index % 12 + 1)
        for day in stride(from: day, through: 1, by: -1) {
            if let date = CalendarDate(year: later, month: month, day: day) { return date }
        }
        return CalendarDate(year: later, month: month, day: 28)!
    }
}
