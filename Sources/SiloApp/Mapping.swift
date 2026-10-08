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
package struct BranchConflict: Error {
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
                let id = entry.id?.value
                let listed = (id.flatMap { byItem[$0] } ?? []).filter { profile == nil || $0.profile == profile }
                let described = id.flatMap { sidecar.presentations[$0] } ?? []
                return Components.Schemas.Item(
                    id: id,
                    _type: entry.type?.rawValue ?? (entry.childContainer != nil ? "container" : nil),
                    title: entry.title,
                    outline: entry.outline,
                    optional: entry.optional,
                    container: entry.childContainer?.value,
                    ref: entry.reference.map { ref in ref.container.map { "\($0.value)#\(ref.item.value)" } ?? ref.item.value },
                    externalRefs: entry.externalRefs.map { Components.Schemas.ExternalRef(provider: $0.provider.rawValue, value: $0.value) },
                    presentations: listed.compactMap { indexed in
                        guard let presentation = described.first(where: { $0.file == indexed.file }) else { return nil }
                        return Components.Schemas.Presentation(
                            id: indexed.id,
                            alternative: presentation.alternative,
                            profile: presentation.profile,
                            displayName: sidecar.displayName(of: presentation),
                            file: presentation.file,
                            source: presentation.source.map(Self.source),
                            transform: presentation.transform.map(Self.transform),
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

    /// Where a presentation came from, as its sidecar records it.
    static func source(_ source: PresentationSource) -> Components.Schemas.PresentationSource {
        Components.Schemas.PresentationSource(binding: source.binding, segments: source.segments.map { segment in
            .init(scheme: segment.key?.scheme, value: segment.key?.value, from: segment.chapters?.from, to: segment.chapters?.to)
        })
    }

    /// How a presentation was made, as its sidecar records it.
    static func transform(_ transform: Transform) -> Components.Schemas.Transform {
        Components.Schemas.Transform(ruleset: transform.ruleset, version: transform.version, layers: transform.layers.map { layer in
            switch layer.subject {
            case .binding(let id): .init(binding: id, version: layer.version, digest: layer.digest)
            case .container(let id): .init(container: id.value, version: layer.version, digest: layer.digest)
            }
        })
    }

    static func branch(_ branch: RulesetStore.Branch) -> Components.Schemas.Branch {
        Components.Schemas.Branch(name: branch.name, base: branch.base, head: branch.head, upToDateWith: branch.upToDateWith, closed: branch.closed)
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
