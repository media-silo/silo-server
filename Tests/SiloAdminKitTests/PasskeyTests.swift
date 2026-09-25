// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloAdminKit
import Testing

/// The minted passkey: 25 letters and digits in fives, which is 25 × log2(36) ≈ 129 bits —
/// comfortably the 128 the proposal asks for — in an alphabet a human can transcribe without
/// a case mistake.
@Suite(.serialized)
struct PasskeyTests {
    /// A draw of 36, not 0: the stdlib's unbiased rejection sampling rerolls a draw of 0 as
    /// unfair for a 36-symbol alphabet, so a degenerate zero RNG never yields a symbol.
    private struct Fixed: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 { state }
    }

    @Test func theMintIs128BitsOfLettersAndDigits() {
        let minted = Passkey.mint()

        let groups = minted.split(separator: "-")
        #expect(groups.count == 5)
        #expect(groups.allSatisfy { $0.count == 5 && $0.allSatisfy { $0.isNumber || ($0.isLetter && $0.isLowercase) } })

        #expect(Passkey.mint() != Passkey.mint(), "two mints differ")
    }

    @Test func theGroupingFollowsTheAlphabet() {
        var zeroes = Fixed(state: 36)
        #expect(Passkey.mint(using: &zeroes) == "00000-00000-00000-00000-00000", "the alphabet's first symbol, grouped in fives")
    }
}
