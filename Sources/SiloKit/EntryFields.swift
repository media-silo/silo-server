// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import SmdKit

/// The fields the silo reads of an entry whatever its kind, as SmdKit's `Entry` keeps them per case:
/// nil where the kind has no such field.
extension Entry {
    public var title: String? {
        switch self {
        case .leaf(let leaf): leaf.title
        case .child(let child): child.title
        case .ref: nil
        }
    }

    public var outline: String? {
        switch self {
        case .leaf(let leaf): leaf.outline
        case .child(let child): child.outline
        case .ref: nil
        }
    }

    /// A leaf's type; nil for a child container or a ref.
    public var type: EntryType? {
        if case .leaf(let leaf) = self { leaf.type } else { nil }
    }

    public var optional: Bool {
        switch self {
        case .leaf(let leaf): leaf.optional
        case .child(let child): child.optional
        case .ref: false
        }
    }

    public var externalRefs: [ExternalRef] {
        switch self {
        case .leaf(let leaf): leaf.externalRefs
        case .child(let child): child.externalRefs
        case .ref: []
        }
    }

    /// The container a child entry names.
    public var childContainer: ContainerID? {
        if case .child(let child) = self { child.container } else { nil }
    }

    public var reference: EntryRef? {
        if case .ref(let ref) = self { ref } else { nil }
    }
}
