// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

#if canImport(SwiftUI)
import AppKit
import CryptoKit
import QuickLook
// The overlay QuickLook and SwiftUI make together, which a package build does not import by itself.
import _QuickLook_SwiftUI
import SwiftUI

/// Artwork looked at full size in Quick Look: the image double-clicked, or the one the pointer is over
/// when Space is pressed, fetched whole to a file of this Mac's caches, since Quick Look shows files.
@MainActor @Observable
final class ArtworkPreview {
    /// The image the pointer is over, which Space shows.
    var hovered: URL?
    /// The file Quick Look is showing.
    var showing: URL?

    private let folder = URL.cachesDirectory.appending(path: "Artwork Previews", directoryHint: .isDirectory)

    /// Shows an image in Quick Look, fetched again each time, so a kind put since shows as it is now.
    func show(_ image: URL) async {
        guard let (data, response) = try? await URLSession.shared.data(from: image),
            (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true
        else { return }
        let name = SHA256.hash(data: Data(image.absoluteString.utf8)).prefix(8).map { String(format: "%02x", $0) }
        let file = folder.appending(path: name.joined()).appendingPathExtension(Self.fileExtension(of: data))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
        } catch {
            return
        }
        showing = file
    }

    /// What an image's bytes say it is, for Quick Look to read it as: a PNG, or otherwise a JPEG.
    nonisolated static func fileExtension(of data: Data) -> String {
        data.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? "png" : "jpg"
    }

    /// Space shows the image the pointer is over, or closes Quick Look, unless a text field takes it.
    fileprivate func pressed(_ event: NSEvent) -> NSEvent? {
        guard event.keyCode == 49, event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift]),
            !(NSApp.keyWindow?.firstResponder is NSText)
        else { return event }
        if showing != nil {
            showing = nil
        } else if let hovered {
            Task { await show(hovered) }
        } else {
            return event
        }
        return nil
    }
}

extension View {
    /// The window's artwork, each image marked `previewable`, shown full size in Quick Look.
    func artworkPreviews() -> some View { modifier(ArtworkPreviews()) }

    /// An image double-clicked, or under the pointer when Space is pressed, shown full size in Quick Look
    /// from the URL given, which may name a larger image than the one shown.
    func previewable(_ image: URL?) -> some View { modifier(Previewable(image: image)) }
}

private struct ArtworkPreviews: ViewModifier {
    @State private var preview = ArtworkPreview()
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        @Bindable var preview = preview
        content
            .environment(preview)
            .quickLookPreview($preview.showing)
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [preview] in preview.pressed($0) }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }
}

private struct Previewable: ViewModifier {
    let image: URL?
    @Environment(ArtworkPreview.self) private var preview: ArtworkPreview?

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                guard let preview else { return }
                if inside {
                    preview.hovered = image
                } else if preview.hovered == image {
                    preview.hovered = nil
                }
            }
            // Beside a click, not in place of it, so a button's click still chooses the image.
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    guard let preview, let image else { return }
                    Task { await preview.show(image) }
                }
            )
    }
}
#endif
