// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

#if canImport(SwiftUI)
import AppKit
import SwiftUI
import Testing
@testable import SiloAdmin

/// A bracketed group laid out as the walk lists them: in a lazy stack, one group under another.
@MainActor
struct BracketedTests {
    /// A one-part serial's label, taller than its part once it wraps, stays within the group, and the
    /// group beneath it starts below it, at every width.
    @Test(arguments: [700.0, 420.0, 300.0, 220.0])
    func aLabelTallerThanItsOnePartIsGivenItsRoom(width: Double) throws {
        let frames = Frames()
        let list = ScrollView {
            LazyVStack(alignment: .leading, spacing: 10, pinnedViews: [.sectionHeaders]) {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Bracketed {
                            Toggle(isOn: .constant(true)) { Text("Mission to the Unknown") }
                        } label: {
                            HStack {
                                Toggle(isOn: .constant(true)) { Text("Serial: Mission to the Unknown").bold() }
                                Button("Ungroup") {}.buttonStyle(.borderless).font(.caption)
                            }
                            .measured("label")
                        }
                        .measured("one part")
                        Bracketed {
                            Text("Temple of Secrets")
                            Text("Small Prophet, Quick Return")
                        } label: {
                            Text("Serial: The Myth Makers").bold()
                        }
                        .measured("beneath")
                    }
                } header: {
                    Text("Children")
                }
            }
        }
        .frame(width: width, height: 600)
        .onPreferenceChange(Measured.self) { frames.measured = $0 }
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: width, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: list)
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        let label = try #require(frames.measured["label"])
        let group = try #require(frames.measured["one part"])
        let beneath = try #require(frames.measured["beneath"])
        #expect(label.maxY <= group.maxY + 0.5, "the label within its group")
        #expect(beneath.minY >= label.maxY, "the group beneath starting below the label")
    }
}

@MainActor
private final class Frames {
    var measured: [String: CGRect] = [:]
}

private struct Measured: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Says where the view is laid out, in the window, by name.
    fileprivate func measured(_ name: String) -> some View {
        background(GeometryReader { Color.clear.preference(key: Measured.self, value: [name: $0.frame(in: .global)]) })
    }
}
#endif
