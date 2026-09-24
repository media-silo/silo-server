// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation

/// The operator passkey as the console mints it: twenty-five lowercase letters and digits from
/// a 36-symbol alphabet — a shade over 128 bits — grouped in fives so a human can read it aloud
/// and type it. Lowercase only, because a transcription that teaches case sensitivity is a
/// transcription that fails; the hyphens are part of the passkey, stored and staged with it, so
/// what the operator files away is exactly the string the silo's hash ever sees.
public enum Passkey {
    private static let symbols = Array("0123456789abcdefghijklmnopqrstuvwxyz")
    private static let length = 25
    private static let group = 5

    public static func mint() -> String {
        var generator = SystemRandomNumberGenerator()
        return mint(using: &generator)
    }

    public static func mint<G: RandomNumberGenerator>(using generator: inout G) -> String {
        let characters = (0..<length).map { _ in symbols.randomElement(using: &generator)! }
        var passkey = ""
        for (index, character) in characters.enumerated() {
            if index > 0, index % group == 0 { passkey += "-" }
            passkey.append(character)
        }
        return passkey
    }
}
