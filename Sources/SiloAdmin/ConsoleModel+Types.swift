// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

#if canImport(SwiftUI)
import SwiftUI
import SiloAdminKit
import SiloClient
import SmdKit

extension ConsoleModel {
    struct Trying: Identifiable {
        let id = UUID()
        var silo: AdminConsole.Silo
        var ruleset: String
        var branch: String
        var version: Int
        var candidates: [AdminConsole.TrialCandidate]
        var chosen: Set<String> = []
    }

    /// A draft's review: its difference and impact before anything is stored, and, when another
    /// version landed first, that version, for the draft to be re-based on it or discarded.
    struct Review: Identifiable {
        let id = UUID()
        var silo: AdminConsole.Silo
        var draft: Draft
        var impact: [SiloClient.OutOfDatePresentation]
        var branches: [SiloClient.Branch]
        var landed: SiloClient.RulesetDocument?
    }

    /// A container in one library of one silo: what the browser and its cache are keyed by.
    struct ContainerKey: Hashable {
        var silo: AdminConsole.Silo.ID
        var library: String
        var container: String
    }

    /// A library, or a container in one, as the Libraries section's browser chooses it.
    enum Browsed: Hashable {
        case library(String)
        case container(ContainerKey)
    }

    /// A container draft's review: its difference from its base and the silo's findings before
    /// anything is stored; when another edit landed first, that sidecar and how it differs from the
    /// base, for the draft to be re-based on it or discarded.
    struct ContainerReview: Identifiable {
        let id = UUID()
        var silo: AdminConsole.Silo
        var draft: ContainerDraft
        var check: AdminConsole.ContainerCheck?
        var landed: AdminConsole.OpenedContainer?
        /// Why storing it failed, said in the review, since an alert cannot show over a sheet.
        var failure: String?
    }

    /// What the console holds of TMDb between reads: the language it answers in, why it cannot be
    /// asked when it cannot, and the sheets open over it.
    struct TMDbState {
        var language = "en-US"
        var problem: String?
        var finding: FindingInTMDb?
        var shaping: ShapingTree?
        var walking: Walking?
        /// The readings of the walk's stops, by stop, cancelled when its sheet closes.
        var readings: [String: Task<Void, Never>] = [:]
        /// The reading of the series' specials, for a walk rooted below the series.
        var pooling: Task<Void, Never>?
    }

    /// A held tree being walked against TMDb: the walk as it stands, the stop open, each stop's reading
    /// as it goes and why one failed, and the store's list and how storing it ended.
    struct Walking: Identifiable {
        let id = UUID()
        var silo: AdminConsole.Silo
        var walk: TMDbWalk
        var open: String
        /// A walk this Mac kept, offered to be resumed or started again before anything is read.
        var resuming = false
        var progress: [String: AdminConsole.TMDbProgress] = [:]
        var failures: [String: String] = [:]
        /// The step the series' specials are on while they are read through the series above the root.
        var pooling: AdminConsole.TMDbProgress?
        /// The series the library holds that a special may go into as its companion.
        var companions: [SiloClient.ContainerSummary] = []
        /// The new stops confirming the open stop would take out of the walk, said before it does.
        var leaving: [String]?
        /// Everything storing the walk will do, listed before any of it is done.
        var plan: TMDbWalk.Plan?
        var storing = false
        var stored: AdminConsole.TMDbWalkStored?
        var failure: String?

        var stop: TMDbWalk.Stop? { walk.stops[open] }
    }

    /// A record being found at TMDb: for a library, to draft from; or, for a series the library holds by
    /// its TMDb reference, one of its seasons to draft beneath it.
    struct FindingInTMDb: Identifiable {
        let id = UUID()
        var silo: AdminConsole.Silo
        var library: String
        /// The held series, and its TMDb number, for a season.
        var series: (container: String, title: String, tmdb: Int)?
    }

    /// A draft from TMDb being shaped before it is made: the tree as last kept, what each special is
    /// suggested for, the silo's dry run, and how making it ended.
    struct ShapingTree: Identifiable {
        var silo: AdminConsole.Silo
        var tree: TMDbTree
        var suggestions: [Int: AdminConsole.SpecialSuggestion] = [:]
        /// The step the specials' suggestions are on while they are read.
        var suggesting: AdminConsole.TMDbProgress?
        /// The series the library holds that a special may go into as a breakout.
        var companions: [SiloClient.ContainerSummary] = []
        var check: AdminConsole.ContainerCheck?
        var outcome: AdminConsole.TMDbCreateOutcome?
        var failure: String?

        var id: TMDbTree.ID { tree.id }
    }

    /// An import from smddb into a library being chosen.
    struct Importing: Identifiable {
        let id = UUID()
        var silo: AdminConsole.Silo
        var library: String
    }

    /// A new container being named: in a library, at its top or beneath a container it holds, whose
    /// sequences it may be placed in.
    struct NewContainer: Identifiable {
        let id = UUID()
        var silo: AdminConsole.Silo
        var library: String
        var parent: String?
        var parentTitle: String?
        var sequences: [String]
    }

    /// A library's container being proposed to smddb: what would be offered, which of the containers
    /// it names go with it, and, once offered, the files written or why smddb refused it.
    struct Proposing: Identifiable {
        let id = UUID()
        var silo: AdminConsole.Silo
        var plan: AdminConsole.ExportPlan
        var chosen: Set<ContainerID>
        var written: [URL]?
        var refusal: String?
    }

    /// A branch's promotion: what it would put out of date, and, once refused, what it has not taken in.
    struct Promotion: Identifiable {
        let id = UUID()
        var silo: AdminConsole.Silo
        var ruleset: String
        var branch: String
        var impact: [SiloClient.OutOfDatePresentation]
        var refused: AdminConsole.PromotionRefused?
    }

    enum DraftView: String, CaseIterable, Identifiable {
        case form = "Form"
        case text = "Text"

        var id: String { rawValue }
    }

    enum DetailSection: String, CaseIterable, Identifiable {
        case settings = "Settings"
        case libraries = "Libraries"
        case rulesets = "Rulesets"
        case outOfDate = "Out of Date"

        var id: String { rawValue }
    }

    /// The endings an operator has to be told in words: someone else's stage runs out at a
    /// clock time, someone else finished, the silo could not be asked at all, or it refused a
    /// settings change or the passkey the change was asked with.
    enum Refusal {
        case stagedElsewhere(until: Date)
        case noLongerInBootstrap
        case unreachable
        case settingsRefused(String)
        case storeRefused(String)
        case noAccess

        var title: String {
            switch self {
            case .stagedElsewhere: "Setup Staged Elsewhere"
            case .noLongerInBootstrap: "Someone Finished First"
            case .unreachable: "The Silo Could Not Be Reached"
            case .settingsRefused: "The Silo Refused the Change"
            case .storeRefused: "The Silo Refused the Store"
            case .noAccess: "No Access"
            }
        }

        var message: String {
            switch self {
            case .stagedElsewhere(let until):
                "Another console has a setup staged on this silo. Its window runs out at \(until.formatted(date: .omitted, time: .shortened)) — try again after that."
            case .noLongerInBootstrap:
                "This silo's setup was already confirmed. It now shows as what its probe says."
            case .unreachable:
                "No reply; the row keeps its last-known state. Try again when the silo answers."
            case .settingsRefused(let reason):
                "Nothing was changed: \(reason)."
            case .storeRefused(let reason):
                "Nothing was stored, and the draft is kept: \(reason)."
            case .noAccess:
                "The silo no longer accepts the passkey this Mac holds for it, so its settings cannot be changed from here."
            }
        }
    }

    /// How a claim ended; only `refused` keeps the sheet up, so a mistyped group can be fixed.
    enum ClaimOutcome {
        case claimed
        case refused
        case failed
    }
}
#endif
