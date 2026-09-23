// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloAPI
import SiloKit
import SiloStore
import SmdKit
import SmdSidecar

package struct NoSuchContainer: Error {}
package struct NoSuchLibrary: Error {}
package struct NoSuchRuleset: Error {}
package struct BadRuleset: Error {
    package var reason: String
}
package struct Unresolvable: Error {
    package var reason: String
}
package struct BadPlacement: Error {
    package var reason: String
}
package struct PlacementRefused: Error {
    package var result: Components.Schemas.PlacementResult
}

/// The index's rows and the sidecar's values as the document's types. One direction only: the API
/// is a projection of the model, never a place the model is edited.
enum Mapping {
    static func summary(_ row: IndexedContainer) -> Components.Schemas.ContainerSummary {
        Components.Schemas.ContainerSummary(
            id: row.id, library: row.library, _type: row.type, title: row.title, displayTitle: row.displayTitle,
            year: row.year, typeLabel: row.typeLabel, outline: row.outline, listed: row.listed, parent: row.parent
        )
    }

    static func container(_ row: IndexedContainer, sidecar: Sidecar, children: [IndexedContainer], presentations: [IndexedPresentation], profile: String?) -> Components.Schemas.Container {
        let container = sidecar.container
        let byItem = Dictionary(grouping: presentations, by: \.item)
        func items(_ entries: [Entry]) -> [Components.Schemas.Item] {
            entries.map { entry in
                let listed = (entry.id.flatMap { byItem[$0] } ?? []).filter { profile == nil || $0.profile == profile }
                let described = entry.id.flatMap { sidecar.presentations[$0] } ?? []
                return Components.Schemas.Item(
                    id: entry.id,
                    _type: entry.type?.rawValue,
                    title: entry.title,
                    outline: entry.outline,
                    optional: entry.optional,
                    container: entry.container?.rawValue,
                    ref: entry.ref.map { ref in ref.container.map { "\($0.rawValue)#\(ref.item)" } ?? ref.item },
                    externalRefs: entry.externalRefs.map { Components.Schemas.ExternalRef(provider: $0.provider.rawValue, value: $0.value) },
                    presentations: listed.compactMap { indexed in
                        guard let presentation = described.first(where: { $0.file == indexed.file }) else { return nil }
                        return Components.Schemas.Presentation(
                            id: indexed.id,
                            alternative: presentation.alternative,
                            profile: presentation.profile,
                            displayName: sidecar.displayName(of: presentation),
                            file: presentation.file,
                            source: presentation.source.map { Components.Schemas.SourceRef(disc: $0.disc, playlist: $0.playlist) },
                            tracks: presentation.tracks.map { Components.Schemas.TrackMapping(feature: $0.feature, audio: $0.audio, subtitle: $0.subtitle) },
                            chapters: presentation.chapters.map { Components.Schemas.Chapter(index: $0.index, title: $0.title) }
                        )
                    }
                )
            }
        }
        return Components.Schemas.Container(
            id: row.id, library: row.library, _type: row.type, title: row.title, displayTitle: row.displayTitle,
            year: row.year, typeLabel: row.typeLabel, outline: row.outline, listed: row.listed, parent: row.parent,
            defaultAlternative: container.defaultAlternative,
            alternatives: container.alternatives.map { Components.Schemas.Alternative(id: $0.id, sequence: $0.sequence, title: $0.title, outline: $0.outline) },
            features: container.features.map { feature in
                Components.Schemas.Feature(
                    id: feature.id, _type: feature.type.rawValue, title: feature.title,
                    participants: feature.participants.map { Components.Schemas.Participant(name: $0.name, role: $0.role) }
                )
            },
            sequences: container.sequences.map { sequence in
                Components.Schemas.Sequence(
                    id: sequence.id,
                    exploded: Components.Schemas.Sequence.explodedPayload(rawValue: sequence.exploded.rawValue) ?? .never,
                    items: items(sequence.items)
                )
            },
            extrasAnchor: container.extrasAnchor,
            extras: items(container.extras),
            children: children.map(summary),
            externalRefs: container.externalRefs.map { Components.Schemas.ExternalRef(provider: $0.provider.rawValue, value: $0.value) }
        )
    }

    static func finding(_ finding: SiloLibrary.Finding) -> Components.Schemas.Finding {
        Components.Schemas.Finding(severity: finding.severity == .error ? .error : .warning, path: finding.path, text: finding.text)
    }

    /// One Codable value as another, through JSON: how SiloKit's facts and recipes cross into the
    /// document's types without a second hand-written mapping to keep in step.
    static func transcode<From: Encodable, To: Decodable>(_ value: From, to type: To.Type = To.self) throws -> To {
        try JSONDecoder().decode(To.self, from: try JSONEncoder().encode(value))
    }
}

import SiloLibrary
