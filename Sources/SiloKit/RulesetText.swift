// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation

/// A ruleset's document as the text a person wrote, with where in it each rule and each output
/// lies: what lets a form edit the document element by element. Every edit is a splice — the
/// characters of the elements it touches replaced, and nothing else — so comments, blank lines,
/// attribute order and quoting outside them stay exactly as written. A document the reader refuses
/// has no `RulesetText`, and so offers no edit.
public struct RulesetText: Sendable {
    /// One rule or output, by where it lies in the text, as UTF-8 offsets.
    public struct Element: Hashable, Sendable {
        public enum Kind: Hashable, Sendable {
            case rule(Scope)
            case output
        }

        public var kind: Kind
        /// The element itself, from its `<` to its last `>`.
        public var range: Range<Int>
        /// What goes with the element when it moves or is deleted: the comments immediately before
        /// it, and, when it stands on lines of its own, those whole lines.
        public var unit: Range<Int>
        /// The whitespace its line starts with, when it starts a line of its own.
        public var indentation: String?
    }

    public let text: String
    /// The document as the reader reads it.
    public let ruleset: Ruleset
    /// Every rule and output, in document order.
    public let elements: [Element]
    private let bytes: [UInt8]
    /// Where an element added after every other goes, and whether it opens a line there.
    private let end: Int
    private let endOpensLine: Bool

    /// Reads the text, refusing it in the reader's words when the reader refuses it.
    public init(_ text: String) throws {
        ruleset = try RulesetFile.ruleset(from: Data(text.utf8))
        self.text = text
        bytes = Array(text.utf8)
        var scanner = Scanner(bytes)
        let scanned = scanner.scan()
        elements = scanned.elements
        end = scanned.end
        endOpensLine = scanned.endOpensLine
        guard elements.count == ruleset.rules.count + ruleset.outputs.count else {
            throw RulesetFileError.malformed("the document could not be laid out element by element")
        }
    }

    // MARK: - What the document holds

    /// The rules, in document order, each with where it lies.
    public var rules: [(rule: Rule, element: Element)] {
        Array(zip(ruleset.rules, elements.filter { if case .rule = $0.kind { true } else { false } }))
    }

    /// The outputs, in document order, each with where it lies.
    public var outputs: [(output: OutputPolicy, element: Element)] {
        Array(zip(ruleset.outputs, elements.filter { $0.kind == .output }))
    }

    /// One scope's rules, in the order that decides between them.
    public func rules(of scope: Scope) -> [(rule: Rule, element: Element)] {
        rules.filter { $0.rule.scope == scope }
    }

    // MARK: - Edits

    /// The text with one scope's rule, by its position within the scope, replaced.
    public func replacingRule(_ position: Int, of scope: Scope, with rule: Rule) -> String {
        splice(rules(of: scope)[position].element.range, with: RulesetFile.element(for: rule))
    }

    /// The text with a rule added after the scope's last rule — or, for a scope with none, before
    /// the first output, or after every element.
    public func addingRule(_ rule: Rule) -> String {
        let xml = RulesetFile.element(for: rule)
        if let last = rules(of: rule.scope).last {
            return inserting(xml, after: last.element)
        }
        if let output = outputs.first {
            return inserting(xml, before: output.element)
        }
        return inserting(xml, before: nil)
    }

    /// The text with one scope's rule deleted, its comments with it.
    public func deletingRule(_ position: Int, of scope: Scope) -> String {
        splice(rules(of: scope)[position].element.unit, with: "")
    }

    /// The text with one scope's rule moved, its comments with it, to `destination` among the
    /// scope's rules: the position it is put before, counted before the move, or the scope's count
    /// for after its last rule.
    public func movingRule(_ position: Int, of scope: Scope, to destination: Int) -> String {
        let scoped = rules(of: scope)
        guard destination != position, destination != position + 1 else { return text }
        let moving = scoped[position].element
        let target: Element? = if destination < scoped.count {
            scoped[destination].element
        } else {
            elements.first { $0.range.lowerBound > scoped[scoped.count - 1].element.range.lowerBound && $0 != moving }
        }
        let piece = bytes[moving.unit]
        var moved = bytes
        let at = target?.unit.lowerBound ?? end
        // Put in first when it goes later in the text, so that the cut's offsets still hold.
        if at > moving.unit.lowerBound {
            moved.insert(contentsOf: piece, at: at)
            moved.removeSubrange(moving.unit)
        } else {
            moved.removeSubrange(moving.unit)
            moved.insert(contentsOf: piece, at: at)
        }
        return String(decoding: moved, as: UTF8.self)
    }

    /// The text with an output, by its position among the outputs, replaced.
    public func replacingOutput(_ position: Int, with output: OutputPolicy) -> String {
        splice(outputs[position].element.range, with: RulesetFile.element(for: output))
    }

    /// The text with an output added after the last.
    public func addingOutput(_ output: OutputPolicy) -> String {
        let xml = RulesetFile.element(for: output)
        if let last = outputs.last { return inserting(xml, after: last.element) }
        return inserting(xml, before: nil)
    }

    /// The text with an output deleted, its comments with it.
    public func deletingOutput(_ position: Int) -> String {
        splice(outputs[position].element.unit, with: "")
    }

    // MARK: - Splicing

    private func splice(_ range: Range<Int>, with replacement: String) -> String {
        var spliced = bytes
        spliced.replaceSubrange(range, with: Array(replacement.utf8))
        return String(decoding: spliced, as: UTF8.self)
    }

    /// The text with a new element written before another, or after every element, in the
    /// indentation of its neighbours, on a line of its own when they stand on lines of their own.
    private func inserting(_ xml: String, before element: Element?) -> String {
        let neighbour = element ?? elements.last
        if let element {
            guard let indentation = element.indentation else {
                return splice(element.unit.lowerBound..<element.unit.lowerBound, with: xml)
            }
            return splice(element.unit.lowerBound..<element.unit.lowerBound, with: indentation + xml + "\n")
        }
        guard endOpensLine else { return splice(end..<end, with: xml) }
        return splice(end..<end, with: (neighbour?.indentation ?? "  ") + xml + "\n")
    }

    /// The text with a new element written straight after another.
    private func inserting(_ xml: String, after element: Element) -> String {
        guard let indentation = element.indentation, element.unit.upperBound > element.range.upperBound else {
            return splice(element.range.upperBound..<element.range.upperBound, with: xml)
        }
        return splice(element.unit.upperBound..<element.unit.upperBound, with: indentation + xml + "\n")
    }

    // MARK: - Scanning

    /// A pass over a document the reader has read, so well formed: the root's children, each with
    /// its extent, and the comments that belong to it.
    private struct Scanner {
        let bytes: [UInt8]
        var at = 0

        init(_ bytes: [UInt8]) { self.bytes = bytes }

        mutating func scan() -> (elements: [Element], end: Int, endOpensLine: Bool) {
            // The prolog, then the root's start tag.
            while at < bytes.count {
                if starts("<?") { skip(past: "?>") } else if starts("<!--") { skip(past: "-->") } else if starts("<!") { skip(past: ">") } else if bytes[at] == UInt8(ascii: "<") { break } else { at += 1 }
            }
            let rootSelfCloses = tag()
            var elements: [Element] = []
            guard !rootSelfCloses else { return ([], at, false) }

            var pending: Int?
            while at < bytes.count {
                if starts("</") {
                    let line = lineStart(at)
                    return (elements, line ?? at, line != nil)
                } else if starts("<!--") {
                    if pending == nil { pending = at }
                    skip(past: "-->")
                } else if starts("<?") {
                    skip(past: "?>")
                } else if starts("<![CDATA[") {
                    skip(past: "]]>")
                } else if bytes[at] == UInt8(ascii: "<") {
                    let start = at
                    let name = self.name(at + 1)
                    element()
                    let finish = at
                    var unitStart = pending ?? start
                    pending = nil
                    let indentation = lineStart(start).map { String(decoding: bytes[$0..<start], as: UTF8.self) }
                    if let line = lineStart(unitStart) { unitStart = line }
                    var unitEnd = finish
                    var probe = finish
                    while probe < bytes.count, bytes[probe] == UInt8(ascii: " ") || bytes[probe] == UInt8(ascii: "\t") { probe += 1 }
                    if probe < bytes.count, bytes[probe] == UInt8(ascii: "\n") { unitEnd = probe + 1 }
                    let kind: Element.Kind = name == "output" ? .output : .rule(Scope(rawValue: name) ?? .video)
                    elements.append(Element(kind: kind, range: start..<finish, unit: unitStart..<unitEnd, indentation: indentation))
                } else {
                    // Whitespace, or text the reader ignores: a blank line parts a comment from what follows.
                    if bytes[at] == UInt8(ascii: "\n"), pending != nil {
                        var probe = at + 1
                        while probe < bytes.count, bytes[probe] == UInt8(ascii: " ") || bytes[probe] == UInt8(ascii: "\t") || bytes[probe] == UInt8(ascii: "\r") { probe += 1 }
                        if probe < bytes.count, bytes[probe] == UInt8(ascii: "\n") { pending = nil }
                    } else if !isSpace(bytes[at]) {
                        pending = nil
                    }
                    at += 1
                }
            }
            return (elements, bytes.count, false)
        }

        /// The start of the line holding `offset`, when only spaces and tabs come before it there.
        func lineStart(_ offset: Int) -> Int? {
            var probe = offset
            while probe > 0 {
                let byte = bytes[probe - 1]
                if byte == UInt8(ascii: "\n") { return probe }
                guard byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t") else { return nil }
                probe -= 1
            }
            return 0
        }

        func isSpace(_ byte: UInt8) -> Bool {
            byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t") || byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r")
        }

        func starts(_ prefix: String) -> Bool {
            let prefix = Array(prefix.utf8)
            return at + prefix.count <= bytes.count && Array(bytes[at..<at + prefix.count]) == prefix
        }

        mutating func skip(past terminator: String) {
            let terminator = Array(terminator.utf8)
            while at < bytes.count {
                if at + terminator.count <= bytes.count, Array(bytes[at..<at + terminator.count]) == terminator {
                    at += terminator.count
                    return
                }
                at += 1
            }
        }

        func name(_ offset: Int) -> String {
            var probe = offset
            while probe < bytes.count, !isSpace(bytes[probe]), bytes[probe] != UInt8(ascii: ">"), bytes[probe] != UInt8(ascii: "/") { probe += 1 }
            return String(decoding: bytes[offset..<probe], as: UTF8.self)
        }

        /// Past one tag, its quoted values respected; whether it closed itself.
        mutating func tag() -> Bool {
            var quote: UInt8?
            while at < bytes.count {
                let byte = bytes[at]
                if let open = quote {
                    if byte == open { quote = nil }
                } else if byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "'") {
                    quote = byte
                } else if byte == UInt8(ascii: ">") {
                    at += 1
                    return bytes[at - 2] == UInt8(ascii: "/")
                }
                at += 1
            }
            return false
        }

        /// Past one element, whatever it holds.
        mutating func element() {
            guard !tag() else { return }
            var depth = 1
            while at < bytes.count, depth > 0 {
                if starts("<!--") {
                    skip(past: "-->")
                } else if starts("<![CDATA[") {
                    skip(past: "]]>")
                } else if starts("<?") {
                    skip(past: "?>")
                } else if starts("</") {
                    _ = tag()
                    depth -= 1
                } else if bytes[at] == UInt8(ascii: "<") {
                    if !tag() { depth += 1 }
                } else {
                    at += 1
                }
            }
        }
    }
}
