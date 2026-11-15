// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloKit
import Testing

@testable import SiloStore

/// A ruleset's standard and its branches: one sequence of versions, each knowing its branch and its
/// parent, and promotion as a fast-forward that loses nothing nobody looked at.
struct RulesetBranchTests {
    static func document(_ comment: String) -> Data {
        Data("<ruleset format=\"1\" name=\"household\"><!-- \(comment) --><video><copy/></video></ruleset>".utf8)
    }

    static func store() throws -> (RulesetStore, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("silo-branches-\(UUID().uuidString)")
        return (try RulesetStore(folder: folder), folder)
    }

    @Test func branchesShareTheSequenceAndEachVersionNamesItsParent() throws {
        let (store, folder) = try Self.store()
        defer { try? FileManager.default.removeItem(at: folder) }
        for n in 1...7 { try store.store(Self.document("standard \(n)"), as: "household", basedOn: n - 1) }
        #expect(try store.parent(of: "household", version: 2) == 1)

        let trial = try store.startBranch("trial", of: "household", from: 7)
        #expect(trial.head == 7 && trial.upToDateWith == 7, "a new branch's head is its base")
        #expect(try store.store(Self.document("on trial"), as: "household", branch: "trial", basedOn: 7).version == 8)
        #expect(
            try store.store(Self.document("standard 9"), as: "household", basedOn: 7).version == 9,
            "a store naming no branch is the standard's"
        )
        #expect(try store.branch(of: "household", version: 8) == "trial")
        #expect(try store.parent(of: "household", version: 8) == 7)
        #expect(try store.parent(of: "household", version: 9) == 7)
        #expect(try store.head(of: "household", branch: RulesetStore.standard) == 9)
        #expect(try store.head(of: "household", branch: "trial") == 8)
        #expect(try store.branches(of: "household").map(\.name) == ["standard", "trial"], "the standard first")

        #expect(throws: RulesetStoreError.branchExists(name: "household", branch: "trial")) {
            try store.startBranch("trial", of: "household", from: 7)
        }
        #expect(throws: RulesetStoreError.notOnStandard(name: "household", version: 8)) {
            try store.startBranch("other", of: "household", from: 8)
        }
        #expect(throws: RulesetStoreError.noSuchBranch(name: "household", branch: "nowhere")) {
            try store.store(Self.document("x"), as: "household", branch: "nowhere")
        }
    }

    @Test func theHeadsDocumentStoredAgainIsTheHead() throws {
        let (store, folder) = try Self.store()
        defer { try? FileManager.default.removeItem(at: folder) }
        try store.store(Self.document("standard 1"), as: "household")
        let first = try store.store(Self.document("standard 2"), as: "household", basedOn: 1)
        let again = try store.store(Self.document("standard 2"), as: "household", basedOn: 1)
        #expect(first == (2, true))
        #expect(again == (2, false), "a store sent again is the version the first made, whatever its base")
        #expect(try store.store(Self.document("standard 2"), as: "household") == (2, false), "or with none")
        #expect(try store.latestVersion(of: "household") == 2, "and stores nothing")

        #expect(throws: RulesetStoreError.noBase(name: "household", branch: RulesetStore.standard)) {
            try store.store(Self.document("standard 3"), as: "household")
        }
        #expect(try store.latestVersion(of: "household") == 2, "a store that does not say its base stores nothing")
        #expect(
            RulesetStoreError.noBase(name: "household", branch: RulesetStore.standard).description
                == "household has a version, so a store to its standard says the head it was made from as basedOn"
        )

        _ = try store.startBranch("trial", of: "household", from: 2)
        #expect(
            try store.store(Self.document("standard 2"), as: "household", branch: "trial") == (2, false),
            "a branch with no version of its own has its base as its head"
        )
        #expect(try store.head(of: "household", branch: "trial") == 2)
    }

    @Test func promotionIsAFastForwardRefusedOverWhatTheBranchHasNotTakenIn() throws {
        let (store, folder) = try Self.store()
        defer { try? FileManager.default.removeItem(at: folder) }
        for n in 1...7 { try store.store(Self.document("standard \(n)"), as: "household", basedOn: n - 1) }
        _ = try store.startBranch("trial", of: "household", from: 7)
        try store.store(Self.document("on trial"), as: "household", branch: "trial", basedOn: 7)
        try store.store(Self.document("standard 9"), as: "household", basedOn: 7)

        #expect(throws: RulesetStoreError.notTakenIn(name: "household", branch: "trial", versions: [9])) {
            try store.promote("trial", of: "household")
        }
        #expect(try store.latestVersion(of: "household") == 9, "nothing is stored")
        #expect(
            RulesetStoreError.notTakenIn(name: "household", branch: "trial", versions: [9]).description
                == "household's branch trial has not taken in household@9 from the standard"
        )

        let caughtUp = try store.store(
            Self.document("on trial, with 9"),
            as: "household",
            branch: "trial",
            upToDateWith: 9,
            basedOn: 8
        ).version
        let promoted = try store.promote("trial", of: "household")
        #expect(promoted == caughtUp + 1)
        #expect(
            try store.document(named: "household", version: promoted)?.data == Self.document("on trial, with 9"),
            "the head's document"
        )
        #expect(try store.branch(of: "household", version: promoted) == RulesetStore.standard)
        #expect(try store.parent(of: "household", version: promoted) == 9)
        #expect(try store.branches(of: "household").last?.closed == true)
        #expect(throws: RulesetStoreError.branchClosed(name: "household", branch: "trial")) {
            try store.store(Self.document("late"), as: "household", branch: "trial", basedOn: 10)
        }
        #expect(throws: RulesetStoreError.branchClosed(name: "household", branch: "trial")) {
            try store.promote("trial", of: "household")
        }
    }

    @Test func aStraightPromotionOverTheStandardsHead() throws {
        let (store, folder) = try Self.store()
        defer { try? FileManager.default.removeItem(at: folder) }
        for n in 1...7 { try store.store(Self.document("standard \(n)"), as: "household", basedOn: n - 1) }
        _ = try store.startBranch("trial", of: "household", from: 7)
        try store.store(Self.document("on trial"), as: "household", branch: "trial", basedOn: 7)
        #expect(try store.promote("trial", of: "household") == 9)
        #expect(try store.parent(of: "household", version: 9) == 7)
        #expect(try store.document(named: "household", version: 9)?.data == Self.document("on trial"))
    }
}
