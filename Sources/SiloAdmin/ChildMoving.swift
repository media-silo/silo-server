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

    /// Whether a child dropped before another, or last with none, would move: one dropped on itself, on
    /// the child after it, or past the last when it is last already stays where it is.
    static func moves(_ child: String, before key: String?, in order: [String]) -> Bool {
        guard let index = order.firstIndex(of: child) else { return true }
        let next = order.indices.contains(index + 1) ? order[index + 1] : nil
        return key != child && key != next
    }
}

/// A list's children moved, each dragged by its grab handle onto another to go before it or past the
/// last to go last, or from its right-click menu: the keys they go by, in order, what moves one, which
/// one a drag is over, and which one's handle the pointer is on. The order is worked out only when a
/// child is moved, not for every row each time a hover or a drag over the list renders it again.
@MainActor
struct ChildMoving {
    let order: () -> [String]
    let move: (_ child: String, _ before: String?) -> Void
    @Binding var dropping: String?
    @Binding var grabbing: String?

    /// A child moved from its right-click menu, a place at a time or to either end.
    @ViewBuilder
    func menu(_ key: String) -> some View {
        let order = order()
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

    /// A child dropped where it already is is taken and left there, so no drag of one ever fails: a
    /// failed drag slides back to where it began, and leaves the rows it was over still marked. Whatever
    /// was marked during the drag is cleared once it is dropped.
    func drop(_ payloads: [String], before key: String?) -> Bool {
        dropping = nil
        grabbing = nil
        guard let moved = payloads.first.flatMap(ChildDrag.child) else { return false }
        if ChildDrag.moves(moved, before: key, in: order()) { move(moved, key) }
        return true
    }

    func target(_ key: String, _ targeted: Bool) {
        if targeted {
            dropping = key
        } else if dropping == key {
            dropping = nil
        }
    }

    func grab(_ key: String, _ over: Bool) {
        if over {
            grabbing = key
        } else if grabbing == key {
            grabbing = nil
        }
    }
}

/// The width a grab handle takes, kept by a row that has none so the rows line up.
private let handleWidth: CGFloat = 14

extension View {
    /// A child moved by the grab handle on its leading side, which runs its whole height, so a group's
    /// runs beside all its entries: while the pointer is on the handle, what it moves is shaded. One
    /// dropped on the child goes before it, marked by a line along its top while a drag is over it. A
    /// row nothing moves keeps the handle's room, and is as it is when nothing moves the list's rows.
    @ViewBuilder
    func movable(_ key: String?, titled title: String, by mover: ChildMoving?, group: Bool = false) -> some View {
        if let mover, let key {
            HStack(alignment: .center, spacing: 4) {
                ChildHandle(key: key, title: title, mover: mover, group: group)
                self
            }
            .fixedSize(horizontal: false, vertical: true)
            .background(
                Color.accentColor.opacity(mover.grabbing == key ? 0.12 : 0),
                in: .rect(cornerRadius: 4)
            )
            .dropDestination(for: String.self) { payloads, _ in
                mover.drop(payloads, before: key)
            } isTargeted: {
                mover.target(key, $0)
            }
            .overlay(alignment: .top) {
                Rectangle().fill(Color.accentColor).frame(height: 2).offset(y: -3)
                    .opacity(mover.dropping == key ? 1 : 0)
            }
        } else if mover != nil {
            HStack(spacing: 4) {
                Color.clear.frame(width: handleWidth, height: 1)
                self
            }
        } else {
            self
        }
    }
}

/// A child's grab handle: dragged, it moves the child, and a group's is a bar the height of its entries,
/// so it reads as moving them all.
private struct ChildHandle: View {
    let key: String
    let title: String
    let mover: ChildMoving
    let group: Bool

    var body: some View {
        let over = mover.grabbing == key
        ZStack {
            if group {
                Capsule().fill(over ? Color.accentColor : Color.secondary.opacity(0.35)).frame(width: 3)
                    .padding(.vertical, 2)
            }
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundStyle(over ? Color.accentColor : .secondary)
                .padding(.vertical, 2)
                .background(group ? Color(nsColor: .windowBackgroundColor) : .clear)
        }
        .frame(width: handleWidth)
        .frame(maxHeight: .infinity)
        .contentShape(.rect)
        .onHover { mover.grab(key, $0) }
        .help(group ? "Drag to move the group and everything in it" : "Drag to move")
        .draggable(ChildDrag.payload(key)) {
            Label(title, systemImage: group ? "folder" : "film")
                .padding(6).background(.regularMaterial, in: .rect(cornerRadius: 6))
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
