// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

#if canImport(SwiftUI)
import SiloAdminKit
import SwiftUI

/// A stop's Episodes group: each field of the episodes beneath it, ticked or unticked at every one of them
/// at once, with how many it would change. Ticking one confirms nothing.
struct EpisodeFields: View {
    let walk: ReviewWalk
    let model: ConsoleModel
    let stop: String

    var body: some View {
        let (fields, unread) = walk.episodeFields(at: stop)
        if !fields.isEmpty {
            GroupBox("Episodes") {
                VStack(alignment: .leading) {
                    ForEach(fields) { field in
                        Toggle(
                            isOn: Binding(get: { field.ticked ?? false }, set: { model.chooseEpisodes(field.id, $0) })
                        ) {
                            Text("\(Self.name(field.id)): \(Self.count(field, unread: unread))")
                        }
                    }
                    if unread > 0 {
                        Text(
                            "\(unread) of them not read yet: ticked here, a field is ticked at them too, and taken "
                                + "where Wikidata's or TMDb's differs."
                        )
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private static func name(_ field: String) -> String {
        switch field {
        case "title": "Titles"
        case "outline": "Outlines"
        case "premiered": "First dates"
        case "cast": "Cast"
        case "crew": "Directors and writers"
        default: field
        }
    }

    private static func count(_ field: ReviewWalk.EpisodeField, unread: Int) -> String {
        let changed = field.episodes == 1 ? "1 episode" : "\(field.episodes) episodes"
        let read = unread > 0 ? "\(changed) of those read" : changed
        return field.ticked == nil ? "\(read), ticked at some" : read
    }
}
#endif
