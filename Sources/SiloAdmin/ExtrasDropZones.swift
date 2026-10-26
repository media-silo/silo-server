// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

#if canImport(SwiftUI)
import SiloAdminKit
import SmdKit
import SwiftUI

/// A container's extras as places to drop a special: one for each type an extra may be, and one to
/// decline it, each with how many specials are placed there.
struct ExtrasDropZones: View {
    let container: String
    let placements: [Int: SpecialPlacement]
    let place: (Int, SpecialPlacement) -> Void
    /// Whether a special may be declined from here: for a series' own container.
    var declines = false
    @State private var targeted: String?

    var body: some View {
        GroupBox("Extras: drop a special on its kind") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(EntryType.extraTypes, id: \.self) { type in
                    zone(
                        type.rawValue,
                        title: Self.title(of: type),
                        count: count { $0 == .extra(of: container, type: type.rawValue) }
                    ) {
                        .extra(of: container, type: type.rawValue)
                    }
                }
                if declines {
                    zone("declined", title: "Declined", count: count { $0 == .declined }) { .declined }
                }
            }
        }
    }

    private func count(_ matching: (SpecialPlacement) -> Bool) -> Int {
        placements.values.filter(matching).count
    }

    private func zone(
        _ key: String,
        title: String,
        count: Int,
        placement: @escaping () -> SpecialPlacement
    )
        -> some View
    {
        HStack {
            Text(title)
            Spacer()
            if count > 0 { Text("\(count)").foregroundStyle(.secondary) }
        }
        .font(.caption)
        .padding(6)
        .background(
            targeted == key ? AnyShapeStyle(Color.accentColor.opacity(0.25)) : AnyShapeStyle(.quaternary.opacity(0.4)),
            in: .rect(cornerRadius: 6)
        )
        .dropDestination(for: String.self) { payloads, _ in
            guard case .special(let special)? = payloads.first.flatMap(AlternativeDrag.init) else { return false }
            place(special, placement())
            return true
        } isTargeted: { isTargeted in
            if isTargeted {
                targeted = key
            } else if targeted == key {
                targeted = nil
            }
        }
    }

    /// An extra's type in words: `behindTheScenes` as "Behind the scenes".
    static func title(of type: EntryType) -> String {
        let words = type.rawValue.reduce(into: "") { words, character in
            if character.isUppercase { words += " " }
            words += String(character).lowercased()
        }
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
#endif
