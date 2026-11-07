// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

extension Walk {
    /// The image a stop puts for an artwork kind when its artwork is ticked: the one the operator chose,
    /// or the one TMDb offers first.
    public func image(for kind: String, at stop: String) -> String? {
        stops[stop]?.images?[kind] ?? offeredFirst(kind, at: stop)
    }

    /// Another of the images TMDb offers for an artwork kind chosen at a stop, its artwork ticked with it,
    /// and the stop pending again if that changes anything.
    public mutating func choose(image path: String, for kind: String, at stop: String) {
        guard var images = stops[stop].map({ $0.images ?? [:] }) else { return }
        if image(for: kind, at: stop) != path {
            images[kind] = path == offeredFirst(kind, at: stop) ? nil : path
            stops[stop]?.images = images.isEmpty ? nil : images
            unconfirm(stop)
        }
        choose("artwork:\(kind)", true, at: stop)
    }

    private func offeredFirst(_ kind: String, at stop: String) -> String? {
        let differences = isNew(stop) ? offered(stop) : stops[stop]?.comparison?.differences ?? []
        return differences.lazy.compactMap { difference -> String? in
            guard case .artwork(kind, let path, _, _) = difference else { return nil }
            return path
        }.first
    }
}
