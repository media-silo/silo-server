// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation

/// Who this silo is: the id it minted once, kept in `silo.json` in the state directory. No route
/// re-mints it, and the operator changing the state directory's contents is the supported way to
/// make a new server. The name is not part of the identity: it is a setting, in `settings.json`,
/// that setup and the settings route change without touching the id.
public struct ServerIdentity: Hashable, Sendable {
    public var id: String

    public init(id: String) {
        self.id = id
    }
}
