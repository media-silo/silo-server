// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

#if canImport(SwiftUI)
import Foundation
import SiloAdminKit
import SmdKit

// MARK: - Walks against TMDb

extension ConsoleModel {
    var walking: Walking? {
        get { tmdbState.walking }
        set {
            // However the sheet closes, readings nobody is shown stop asking TMDb and the silo.
            if newValue?.id != tmdbState.walking?.id {
                for reading in tmdbState.readings.values { reading.cancel() }
                tmdbState.readings = [:]
                tmdbState.pooling?.cancel()
                tmdbState.pooling = nil
            }
            tmdbState.walking = newValue
        }
    }

    /// Starts a walk of a held container's tree against TMDb, rooted at it: its first stop opened and
    /// read, and, for a walk rooted below a series, the series' specials read beside it.
    func compareWithTMDb(_ key: ContainerKey, on silo: AdminConsole.Silo) async {
        let root = TMDbWalk.Stop(id: key.container, title: key.container, type: "")
        let starting = Walking(silo: silo, walk: TMDbWalk(library: key.library, root: root), open: key.container)
        walking = starting
        guard database != nil, tmdb != nil else {
            walking?.failure = tmdbProblem ?? smddbProblem ?? "TMDb or smddb's clone cannot be read."
            return
        }
        do {
            let walk = try await console.startWalk(at: key.container, in: key.library, of: silo)
            guard walking?.id == starting.id else { return }
            walking?.walk = walk
            if let series = walk.series, series != walk.root { readSpecials(of: series, for: starting.id) }
        } catch {
            if walking?.id == starting.id { walking?.failure = describe(error) }
            return
        }
        await openStop(key.container)
    }

    /// Opens a stop of the walk, reading it against TMDb if it has not been read.
    func openStop(_ stop: String) async {
        guard walking?.walk.stops[stop] != nil else { return }
        walking?.open = stop
        await read(stop)
    }

    /// Reads the open stop again, after its reading failed.
    func readStopAgain() async {
        guard let open = walking?.open, tmdbState.readings[open] == nil else { return }
        walking?.walk.stops[open]?.comparison = nil
        await read(open)
    }

    /// Opens the first stop not yet confirmed, in the tree's order.
    func nextStop() async {
        guard let next = walking?.walk.next else { return }
        await openStop(next)
    }

    /// Reads a stop against TMDb, each step shown as it goes with what it has found; a reading already
    /// running is waited for, and a stop read already is not read again.
    private func read(_ stop: String) async {
        guard let current = walking, let database, let tmdb else { return }
        if let running = tmdbState.readings[stop] {
            await running.value
            return
        }
        guard current.walk.stops[stop]?.comparison == nil else { return }
        let (id, silo, library) = (current.id, current.silo, current.walk.library)
        walking?.failures[stop] = nil
        walking?.progress[stop] = AdminConsole.TMDbProgress("Opening the container")
        let reading = Task {
            do {
                let comparison = try await console.compare(
                    stop,
                    in: library,
                    of: silo,
                    from: database,
                    tmdb: tmdb,
                    progress: { step, found in await self.reading(step, found, of: stop, for: id) }
                )
                if walking?.id == id { walking?.walk.read(comparison) }
            } catch let unreadable as AdminConsole.NoTMDbReading {
                if walking?.id == id { walking?.failures[stop] = unreadable.reason }
            } catch {
                // A reading stopped by its sheet closing failed at nothing.
                if walking?.id == id, !Task.isCancelled { walking?.failures[stop] = describe(error) }
            }
            guard walking?.id == id else { return }
            walking?.progress[stop] = nil
            tmdbState.readings[stop] = nil
        }
        tmdbState.readings[stop] = reading
        await reading.value
    }

    /// A step of a stop's reading, kept while the walk it was asked for is open.
    private func reading(
        _ step: AdminConsole.TMDbProgress,
        _ found: AdminConsole.TMDbComparison,
        of stop: String,
        for id: UUID
    ) {
        guard walking?.id == id else { return }
        walking?.progress[stop] = step
        walking?.walk.read(found)
    }

    /// Reads the specials of the series above a walk's root, to sit beside every stop.
    private func readSpecials(of series: String, for id: UUID) {
        guard let current = walking, let database, let tmdb else { return }
        let (silo, library) = (current.silo, current.walk.library)
        walking?.pooling = AdminConsole.TMDbProgress("Reading the series' specials")
        tmdbState.pooling = Task {
            do {
                let specials = try await console.specials(
                    of: series,
                    in: library,
                    of: silo,
                    from: database,
                    tmdb: tmdb,
                    progress: { step, found in await self.pooling(step, found, for: id) }
                )
                if walking?.id == id { walking?.walk.pool(specials) }
            } catch {
                if walking?.id == id, !Task.isCancelled { walking?.failure = describe(error) }
            }
            if walking?.id == id { walking?.pooling = nil }
        }
    }

    private func pooling(_ step: AdminConsole.TMDbProgress, _ found: AdminConsole.TMDbComparison, for id: UUID) {
        guard walking?.id == id else { return }
        walking?.pooling = step
        walking?.walk.pool(found)
    }

    /// Confirms the open stop: what is ticked is kept as its pending change, the containers beneath it
    /// join the walk, and the next stop is read while the operator looks at this one.
    func confirmStop() async {
        guard let current = walking else { return }
        do {
            let beneath = try await console.stops(beneath: current.open, in: current.walk, of: current.silo)
            guard walking?.id == current.id else { return }
            walking?.walk.confirm(current.open, beneath: beneath)
            walking?.plan = nil
        } catch {
            walking?.failure = describe(error)
            return
        }
        if let next = walking?.walk.next, next != current.open { Task { await read(next) } }
    }

    /// Puts a special where the operator says, or back among the unassigned.
    func place(_ special: Int, _ placement: SpecialPlacement?) {
        walking?.walk.place(special, placement)
        walking?.plan = nil
    }

    /// Lists everything storing the walk will do, before any of it is done.
    func listStore() {
        do {
            walking?.plan = try walking?.walk.plan()
        } catch {
            walking?.failure = describe(error)
        }
    }

    /// Stores the walk as its list says, stopping at the first refusal; what was not stored stays in the
    /// walk, to be stored again. The root is read again in the browser.
    func storeWalk() async {
        guard let current = walking, let tmdb else { return }
        walking?.storing = true
        defer { walking?.storing = false }
        do {
            let stored = try await console.store(current.walk, of: current.silo, tmdb: tmdb)
            guard walking?.id == current.id else { return }
            walking?.walk = stored.walk
            walking?.stored = stored
            walking?.plan = try? stored.walk.plan()
            await open(ContainerKey(silo: current.silo.id, library: current.walk.library, container: current.walk.root))
        } catch {
            walking?.failure = describe(error)
        }
    }
}
#endif
