// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloClient
import SmdKit

/// A walk's stores as they are gathered, a library's steps in the plan's order.
struct StorePreparing {
    struct Target: Hashable {
        var library: String
        var container: String
    }

    enum Pending {
        case step(SiloClient.StoreStep)
        case edit(Target)
    }

    /// The walk's library, whose store is sent last.
    var library: String
    var libraries: [String] = []
    var steps: [String: [Pending]] = [:]
    var owners: [String: [[ReviewWalk.Step]]] = [:]
    /// Each container's edit: its draft, and where it is among its library's steps.
    var edits: [Target: (draft: ContainerDraft, position: Int)] = [:]
    /// What each container read for an edit declines in the library; nothing for one the store makes.
    var declined: [Target: [ExternalRef]] = [:]
    /// The containers the store makes, by id.
    var made: [String: Container] = [:]

    mutating func add(_ pending: Pending, in library: String, for step: ReviewWalk.Step) {
        if !libraries.contains(library) { libraries.append(library) }
        steps[library, default: []].append(pending)
        owners[library, default: []].append([step])
    }

    /// The container's edit, changed by `change` from what it has gathered and what the container
    /// declines when it was read: the step that began it, or a new one.
    mutating func edit(
        _ container: String,
        in library: String,
        for step: ReviewWalk.Step,
        _ change: ([ExternalRef]) -> ContainerDraft
    ) {
        let target = Target(library: library, container: container)
        let draft = change(declined[target] ?? [])
        if let position = edits[target]?.position {
            edits[target] = (draft, position)
            owners[library]?[position].append(step)
        } else {
            add(.edit(target), in: library, for: step)
            edits[target] = (draft, steps[library, default: []].count - 1)
        }
    }

    /// The stores, the walk's library last, each under a new key.
    var stores: [ReviewWalk.SentStore] {
        let order = libraries.filter { $0 != library } + libraries.filter { $0 == library }
        return order.map { library in
            ReviewWalk.SentStore(
                library: library,
                key: UUID().uuidString,
                steps: (steps[library] ?? []).map { pending in
                    switch pending {
                    case .step(let step): step
                    case .edit(let target):
                        Self.step(
                            editing: edits[target]!.draft,
                            made: made[target.container] != nil && target.library == self.library
                        )
                    }
                },
                owners: (owners[library] ?? []).map { $0.map(\.id) },
                described: (owners[library] ?? []).map { $0.map(\.described).joined(separator: "; ") }
            )
        }
    }

    private func isMade(_ target: Target) -> Bool { target.library == library && made[target.container] != nil }

    /// An edit in the silo's terms; one of a container the store makes is on what it makes, and leaves
    /// the attributions it was made with.
    static func step(editing draft: ContainerDraft, made: Bool) -> SiloClient.StoreStep {
        .edit(
            .init(
                container: draft.container,
                document: draft.text,
                basedOn: made ? "" : draft.base,
                attributions: made ? nil : draft.attributions.map(AdminConsole.wire),
                declined: draft.declined.map(AdminConsole.wireRefs)
            )
        )
    }
}
