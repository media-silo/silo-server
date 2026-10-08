// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloKit

/// The latest check of each placed presentation, one JSON file each under `<state>/checks`, by the
/// id of the job that placed it. Each check replaces the last: the record is what the rules in
/// force were found to decide, not a history.
public struct CheckStore: Sendable {
    private let folder: RecordFolder<CheckRecord>

    public init(folder: URL) throws {
        self.folder = try RecordFolder(folder: folder, id: \.job)
    }

    /// In memory only, for tests.
    public init() {
        folder = RecordFolder(id: \.job)
    }

    public func check(of job: String) -> CheckRecord? { folder.record(job) }

    public var all: [CheckRecord] { folder.all }

    /// Records a check, in place of the job's last.
    public func record(_ check: CheckRecord) throws {
        if folder.record(check.job) != nil {
            _ = try folder.update(check.job) { (existing: inout CheckRecord) throws -> Void in existing = check }
        } else {
            try folder.insert([check])
        }
    }
}
