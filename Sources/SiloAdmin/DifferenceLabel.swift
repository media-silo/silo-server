// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

#if canImport(SwiftUI)
import SiloAdminKit
import SmdKit
import SmdSidecar
import SwiftUI

/// A difference as the walk says it, the same for a held container and a new one: a fact as Wikidata
/// states it, and TMDb's outline and artwork taken with their attribution marked, or read again once
/// TMDb's terms no longer let them be kept.
struct DifferenceLabel: View {
    let difference: ReviewWalk.Difference
    let walk: ReviewWalk
    var images: ImageChoice?

    var body: some View {
        switch difference {
        case .title(let title): Text("Title: \(title)")
        case .year(let year): Text("Year: \(year)")
        case .outline(let text, let record):
            VStack(alignment: .leading) {
                Text(text).font(.callout)
                HStack(spacing: 4) {
                    TMDbMark()
                    Text("taken with its attribution to TMDb \(record)").font(.caption).foregroundStyle(.secondary)
                }
            }
        case .premiered(let date): Text("First shown: \(date.description)")
        case .cast(let cast): Text("Cast: \(Self.cast(cast))")
        case .crew(let crew): Text("Crew: \(Self.crew(crew))")
        case .reference(let item, let ref): Text("\(ref.provider.title) \(ref.value)\(item.map { " for \($0)" } ?? "")")
        case .episode(let episode, _): Text(walk.title(of: episode))
        case .staleOutline(let text, _, let read):
            VStack(alignment: .leading) {
                if let text {
                    Text(text).font(.callout)
                    HStack(spacing: 4) {
                        TMDbMark()
                        Text("read from TMDb \(read), longer ago than TMDb's terms let it be kept: read again")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text(
                        "The outline read from TMDb \(read) is kept longer than TMDb's terms allow, and TMDb no longer has one: removed"
                    )
                }
            }
        case .child(let child): Text(child.title)
        case .heldChild(let child, let container, let suggested):
            let held = walk.stops[container]?.title ?? container
            if suggested {
                Text(
                    "\(child.title): perhaps \(held), which the library holds with no Wikidata id; say which season it is when the walk reaches it"
                )
            } else if walk.identified[container] != nil {
                Text("\(child.title): held as \(held), as you said it is")
            } else {
                Text("\(child.title): held as \(held)")
            }
        case .unmatchedSeason: EmptyView()
        case .order(let sequence, let items):
            Text("\(sequence ?? "The sequence") in Wikidata's order: \(items.joined(separator: ", "))")
        case .artwork(let kind, let path, let record, _):
            VStack(alignment: .leading) {
                TMDbArtwork(path: images.flatMap { walk.image(for: kind, at: $0.stop) } ?? path)
                HStack(spacing: 4) {
                    Text("\(kind),")
                    TMDbMark()
                    Text("taken with its attribution to TMDb \(record.id)")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        case .staleArtwork(let kind, let path, _, _, let read):
            if let path {
                VStack(alignment: .leading) {
                    TMDbArtwork(path: images.flatMap { walk.image(for: kind, at: $0.stop) } ?? path)
                    HStack(spacing: 4) {
                        Text("\(kind),")
                        TMDbMark()
                        Text("read from TMDb \(read), longer ago than TMDb's terms let it be kept: read again")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(
                    "\(kind), read from TMDb \(read) and kept longer than TMDb's terms allow; TMDb no longer has one: removed"
                )
            }
        case .special(let special): Text(special.episode.title)
        }
    }

    /// The cast, each with the character they play: `Billie Piper as Rose Tyler; …`.
    static func cast(_ people: [ReviewWalk.Person]) -> String {
        people.map { person in person.role.map { "\(person.name) as \($0)" } ?? person.name }
            .joined(separator: "; ")
    }

    /// The crew, each with the job they did: `Keith Boak [Director], Russell T Davies [Writer]`.
    static func crew(_ people: [ReviewWalk.Person]) -> String {
        people.map { person in person.role.map { "\(person.name) [\($0)]" } ?? person.name }
            .joined(separator: ", ")
    }
}
#endif
