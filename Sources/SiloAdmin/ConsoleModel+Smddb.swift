// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

#if canImport(SwiftUI)
import Foundation
import SiloAdminKit
import SiloClient
import SmdKit

// MARK: - smddb

extension ConsoleModel {
    static let smddbFolderKey = "smddbClone"

    /// The clone as SmdKit's client, when one is named and could be read.
    var database: LocalRepository? {
        guard let smddbFolder, smddbProblem == nil else { return nil }
        return LocalRepository(root: smddbFolder)
    }

    /// Names the folder that is smddb's clone on this Mac, or none, and reads it.
    func chooseClone(_ folder: URL?) async {
        smddbFolder = folder
        UserDefaults.standard.set(folder, forKey: Self.smddbFolderKey)
        await readClone()
    }

    /// Reads the clone again, as the app does when it comes back to the fore, so that a pull made
    /// outside the console is seen; and compares every container opened with it again.
    func readClone() async {
        guard let smddbFolder else {
            smddbProblem = "No clone of smddb's data repository is named in this Mac's settings."
            standings = [:]
            return
        }
        do {
            _ = try await LocalRepository(root: smddbFolder).containers()
            smddbProblem = nil
        } catch {
            smddbProblem = "The clone at \(smddbFolder.path) cannot be read: \(error.localizedDescription)"
        }
        for key in containers.keys { await compareWithSmddb(key) }
    }

    /// How an opened container stands against smddb's record, the two documents compared here.
    func compareWithSmddb(_ key: ContainerKey) async {
        guard let database, let opened = containers[key] else {
            standings[key] = nil
            return
        }
        standings[key] = try? await AdminConsole.standing(of: opened.sidecar, in: database)
    }

    /// smddb's containers matching a title or a provider's id; its roots for no text.
    func searchSmddb(_ text: String) async -> [Container] {
        guard let database else { return [] }
        return (try? await AdminConsole.search(text, in: database)) ?? []
    }

    /// Works out importing a container from smddb. One the library holds already opens as an edit
    /// draft from smddb's record instead, and the import closes.
    func planImport(
        _ id: ContainerID,
        into library: String,
        on silo: AdminConsole.Silo
    ) async -> AdminConsole.ImportPlan? {
        guard let database else { return nil }
        do {
            switch try await console.planImport(id, into: library, of: silo, from: database) {
            case .plan(let plan): return plan
            case .held(let draft):
                importing = nil
                open(draft, for: silo)
                return nil
            }
        } catch {
            fail(error)
            return nil
        }
    }

    /// Imports the plan with the descendants chosen, or asks for its dry run. Made, the library's
    /// containers are read again.
    func runImport(
        _ plan: AdminConsole.ImportPlan,
        choosing chosen: Set<ContainerID>,
        dryRun: Bool,
        on silo: AdminConsole.Silo
    ) async -> AdminConsole.ImportOutcome? {
        guard let database else { return nil }
        do {
            let outcome = try await console.importContainers(
                plan,
                choosing: chosen,
                dryRun: dryRun,
                of: silo,
                from: database
            )
            if case .made = outcome { await loadContainers(for: silo) }
            return outcome
        } catch {
            fail(error)
            return nil
        }
    }

    /// Takes smddb's record of an opened container in, as an edit draft based on the library's sidecar.
    func takeSmddbRecord(of key: ContainerKey) async {
        guard let silo = silos.first(where: { $0.id == key.silo }),
            case .differs(let record)? = standings[key]
        else { return }
        do {
            open(try await console.draft(fromSmddb: record, in: key.library, of: silo), for: silo)
        } catch {
            fail(error)
        }
    }

    /// Starts a new container with an id from smddb's client, as a draft opened in the editor.
    func makeNewContainer(
        _ type: ContainerType,
        titled title: String,
        at creating: ContainerDraft.Creating,
        in library: String,
        on silo: AdminConsole.Silo
    ) async {
        guard let database, let title = Title(title) else { return }
        do {
            let draft = try await console.newContainer(
                type,
                titled: title,
                in: library,
                at: creating,
                of: silo,
                from: database
            )
            newContainer = nil
            open(draft, for: silo)
        } catch {
            fail(error)
        }
    }

    /// Makes the reviewed new container: the parent's edit naming it first, when it has a parent. Made,
    /// the draft ends and the library's containers are read again; refused, the draft is kept.
    func make(_ draft: ContainerDraft, on silo: AdminConsole.Silo) async {
        do {
            switch try await console.create(draft, of: silo) {
            case .created:
                discardContainerDraft(for: silo)
                await loadContainers(for: silo)
                if let parent = draft.creating?.parent {
                    await open(ContainerKey(silo: silo.id, library: draft.library, container: parent))
                }
            case .parentRefused(let result):
                settle(.refused(result), of: draft.id)
            case .refused(let result):
                settle(
                    .refused(
                        SiloClient.ContainerEditResult(
                            applied: false,
                            sidecar: "",
                            digest: "",
                            findings: result.findings
                        )
                    ),
                    of: draft.id
                )
            }
        } catch {
            fail(error)
        }
    }

    /// Works out proposing an opened container to smddb, for the sheet to show before anything is written.
    func beginProposal(of key: ContainerKey) async {
        guard let database, let silo = silos.first(where: { $0.id == key.silo }) else { return }
        do {
            let plan = try await console.planExport(key.container, in: key.library, of: silo, to: database)
            proposing = Proposing(silo: silo, plan: plan, chosen: Set(plan.offered.map(\.id)))
        } catch {
            fail(error)
        }
    }

    /// Contributes the proposal to the clone, and says which files it wrote there.
    func propose() async {
        guard let database, let proposal = proposing else { return }
        do {
            guard
                case .written(let files) = try await console.export(
                    proposal.plan,
                    choosing: proposal.chosen,
                    to: database
                )
            else { return }
            proposing?.written = files
            await readClone()
        } catch let refused as ContributionError {
            proposing?.refusal = refused.localizedDescription
        } catch {
            proposing?.refusal = error.localizedDescription
        }
    }

    private func fail(_ error: any Error) {
        switch error {
        case let refused as AdminConsole.StoreRefused: refusal = .storeRefused(refused.reason)
        case let refused as AdminConsole.SettingsRefused: refusal = .settingsRefused(refused.reason)
        case is AdminConsole.NoAccess: refusal = .noAccess
        default: refusal = .unreachable
        }
    }
}
#endif
