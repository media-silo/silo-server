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
        // A walk this Mac keeps for the container is offered to be resumed, or started again.
        if let kept = console.tmdbWalks.walk(rootedAt: key.container, in: key.library, of: silo.id) {
            walking = Walking(silo: silo, walk: kept, open: kept.next ?? kept.root, resuming: true)
            return
        }
        await startWalk(key, on: silo)
    }

    /// Goes on with the walk this Mac kept, as it was left.
    func resumeWalk() async {
        guard let current = walking, current.resuming else { return }
        walking?.resuming = false
        let walk = current.walk
        if let series = walk.series, series != walk.root, walk.specials.isEmpty {
            readSpecials(of: series, for: current.id)
        }
        await readCompanions(for: current.id)
        await openStop(current.open)
    }

    /// Discards the walk this Mac kept for the container and starts a new one.
    func startWalkAgain() async {
        guard let current = walking else { return }
        try? console.tmdbWalks.remove(current.walk.id, of: current.silo.id)
        await startWalk(
            ContainerKey(silo: current.silo.id, library: current.walk.library, container: current.walk.root),
            on: current.silo
        )
    }

    /// Discards the walk: off this Mac, and the sheet closed. Nothing it held was stored.
    func discardWalk() {
        guard let current = walking else { return }
        try? console.tmdbWalks.remove(current.walk.id, of: current.silo.id)
        walking = nil
    }

    /// Keeps the walk on this Mac as it stands, to be resumed after the console closes.
    func keepWalk() {
        guard var walk = walking?.walk, let silo = walking?.silo, walking?.resuming == false else { return }
        walk.edited = .now
        walking?.walk.edited = walk.edited
        try? console.tmdbWalks.save(walk, for: silo.id)
    }

    private func readCompanions(for id: UUID) async {
        guard let current = walking, current.walk.series != nil else { return }
        let held = try? await console.companionSeries(
            in: current.walk.library,
            besides: current.walk.series,
            of: current.silo
        )
        if walking?.id == id { walking?.companions = held ?? [] }
    }

    private func startWalk(_ key: ContainerKey, on silo: AdminConsole.Silo) async {
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
            await readCompanions(for: starting.id)
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

    /// Says which of TMDb's seasons the open stop, a held season carrying no TMDb id, is, or that it is
    /// unmatched again, and reads it as that season.
    func identifySeason(_ season: Int?) async {
        guard let open = walking?.open, tmdbState.readings[open] == nil else { return }
        walking?.walk.identify(open, as: season)
        walking?.plan = nil
        keepWalk()
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
        // A new stop is a draft from TMDb already, with nothing in the library to read.
        guard current.walk.stops[stop]?.comparison == nil, !current.walk.isNew(stop) else { return }
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
                    identified: current.walk.identified,
                    progress: { step, found in await self.reading(step, found, of: stop, for: id) }
                )
                if walking?.id == id {
                    walking?.walk.read(comparison)
                    keepWalk()
                }
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

    /// Confirms the open stop: the operator saying it is as it should be, so what is ticked is kept as
    /// its pending change, the containers beneath it join the walk, and the next stop is read while the
    /// operator looks at this one. Any change to it afterwards makes it pending again.
    /// A missing child no longer chosen takes its new stops out of the walk, so the console says which
    /// first, and confirms only once the operator says so.
    @discardableResult
    func confirmStop(leavingSaid: Bool = false) async -> Bool {
        guard let current = walking, !current.confirming, let database, let tmdb else { return false }
        let leaving = current.walk.leaving(confirming: current.open)
        if !leaving.isEmpty, !leavingSaid {
            walking?.leaving = leaving.compactMap { current.walk.stops[$0]?.title }
            return false
        }
        walking?.leaving = nil
        walking?.confirming = true
        defer { if walking?.id == current.id { walking?.confirming = false } }
        do {
            let drafts = try await console.drafts(
                confirming: current.open,
                in: current.walk,
                from: database,
                tmdb: tmdb
            )
            let beneath = try await console.stops(beneath: current.open, in: current.walk, of: current.silo)
            guard walking?.id == current.id else { return false }
            walking?.walk.confirm(current.open, beneath: beneath, drafts: drafts)
            walking?.plan = nil
            keepWalk()
        } catch {
            walking?.failure = describe(error)
            return false
        }
        if let next = walking?.walk.next, next != current.open { Task { await read(next) } }
        return true
    }

    /// Confirms the open stop and opens the next, as Confirm and then Next would. When confirming waits
    /// for the operator to say containers may leave the walk, the next is opened once they have.
    func confirmAndNext(leavingSaid: Bool = false) async {
        walking?.nextOnceConfirmed = true
        let confirmed = await confirmStop(leavingSaid: leavingSaid)
        // Still asked while the leaving are being said; otherwise done with, confirmed or not.
        guard confirmed || walking?.leaving == nil else { return }
        walking?.nextOnceConfirmed = false
        if confirmed { await nextStop() }
    }

    /// The open stop pending again, its choices kept, as though nothing were confirmed there.
    func unconfirmStop() {
        guard let open = walking?.open else { return }
        walking?.walk.unconfirm(open)
        walking?.plan = nil
        keepWalk()
    }

    /// Puts a special where the operator says, or back among the unassigned; a new companion series it
    /// names is kept with the walk.
    func place(_ special: Int, _ placement: SpecialPlacement?, companion: Container? = nil) {
        walking?.walk.place(special, placement, companion: companion)
        walking?.plan = nil
        keepWalk()
    }

    /// A new companion series of the operator's own beside the walked one, holding nothing yet, opened as
    /// a stop of its own.
    func addCompanion(_ title: Title, listed: Bool) async {
        guard walking != nil, let id = try? await provisionalID() else { return }
        var series = Container(id: id, type: .series, title: title, listed: listed)
        series.sequences = [Sequence(id: "episodes", items: [])]
        guard walking?.walk.addCompanion(series) == true else { return }
        walking?.plan = nil
        keepWalk()
        await openStop(id.value)
    }

    /// A companion series out of the walk, with the stops beneath it; the root is opened if it was open.
    func dropCompanion(_ id: String) {
        guard let root = walking?.walk.root else { return }
        walking?.walk.dropCompanion(id)
        if let open = walking?.open, walking?.walk.stops[open] == nil { walking?.open = root }
        walking?.plan = nil
        keepWalk()
    }

    /// Shapes the open new stop's draft as a draft from TMDb is shaped.
    func shapeNewStop(_ change: (inout TMDbTree) -> Void) {
        guard let open = walking?.open else { return }
        walking?.walk.shape(open, change)
        walking?.plan = nil
        keepWalk()
    }

    /// Moves one of the open new stop's entries before another, or last, the specials placed after it
    /// kept after it.
    func moveNewStopEntry(_ item: ItemID, before target: ItemID?) {
        guard let open = walking?.open else { return }
        walking?.walk.move(item, at: open, before: target)
        walking?.plan = nil
        keepWalk()
    }

    /// Moves one of the open held stop's entries, by its key, before another, or last; with none, undoes
    /// every move made there.
    func arrangeHeldStop(_ key: String?, before target: String?) {
        guard let open = walking?.open else { return }
        if let key {
            walking?.walk.arrange(key, at: open, before: target)
        } else {
            walking?.walk.unarrange(open)
        }
        walking?.plan = nil
        keepWalk()
    }

    /// A special dropped among the open stop's children, placed in its primary sequence before the child
    /// whose key is given, or last.
    func placeAmongChildren(_ special: Int, before target: String?) {
        guard let open = walking?.open else { return }
        walking?.walk.place(special, at: open, before: target)
        walking?.plan = nil
        keepWalk()
    }

    /// A new container of a kind beneath the open stop, holding nothing yet.
    func addContainer(_ type: ContainerType, title: Title) async {
        guard let open = walking?.open, let id = try? await provisionalID() else { return }
        walking?.walk.addContainer(id, type: type, title: title, beneath: open)
        walking?.plan = nil
        keepWalk()
    }

    /// Groups the open held stop's missing episodes, or changes the groups made of them.
    func groupEpisodes(_ change: (inout TMDbWalk, String) -> Void) {
        guard let open = walking?.open, var walk = walking?.walk else { return }
        change(&walk, open)
        walking?.walk = walk
        walking?.plan = nil
        keepWalk()
    }

    /// Drafts the walk's alternatives, or edits those drafted.
    func draftAlternatives(_ change: (inout TMDbWalk) -> Void) {
        guard var walk = walking?.walk else { return }
        change(&walk)
        walking?.walk = walk
        walking?.plan = nil
        keepWalk()
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
            if stored.refusal == nil {
                // Stored whole, the walk ends, and this Mac keeps it no longer.
                try? console.tmdbWalks.remove(stored.walk.id, of: current.silo.id)
            } else {
                keepWalk()
            }
            if let stale = stored.stale {
                walking?.open = stale
                await read(stale)
            }
            await open(ContainerKey(silo: current.silo.id, library: current.walk.library, container: current.walk.root))
        } catch {
            walking?.failure = describe(error)
        }
    }
}
#endif
