// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation

/// Whose rules a layer is: a container's, by its id, or a binding's, by its id. The ruleset applied
/// is the stack's last layer and is named by the recipe itself. `LayeredRulesets.md`, *Layers*.
public enum LayerSubject: Hashable, Sendable {
    case container(String)
    case binding(String)

    public var id: String {
        switch self {
        case .container(let id), .binding(let id): id
        }
    }
}

extension LayerSubject: CustomStringConvertible {
    public var description: String {
        switch self {
        case .container(let id): "container \(id)"
        case .binding(let id): "binding \(id)"
        }
    }
}

/// One layer of a stack above the ruleset, read and ready to resolve through: whose it is, the
/// version in force when it was read, the digest of that version's file, and its rules.
public struct RulesLayer: Hashable, Sendable {
    public var subject: LayerSubject
    public var version: Int
    public var digest: String
    public var rules: [Rule]

    public init(subject: LayerSubject, version: Int, digest: String, rules: [Rule]) {
        self.subject = subject
        self.version = version
        self.digest = digest
        self.rules = rules
    }

    /// What a recipe records of it: enough to find, and check, the rules again.
    public var reference: RecipeLayer {
        RecipeLayer(subject: subject, version: version, digest: digest)
    }
}

/// A layer as a recipe records it, nearest first: whose, which version, and that version's digest.
/// Spelt in JSON as the `.smd`'s `<layer>` is: `{"container": "…", "version": 4, "digest": "…"}`.
public struct RecipeLayer: Hashable, Sendable, Codable {
    public var subject: LayerSubject
    public var version: Int
    public var digest: String

    public init(subject: LayerSubject, version: Int, digest: String) {
        self.subject = subject
        self.version = version
        self.digest = digest
    }

    fileprivate enum CodingKeys: String, CodingKey, SubjectKeys {
        case container, binding, version, digest
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        subject = try LayerSubject(decodingFrom: values)
        version = try values.decode(Int.self, forKey: .version)
        digest = try values.decode(String.self, forKey: .digest)
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try subject.encode(into: &values)
        try values.encode(version, forKey: .version)
        try values.encode(digest, forKey: .digest)
    }
}

/// The layer a decision's rule came from: the ruleset applied, by name, or a container's or a
/// binding's rules, by id. Spelt in JSON as one key: `{"ruleset": "household"}`.
public enum DecisionLayer: Hashable, Sendable, Codable {
    case ruleset(String)
    case layer(LayerSubject)

    fileprivate enum CodingKeys: String, CodingKey, SubjectKeys {
        case ruleset, container, binding
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let name = try values.decodeIfPresent(String.self, forKey: .ruleset) {
            self = .ruleset(name)
        } else {
            self = .layer(try LayerSubject(decodingFrom: values))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .ruleset(let name): try values.encode(name, forKey: .ruleset)
        case .layer(let subject): try subject.encode(into: &values)
        }
    }
}

fileprivate protocol SubjectKeys: CodingKey {
    static var container: Self { get }
    static var binding: Self { get }
}

extension LayerSubject {
    fileprivate init<Keys: SubjectKeys>(decodingFrom values: KeyedDecodingContainer<Keys>) throws {
        switch (try values.decodeIfPresent(String.self, forKey: .container), try values.decodeIfPresent(String.self, forKey: .binding)) {
        case (let container?, nil): self = .container(container)
        case (nil, let binding?): self = .binding(binding)
        default:
            throw DecodingError.dataCorruptedError(forKey: Keys.container, in: values, debugDescription: "a layer names exactly one of a container and a binding")
        }
    }

    fileprivate func encode<Keys: SubjectKeys>(into values: inout KeyedEncodingContainer<Keys>) throws {
        switch self {
        case .container(let id): try values.encode(id, forKey: .container)
        case .binding(let id): try values.encode(id, forKey: .binding)
        }
    }
}
