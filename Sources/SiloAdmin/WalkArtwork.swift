// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

#if canImport(SwiftUI)
import SiloAdminKit
import SwiftUI

/// Another of the images TMDb offers for an artwork kind chosen at a stop, given the kind and the image.
struct ImageChoice {
    let stop: String
    let choose: (String, String) -> Void
}

/// The images TMDb offers for an artwork kind, the one storing puts marked, and any other chosen in its
/// place.
struct ImageStrip: View {
    let kind: String
    let offered: [String]
    let chosen: String
    let choose: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ScrollView(.horizontal) {
                HStack {
                    ForEach(offered, id: \.self) { image in
                        Button {
                            choose(kind, image)
                        } label: {
                            TMDbImage(path: image, size: 44)
                        }
                        .buttonStyle(.plain)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(image == chosen ? Color.accentColor : .clear, lineWidth: 2)
                        )
                        .help(
                            image == chosen
                                ? "The image storing puts. Double-click, or press Space, to see it whole."
                                : "Put this image instead. Double-click, or press Space, to see it whole."
                        )
                    }
                }
                .padding(2)
            }
            Text("\(offered.count) offered: choose another to put it instead").font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// An image TMDb holds, by its path there, fitted to a square of the size given, and shown whole in
/// Quick Look; one TMDb does not give is said to be missing rather than shown loading.
struct TMDbImage: View {
    let path: String
    let size: CGFloat

    var body: some View {
        AsyncImage(url: URL(string: "https://image.tmdb.org/t/p/w185\(TMDb.raster(path))")) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFit()
            case .failure:
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary)
                    .help("TMDb did not give this image.")
            default:
                ProgressView()
            }
        }
        .frame(width: size, height: size)
        .previewable(URL(string: "https://image.tmdb.org/t/p/original\(TMDb.raster(path))"))
    }
}
#endif
