// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Crypto
import Foundation
import SiloClient
import SmdKit
import SmdSidecar

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension ReviewWalk {
    /// A store of the walk as it is handed to the silo: the library it is made in, the key it is kept
    /// under with the walk before it is sent, its steps in the silo's terms, and, for each of them, the
    /// steps of the plan it makes and how it is said.
    public struct SentStore: Hashable, Sendable, Codable {
        public var library: String
        public var key: String
        public var steps: [SiloClient.StoreStep]
        /// The plan's steps each of the store's steps makes, by id.
        public var owners: [[String]]
        public var described: [String]
    }
}

extension AdminConsole {
    /// How many answers in a row a store's sending and asking after it may lose before the console says
    /// the silo cannot be reached; the store stays kept with the walk under its key.
    static let lostAnswers = 5

    /// Stores the walk as its plan lists it, as one store for each library it edits, the other
    /// libraries' first: the images it puts sent first, then each store sent under a key kept with the
    /// walk, and asked after every `interval` until the silo says it is made or refused. A walk kept
    /// with its store sent asks after it, and does not send it again. `progress` is told the images, and
    /// then each step the silo says it is making, with how many of the store's steps are made before it.
    public func store(
        _ walk: ReviewWalk,
        of silo: Silo,
        tmdb: (any TMDbSource)?,
        pollingEvery interval: Duration = .seconds(1),
        progress: @Sendable (StepProgress) async -> Void = { _ in }
    ) async throws -> ReviewWalkStored {
        var walk = walk
        let plan = try walk.plan()
        var asking = walk.sending != nil
        if walk.sending == nil {
            walk.sending = try await sending(plan, of: walk, on: silo, tmdb: tmdb, progress: progress)
            walk.edited = .now
            try reviewWalks.save(walk, for: silo.id)
        }
        let total = walk.sending?.reduce(0) { $0 + $1.steps.count } ?? 0
        var before = 0
        while let sent = walk.sending?.first {
            let record = try await made(sent, asking: asking, of: silo, every: interval) { record in
                guard let step = record.step, sent.described.indices.contains(step) else { return }
                await progress(StepProgress(sent.described[step], done: before + record.made, of: total))
            }
            asking = false
            walk.stored.formUnion(sent.owners.prefix(record.made).joined())
            if record.state == .refused {
                // The key is freed with the refusal: the walk's next store is sent under a new one.
                walk.sending = nil
                return refused(record, of: sent, in: walk, plan: plan)
            }
            walk.sending?.removeFirst()
            before += sent.steps.count
            if walk.sending?.isEmpty == false { try reviewWalks.save(walk, for: silo.id) }
        }
        walk.sending = nil
        return ReviewWalkStored(
            walk: walk,
            stored: plan.steps.filter { walk.stored.contains($0.id) },
            refusal: nil,
            rest: []
        )
    }

    /// A store refused: what was made before the step refused, why, and the rest, which the walk keeps.
    /// A stop's edit on a sidecar the library has changed since is to be read again, and confirmed again
    /// once the operator has looked.
    private func refused(
        _ record: SiloClient.StoreRecord,
        of sent: ReviewWalk.SentStore,
        in walk: ReviewWalk,
        plan: ReviewWalk.Plan
    ) -> ReviewWalkStored {
        var walk = walk
        var refusal = record.reason ?? "the silo refused the store"
        var stale: String?
        let refusedStep = record.step.flatMap { sent.owners.indices.contains($0) ? sent.owners[$0] : nil } ?? []
        let draft = plan.steps.lazy.compactMap { step -> ContainerDraft? in
            guard refusedStep.contains(step.id), case .edit(let draft) = step.kind else { return nil }
            return draft
        }
        .first
        if refusal.hasPrefix("the sidecar is now"), let draft {
            stale = draft.container
            refusal = Self.changedSince(draft)
            walk.stops[draft.container]?.comparison = nil
            walk.stops[draft.container]?.taken = nil
        }
        return ReviewWalkStored(
            walk: walk,
            stored: plan.steps.filter { walk.stored.contains($0.id) },
            refusal: refusal,
            rest: plan.steps.filter { !walk.stored.contains($0.id) },
            stale: stale
        )
    }

    /// The store's record once the silo says it is made or refused, said to `said` each time it is asked
    /// after while it is under way.
    private func made(
        _ sent: ReviewWalk.SentStore,
        asking: Bool,
        of silo: Silo,
        every interval: Duration,
        said: (SiloClient.StoreRecord) async -> Void
    ) async throws -> SiloClient.StoreRecord {
        var record = try await taken(sent, asking: asking, of: silo, every: interval)
        var lost = 0
        while record.state == .underWay {
            await said(record)
            try await Task.sleep(for: interval)
            do {
                record = try await withOperator(silo) { try await $0.store(sent.key, in: sent.library) }
                lost = 0
            } catch is URLError where lost < Self.lostAnswers {
                lost += 1
            }
        }
        return record
    }

    /// The store as the silo took it: asked after first when it may have been sent already, and sent
    /// when the silo has none under its key. An answer lost is asked after, never sent again blind.
    private func taken(
        _ sent: ReviewWalk.SentStore,
        asking: Bool,
        of silo: Silo,
        every interval: Duration
    ) async throws -> SiloClient.StoreRecord {
        var asking = asking
        var lost = 0
        while true {
            do {
                if asking {
                    do {
                        return try await withOperator(silo) { try await $0.store(sent.key, in: sent.library) }
                    } catch SiloClientError.status(404, _) {}
                }
                return try await withOperator(silo) {
                    try await $0.createStore(sent.steps, key: sent.key, in: sent.library)
                }
            } catch is URLError where lost < Self.lostAnswers {
                lost += 1
                asking = true
                try await Task.sleep(for: interval)
            } catch SiloClientError.status(let status, let body) where status == 400 || status == 409 {
                throw StoreRefused(reason: Self.detail(body))
            }
        }
    }

    // MARK: The store prepared

    /// The stores a plan is sent as, its images put first: each step in the silo's terms, every edit of
    /// one container one step, on the base its stop, or the list, read.
    func sending(
        _ plan: ReviewWalk.Plan,
        of walk: ReviewWalk,
        on silo: Silo,
        tmdb: (any TMDbSource)?,
        progress: @Sendable (StepProgress) async -> Void
    ) async throws -> [ReviewWalk.SentStore] {
        let images = try await sendingImages(of: plan, on: silo, tmdb: tmdb, progress: progress)
        var preparing = StorePreparing(library: walk.library)
        for step in plan.steps {
            try await prepare(step, in: &preparing, images: images, on: silo)
        }
        return preparing.stores
    }

    /// The images the plan puts, by path, each sent to the silo unless it holds them already.
    private func sendingImages(
        of plan: ReviewWalk.Plan,
        on silo: Silo,
        tmdb: (any TMDbSource)?,
        progress: @Sendable (StepProgress) async -> Void
    ) async throws -> [String: String] {
        let paths = plan.steps.compactMap { step -> String? in
            if case .artwork(_, let path, _, _) = step.kind { path } else { nil }
        }
        guard !paths.isEmpty else { return [:] }
        guard let tmdb else { throw StoreRefused(reason: TMDb.Unavailable.noToken.reason) }
        var digests: [String: String] = [:]
        for (index, path) in paths.enumerated() where digests[path] == nil {
            await progress(StepProgress("send the images the walk puts", done: index, of: paths.count))
            let image = try await tmdb.image(at: path)
            let digest = SHA256.hash(data: image).map { String(format: "%02x", $0) }.joined()
            do {
                try await withOperator(silo) { client in
                    if try await !client.holdsBlob(digest) { try await client.putBlob(image, digest: digest) }
                }
            } catch SiloClientError.status(415, _) {
                throw StoreRefused(reason: "the silo takes artwork as a JPEG or a PNG, and TMDb's \(path) is neither")
            } catch SiloClientError.status(413, _) {
                throw StoreRefused(reason: "the silo takes artwork up to 25 MB, and TMDb's \(path) is larger")
            }
            digests[path] = digest
        }
        return digests
    }

    /// A step of the plan added to its library's store: an edit gathered in its container's one edit,
    /// anything else as a step of its own.
    private func prepare(
        _ step: ReviewWalk.Step,
        in preparing: inout StorePreparing,
        images: [String: String],
        on silo: Silo
    ) async throws {
        let library = preparing.library
        switch step.kind {
        case .create(let containers, let parent, let attributions):
            for container in containers { preparing.made[container.id.value] = container }
            let create = SiloClient.StoreCreate(
                documents: containers.map(DraftTree.text),
                parent: parent,
                attributions: attributions.isEmpty ? nil : attributions
            )
            preparing.add(.step(.create(create)), in: library, for: step)
        case .edit(let draft):
            preparing.edit(draft.container, in: library, for: step) { _ in draft }
        case .held, .name, .decline:
            try await prepareEdit(step, in: &preparing, on: silo)
        case .artwork(let kind, let path, let record, let container):
            let attribution = SiloClient.ArtworkAttribution(
                provider: record.ref.provider.rawValue,
                value: record.ref.value,
                read: CalendarDate.today.description
            )
            let artwork = SiloClient.StoreArtwork(
                container: container,
                kind: kind,
                image: images[path],
                attribution: attribution
            )
            preparing.add(.step(.putArtwork(artwork)), in: library, for: step)
        case .removeArtwork(let kind, let container):
            preparing.add(.step(.removeArtwork(.init(container: container, kind: kind))), in: library, for: step)
        }
    }

    /// An edit of a container outside the walk's stops, gathered onto the container as the list read it.
    private func prepareEdit(_ step: ReviewWalk.Step, in preparing: inout StorePreparing, on silo: Silo) async throws {
        let library = preparing.library
        switch step.kind {
        case .held(let edit):
            let target = try await editing(edit.container, in: edit.library, preparing: &preparing, on: silo)
            preparing.edit(edit.container, in: edit.library, for: step) { _ in
                var draft = target
                if var container = draft.value {
                    Self.applying(edit, to: &container)
                    draft.set(container)
                }
                return draft
            }
        case .name(let child, let parent, let creating):
            let target = try await editing(parent, in: library, preparing: &preparing, on: silo)
            preparing.edit(parent, in: library, for: step) { _ in
                var draft = target
                if let held = draft.value { draft.set(Self.naming(child, in: held, at: creating)) }
                return draft
            }
        case .decline(let refs, let series):
            let target = try await editing(series, in: library, preparing: &preparing, on: silo)
            preparing.edit(series, in: library, for: step) { held in
                var draft = target
                var declined = draft.declined ?? held
                for ref in refs where !declined.contains(ref) { declined.append(ref) }
                draft.declined = declined
                return draft
            }
        default:
            break
        }
    }

    /// The draft a container's edits in the store gather in: the one an earlier step began, a container
    /// an earlier step makes, on what it makes, or the container as the library holds it now.
    private func editing(
        _ container: String,
        in library: String,
        preparing: inout StorePreparing,
        on silo: Silo
    ) async throws -> ContainerDraft {
        let target = StorePreparing.Target(library: library, container: container)
        if let held = preparing.edits[target] { return held.draft }
        if library == preparing.library, let made = preparing.made[container] {
            preparing.declined[target] = []
            return ContainerDraft.new(made, in: library, at: ContainerDraft.Creating())
        }
        let opened: OpenedContainer
        do {
            opened = try await open(container: container, in: library, of: silo)
        } catch SiloClientError.status(404, _) {
            throw StoreRefused(reason: "\(library) no longer holds \(container)")
        }
        preparing.declined[target] = try SidecarFile.sidecar(from: opened.sidecar).declined
        return try ContainerDraft.change(opened.container, sidecar: opened.sidecar)
    }
}
