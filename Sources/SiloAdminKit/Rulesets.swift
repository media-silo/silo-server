// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloClient
import SiloKit

/// What the console says of a ruleset, drawn from the silo's reading of it and never from its XML:
/// the reading is the silo's, and these only arrange it.
extension SiloClient.RulesetReading {
    /// The rules of each scope that has any, in document order within it: the order that decides
    /// between them, since the first rule of a scope whose conditions all hold decides a stream.
    public var byScope: [(scope: Scope, rules: [SiloClient.RuleReading])] {
        Scope.allCases.compactMap { scope in
            let rules = rules.filter { $0.scope == scope }
            return rules.isEmpty ? nil : (scope, rules)
        }
    }

    /// The scopes whose last rule has conditions: a stream that meets none of them is one no rule
    /// decides, and stops an application.
    public var scopesWithoutCatchAll: Set<Scope> {
        Set(byScope.compactMap { $0.rules.last?.conditions.isEmpty == false ? $0.scope : nil })
    }
}

extension SiloClient.ConditionReading {
    /// As the document writes it: `audio.channels ge 6`.
    public var text: String { "\(fact) \(test) \(value)" }
}

extension Action {
    /// What happens to the stream, in a few words: `copy`, `drop`, or `encode aac 96k 2ch`.
    public var summary: String {
        switch self {
        case .copy: "copy"
        case .drop: "drop"
        case .encode(let settings):
            (["encode", settings.codec] + [
                settings.preset, settings.crf.map { "crf \($0)" }, settings.bitrate,
                settings.channels.map { "\($0)ch" }, settings.pixelFormat,
            ].compactMap { $0 }).joined(separator: " ")
        }
    }
}

extension CheckedStack {
    /// The ruleset and every layer above it, nearest first: `household@1 + binding v2 + container v1`.
    public var summary: String {
        ([ruleset.description] + layers.map { layer in
            switch layer.subject {
            case .binding: "binding rules v\(layer.version)"
            case .container(let id): "\(id)'s rules v\(layer.version)"
            }
        }).joined(separator: " + ")
    }
}

extension SiloClient.OutOfDatePresentation {
    /// Whether every source of its binding has a copy some node holds, so that it can be made again.
    public var everySourceHasACopy: Bool {
        sources.allSatisfy { !$0.copies.isEmpty }
    }
}
