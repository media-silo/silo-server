// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

#if canImport(SwiftUI)
import SwiftUI
import SiloAdminKit
import SiloClient

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
