// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation

/// A file as it physically is, registered once with the input spec its producer described it by,
/// however many entries are later made from it. The silo mints the id: a producer cannot be relied
/// on to identify a file as another would, and the silo cannot hash a file it does not hold.
public struct Source: Hashable, Sendable, Codable {
    /// A lowercased UUID, minted by the silo.
    public var id: String
    public var input: InputSpec
    /// How a producer can identify the source independently of the silo, when one can.
    public var key: NaturalKey?
    /// The nodes holding the file, each by the reference it serves it by. Possibly none.
    public var copies: [FileRef]
    public var createdAt: Date

    public init(id: String = UUID().uuidString.lowercased(), input: InputSpec, key: NaturalKey? = nil, copies: [FileRef] = [], createdAt: Date = .now) {
        self.id = id
        self.input = input
        self.key = key
        self.copies = copies
        self.createdAt = createdAt
    }

    /// Adds a copy, replacing the one its node already held: a node holds a source's file once.
    public mutating func hold(_ copy: FileRef) {
        copies.removeAll { $0.holder == copy.holder }
        copies.append(copy)
    }
}

/// An identity a producer can compute for a source without the silo — a disc title, a content
/// hash, an IMF composition's UUID — by which registering the same source twice finds the first.
public struct NaturalKey: Hashable, Sendable, Codable, CustomStringConvertible {
    public var scheme: String
    public var value: String

    public init(scheme: String, value: String) {
        self.scheme = scheme
        self.value = value
    }

    public var description: String { "\(scheme):\(value)" }
}
