// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Crypto
import Foundation
import SiloKit
import SmdSidecar

/// A container's or a binding's rules as the library holds them: a folder of version files beside a
/// sidecar, named by a `<rules path activeVersion>`. Read here with the digest a recipe records, so
/// that the rules a recipe was resolved through can be found, and checked, after the version in
/// force has moved on. `LayeredRulesets.md`, *A container's rules*.
public enum RulesLayerFile {
    /// The version in force of the rules `reference` names, read from beside the sidecar in `folder`.
    public static func read(_ subject: LayerSubject, _ reference: SidecarRules, in folder: URL) throws(RulesLayerError) -> RulesLayer {
        try read(subject, version: reference.activeVersion, file: folder.appendingPathComponent(reference.activeFile))
    }

    /// One version's file, whichever is in force.
    public static func read(_ subject: LayerSubject, version: Int, file: URL) throws(RulesLayerError) -> RulesLayer {
        guard let data = try? Data(contentsOf: file) else {
            throw RulesLayerError(subject: subject, version: version, reason: "rules version \(version) is not there")
        }
        do {
            return RulesLayer(subject: subject, version: version, digest: digest(of: data), rules: try RulesetFile.layerRules(from: data))
        } catch {
            throw RulesLayerError(subject: subject, version: version, reason: "rules version \(version): \(error)")
        }
    }

    /// `sha256:` and the hex of the file's bytes, as a `<layer digest>` spells it.
    public static func digest(of data: Data) -> String {
        "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// A layer that cannot be read: its version file is not there, or its rules are refused.
public struct RulesLayerError: Error, Hashable, Sendable, CustomStringConvertible {
    public var subject: LayerSubject
    public var version: Int
    public var reason: String

    public init(subject: LayerSubject, version: Int, reason: String) {
        self.subject = subject
        self.version = version
        self.reason = reason
    }

    public var description: String {
        "the rules of \(subject): \(reason)"
    }
}
