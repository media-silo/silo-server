// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

/// A BCP 47 language tag (RFC 5646), held in its canonical form: the primary language as the
/// shortest ISO 639 code for it, a script in title case, a region in capitals, and anything after —
/// variants, extensions, private use — in lower case. `en`, `en-GB`, `es-419`, `zh-Hant`, `yue`.
///
/// Parsing accepts a well-formed tag in any case, and a primary language given by its ISO 639-2
/// code, terminological or bibliographic, and answers the canonical tag: `ENG` and `eng-gb` read as
/// `en` and `en-GB`, `fre` as `fr`. An input spec then insists its tags are already canonical, so a
/// producer's mistakes are refused rather than quietly mended; the plain-file producer, which reads
/// whatever a file was tagged with, is the caller that canonicalises.
///
/// Extended language subtags (`zh-yue`) are not read: BCP 47's canonical form writes the language on
/// its own (`yue`), and a tag that needs one is the rare case a producer can spell directly.
public struct LanguageTag: Hashable, Sendable, CustomStringConvertible {
    /// The primary language subtag, as the shortest ISO 639 code: `en`, `fr`, `yue`.
    public let language: String
    /// The script subtag, in title case: `Latn`, `Hant`.
    public let script: String?
    /// The region subtag, in capitals or digits: `GB`, `BR`, `419`.
    public let region: String?
    /// Variants, extensions and private use, in lower case, in order.
    public let rest: [String]

    public var description: String {
        ([language] + [script, region].compactMap { $0 } + rest).joined(separator: "-")
    }

    /// The canonical form of `text`, or nil when it is not a well-formed tag this reads.
    public init?(canonicalizing text: String) {
        let subtags = text.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard !subtags.isEmpty, subtags.allSatisfy({ (1...8).contains($0.count) && $0.allSatisfy(\.isASCIIAlphanumeric) }) else {
            return nil
        }
        var position = 0
        func next() -> String? { position < subtags.count ? subtags[position] : nil }

        guard let first = next(), (2...3).contains(first.count), first.allSatisfy(\.isASCIILetter) else { return nil }
        let lowered = first.lowercased()
        language = ISO639.twoLetterCode[lowered] ?? lowered
        position += 1

        if let subtag = next(), subtag.count == 4, subtag.allSatisfy(\.isASCIILetter) {
            script = subtag.prefix(1).uppercased() + subtag.dropFirst().lowercased()
            position += 1
        } else {
            script = nil
        }

        if let subtag = next(),
           (subtag.count == 2 && subtag.allSatisfy(\.isASCIILetter)) || (subtag.count == 3 && subtag.allSatisfy(\.isASCIIDigit)) {
            region = subtag.uppercased()
            position += 1
        } else {
            region = nil
        }

        var rest: [String] = []
        // Variants: five to eight characters, or four starting with a digit.
        while let subtag = next(), (5...8).contains(subtag.count) || (subtag.count == 4 && subtag.first!.isASCIIDigit) {
            rest.append(subtag.lowercased())
            position += 1
        }
        // Extensions — a singleton other than `x` and one or more subtags of two to eight — then
        // private use: `x` and one or more subtags of one to eight.
        while let singleton = next(), singleton.count == 1 {
            let isPrivateUse = singleton.lowercased() == "x"
            rest.append(singleton.lowercased())
            position += 1
            var taken = 0
            while let subtag = next(), isPrivateUse || subtag.count >= 2 {
                if !isPrivateUse && subtag.count == 1 { break }
                rest.append(subtag.lowercased())
                position += 1
                taken += 1
            }
            guard taken > 0 else { return nil }
            if isPrivateUse { break }
        }
        guard position == subtags.count else { return nil }
        self.rest = rest
    }
}

extension Character {
    fileprivate var isASCIILetter: Bool { isASCII && isLetter }
    fileprivate var isASCIIDigit: Bool { isASCII && isNumber }
    fileprivate var isASCIIAlphanumeric: Bool { isASCIILetter || isASCIIDigit }
}
