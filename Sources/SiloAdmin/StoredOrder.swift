// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

#if canImport(SwiftUI)
import SiloAdminKit
import SwiftUI

/// A held stop's primary sequence as storing will leave it, each entry moved by dragging it or from its
/// right-click menu, and the order kept with the walk until it is undone.
struct StoredOrder: View {
    let walk: TMDbWalk
    let model: ConsoleModel
    let stop: String
    @State private var dropping: String?

    var body: some View {
        let entries = walk.storedEntries(at: stop)
        if entries.count > 1 {
            let mover = ChildMoving(
                order: entries.map(\.id),
                move: { model.arrangeHeldStop($0, before: $1) },
                dropping: $dropping
            )
            GroupBox {
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        "As storing will leave it. Drag an entry onto another to put it before it, or right-click it to move it."
                    )
                    .font(.caption).foregroundStyle(.secondary)
                    ForEach(entries) { entry in
                        HStack {
                            Image(systemName: entry.isContainer ? "folder" : "film").foregroundStyle(.secondary)
                            Text(entry.title)
                            if entry.isAdded { Text("added").font(.caption).foregroundStyle(.green) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                        .movable(entry.id, titled: entry.title, by: mover)
                        .contextMenu { mover.menu(entry.id) }
                    }
                    ChildEnd(mover: mover)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                HStack {
                    Text("Primary sequence, in order")
                    Spacer()
                    if walk.arrangedEntries[stop] != nil {
                        Button("Undo Moves") { model.arrangeHeldStop(nil, before: nil) }
                            .buttonStyle(.borderless).font(.caption)
                            .help("The order storing would give it had nothing been moved.")
                    }
                }
            }
        }
    }
}
#endif
