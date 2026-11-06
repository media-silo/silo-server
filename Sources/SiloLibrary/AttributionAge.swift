// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import SiloKit
import SmdKit
import SmdSidecar

/// The walk's warning on content kept longer than its provider's terms allow.
public enum AttributionAge {
    /// A warning, on the sidecar, for each attribution read longer ago than its provider lets its
    /// content be kept.
    public static func findings(_ attributions: [Attribution], sidecar: String, today: CalendarDate) -> [Finding] {
        attributions.compactMap { attribution in
            guard let months = attribution.provider.keepsContentForMonths,
                attribution.read.adding(months: months) < today
            else { return nil }
            return Finding(
                .warning,
                path: sidecar,
                "\(attribution.subject) was read from \(attribution.provider) on \(attribution.read), "
                    + "more than \(months) months ago, longer than its terms let it be kept"
            )
        }
    }
}
