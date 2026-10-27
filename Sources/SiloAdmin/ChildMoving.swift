// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

#if canImport(SwiftUI)
import SwiftUI

/// A list's child dragged to be moved, as text: the key its row goes by.
enum ChildDrag {
    /// Where a child dragged past the last goes, marked while it is over it.
    static let end = "silo-child-end"
    private static let prefix = "silo-child:"

    static func payload(_ key: String) -> String { prefix + key }

    /// The key a drag's text carries, or nil when it is no child's.
    static func child(_ payload: String) -> String? {
        payload.hasPrefix(prefix) ? String(payload.dropFirst(prefix.count)) : nil
    }
}

/// A list's children moved, each dragged onto another to go before it or past the last to go last, or
/// from its right-click menu: the keys they go by, in order, what moves one, and which one a drag is
/// over.
@MainActor
struct ChildMoving {
    let order: [String]
    let move: (_ child: String, _ before: String?) -> Void
    @Binding var dropping: String?

    /// A child moved from its right-click menu, a place at a time or to either end.
    @ViewBuilder
    func menu(_ key: String) -> some View {
        if let index = order.firstIndex(of: key) {
            Section("Move") {
                Button("Move Up") { move(key, order[index - 1]) }.disabled(index == 0)
                Button("Move Down") { move(key, order.indices.contains(index + 2) ? order[index + 2] : nil) }
                    .disabled(index == order.count - 1)
                Button("Move to Top") { move(key, order.first) }.disabled(index == 0)
                Button("Move to Bottom") { move(key, nil) }.disabled(index == order.count - 1)
            }
        }
    }

    func drop(_ payloads: [String], before key: String?) -> Bool {
        guard let moved = payloads.first.flatMap(ChildDrag.child), moved != key else { return false }
        move(moved, key)
        return true
    }

    func target(_ key: String, _ targeted: Bool) {
        if targeted {
            dropping = key
        } else if dropping == key {
            dropping = nil
        }
    }
}

extension View {
    /// A child dragged to be moved, and one dropped on it put before it, marked by a line along its top
    /// while a drag is over it; as it is when nothing moves it.
    @ViewBuilder
    func movable(_ key: String?, titled title: String, by mover: ChildMoving?) -> some View {
        if let mover, let key {
            draggable(ChildDrag.payload(key)) {
                Text(title).padding(6).background(.regularMaterial, in: .rect(cornerRadius: 6))
            }
            .dropDestination(for: String.self) { payloads, _ in
                mover.drop(payloads, before: key)
            } isTargeted: {
                mover.target(key, $0)
            }
            .overlay(alignment: .top) {
                Rectangle().fill(Color.accentColor).frame(height: 2).offset(y: -3)
                    .opacity(mover.dropping == key ? 1 : 0)
            }
        } else {
            self
        }
    }
}

/// After a list's last child: one dragged here goes last.
struct ChildEnd: View {
    let mover: ChildMoving

    var body: some View {
        let over = mover.dropping == ChildDrag.end
        Rectangle()
            .fill(over ? Color.accentColor : .clear)
            .frame(height: over ? 2 : 10)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
            .dropDestination(for: String.self) { payloads, _ in
                mover.drop(payloads, before: nil)
            } isTargeted: {
                mover.target(ChildDrag.end, $0)
            }
    }
}
#endif
