// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import Synchronization

/// Where passkeys live once minted or claimed: one seam, two keepers — the Keychain where one
/// exists, memory otherwise and in tests. Read and written synchronously; the quantities are a
/// string at a time and none of it takes longer than a keychain call.
public protocol PasskeyStore: Sendable {
    func passkey(for serverID: String) -> String?
    func store(_ passkey: String, for serverID: String)
    /// Removes the stored passkey, if any — forgetting a silo means this Mac no longer holds it.
    func remove(for serverID: String)
}

/// The in-memory keeper: the tests' Keychain, and the fallback where no Keychain exists.
public final class InMemoryPasskeyStore: PasskeyStore, Sendable {
    private let passkeys: Mutex<[String: String]>

    public init() {
        passkeys = Mutex([:])
    }

    public func passkey(for serverID: String) -> String? {
        passkeys.withLock { $0[serverID] }
    }

    public func store(_ passkey: String, for serverID: String) {
        passkeys.withLock { $0[serverID] = passkey }
    }

    public func remove(for serverID: String) {
        passkeys.withLock { $0[serverID] = nil }
    }
}

#if canImport(Security)
import Security

/// The Keychain's keeper: generic passwords under the console's service, keyed by ServerID —
/// the one place a passkey is allowed to outlive the app it was minted in.
public struct KeychainPasskeyStore: PasskeyStore {
    private let service = "media-silo.siloadmin"

    public init() {}

    public func passkey(for serverID: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: serverID,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    public func store(_ passkey: String, for serverID: String) {
        let data = Data(passkey.utf8)
        let key: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: serverID,
        ]
        if SecItemAdd((key.merging([kSecValueData: data]) { _, new in new }) as CFDictionary, nil) == errSecDuplicateItem {
            SecItemUpdate(key as CFDictionary, [kSecValueData: data] as CFDictionary)
        }
    }

    public func remove(for serverID: String) {
        let key: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: serverID,
        ]
        SecItemDelete(key as CFDictionary)
    }
}
#endif
