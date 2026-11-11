// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import SmdKit

// MARK: - A stop confirmed with everything beneath it

/// A season of twenty-six parts is twenty-six stops, the season and everything beneath it confirmed in
/// one action. `Proposals/EpisodeDetails.md`.
extension ReviewWalk {
    /// Whether Confirm and everything beneath confirmed a stop that the operator has not opened since.
    public func confirmedFromAbove(_ id: String) -> Bool { stops[id]?.fromAbove == true }

    /// The operator has looked at a stop: it is no longer, and is never, one only confirmed from above.
    public mutating func opened(_ id: String) {
        stops[id]?.fromAbove = false
    }
}

extension AdminConsole {
    /// What Confirm and everything beneath did: the walk, and each stop beneath that could not be read,
    /// left pending, with why.
    public struct ConfirmedBeneath: Sendable {
        public var walk: ReviewWalk
        public var unread: [String: any Error]
    }

    /// Confirms a stop with its ticks, unless it is confirmed already, then reads each stop beneath it the
    /// walk finds, depth first, and confirms each pending one with the ticks it holds: the operator's, at
    /// it, and otherwise the defaults, nothing at a held stop and everything
    /// at a new one. A missing child is drafted only when it is ticked, so the stops confirmed are those
    /// the ticks reach, and no special is placed. Each stop confirmed beneath that the operator has not
    /// opened is marked confirmed from above; one that cannot be read is left pending, with nothing beneath it found, and the rest are
    /// confirmed.
    public func confirm(
        _ id: String,
        withEverythingBeneath walk: ReviewWalk,
        of silo: Silo,
        from database: any ContainerDatabase,
        wikidata: any WikidataSource,
        tmdb: (any TMDbSource)?,
        progress: @escaping @Sendable (String, StepProgress) async -> Void = { _, _ in }
    ) async throws -> ConfirmedBeneath {
        // A stop confirmed with what is ticked there, as Confirm does: the drafts its ticks make, and the
        // stops beneath it, joining the walk.
        func confirm(_ id: String, in walk: inout ReviewWalk) async throws {
            let drafts = try await drafts(confirming: id, in: walk, from: database, wikidata: wikidata, tmdb: tmdb)
            walk.confirm(id, beneath: try await stops(beneath: id, in: walk, of: silo), drafts: drafts)
        }
        var walk = walk
        if walk.stops[id]?.taken == nil { try await confirm(id, in: &walk) }
        var unread: [String: any Error] = [:]
        var queue = walk.stops[id]?.children ?? []
        var seen: Set<String> = [id]
        while !queue.isEmpty {
            try Task.checkCancellation()
            let next = queue.removeFirst()
            guard seen.insert(next).inserted, let stop = walk.stops[next] else { continue }
            if stop.taken == nil {
                do {
                    if stop.comparison == nil, !walk.isNew(next) {
                        await progress(next, StepProgress("Opening the container"))
                        walk.read(
                            try await compare(
                                next,
                                in: walk.library,
                                of: silo,
                                from: database,
                                wikidata: wikidata,
                                tmdb: tmdb,
                                identified: walk.identified,
                                progress: { step, _ in await progress(next, step) }
                            )
                        )
                    }
                    try await confirm(next, in: &walk)
                    if walk.stops[next]?.fromAbove == nil { walk.stops[next]?.fromAbove = true }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    unread[next] = error
                    continue
                }
            }
            queue = (walk.stops[next]?.children ?? []) + queue
        }
        return ConfirmedBeneath(walk: walk, unread: unread)
    }
}
