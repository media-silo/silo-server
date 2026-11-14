// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation

#if canImport(FoundationXML)
import FoundationXML
#endif

/// A ruleset as a file: XML, rooted at `<ruleset>`, hand-edited beside the `.smd` files it
/// decides for and spelled the way they are spelled. A rule is an element named for its scope,
/// its conditions are `<when>` children and its action is the one remaining child.
///
/// ```xml
/// <ruleset format="1" name="household" version="7">
///   <audio id="commentary">
///     <when fact="audio.role" is="commentary"/>
///     <encode codec="aac" bitrate="160k" channels="2"/>
///   </audio>
///   <audio><copy/></audio>
///   <output container="mkv"/>
/// </ruleset>
/// ```
public enum RulesetFile {
    /// A file with a higher number is refused rather than half-read.
    public static let format = 1

    public static let fileExtension = "xml"

    // MARK: - Writing

    public static func data(for ruleset: Ruleset) -> Data {
        let root = XMLElement(name: "ruleset")
        root.set("format", String(format))
        root.set("name", ruleset.name)
        root.set("version", ruleset.version.map(String.init))

        for rule in ruleset.rules {
            root.addChild(ruleElement(rule))
        }

        for policy in ruleset.outputs {
            root.addChild(outputElement(policy))
        }

        let document = XMLDocument(rootElement: root)
        document.version = "1.0"
        document.characterEncoding = "UTF-8"
        var data = document.xmlData(options: [.nodePrettyPrint, .nodeCompactEmptyElement])
        if data.last != UInt8(ascii: "\n") { data.append(UInt8(ascii: "\n")) }
        return data
    }

    /// One rule as an element of the document, on one line: what an edit splices in.
    public static func element(for rule: Rule) -> String {
        written(ruleElement(rule))
    }

    /// One output as an element of the document.
    public static func element(for output: OutputPolicy) -> String {
        written(outputElement(output))
    }

    /// An element as one line of XML, written here rather than by the XML library so that it reads
    /// the same on every platform: attributes in the order they were set, an empty element closed in
    /// its own tag.
    private static func written(_ element: XMLElement) -> String {
        func escaped(_ text: String, quote: Bool) -> String {
            var escaped = text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            if quote { escaped = escaped.replacingOccurrences(of: "\"", with: "&quot;") }
            return escaped
        }
        let name = element.name ?? ""
        let attributes = (element.attributes ?? []).map {
            " \($0.name ?? "")=\"\(escaped($0.stringValue ?? "", quote: true))\""
        }.joined()
        let children = (element.children ?? []).compactMap { $0 as? XMLElement }
        if !children.isEmpty {
            return "<\(name)\(attributes)>" + children.map(written).joined() + "</\(name)>"
        }
        if let text = element.stringValue, !text.isEmpty {
            return "<\(name)\(attributes)>\(escaped(text, quote: false))</\(name)>"
        }
        return "<\(name)\(attributes)/>"
    }

    private static func ruleElement(_ rule: Rule) -> XMLElement {
        let element = XMLElement(name: rule.scope.rawValue)
        element.set("id", rule.id)
        for condition in rule.conditions {
            let when = XMLElement(name: "when")
            when.set("fact", condition.fact.rawValue)
            let (test, value) = condition.test.attribute
            when.set(test, value)
            element.addChild(when)
        }
        element.addChild(actionElement(rule.action))
        return element
    }

    private static func outputElement(_ policy: OutputPolicy) -> XMLElement {
        let output = XMLElement(name: "output")
        output.set("profile", policy.profile)
        output.set("container", policy.container)
        return output
    }

    private static func actionElement(_ action: Action) -> XMLElement {
        switch action {
        case .copy:
            return XMLElement(name: "copy")
        case .drop:
            return XMLElement(name: "drop")
        case .encode(let settings):
            let element = XMLElement(name: "encode")
            element.set("codec", settings.codec)
            element.set("preset", settings.preset)
            element.set("crf", settings.crf.map(String.init))
            element.set("bitrate", settings.bitrate)
            element.set("channels", settings.channels.map(String.init))
            element.set("pixelFormat", settings.pixelFormat)
            for filter in settings.filters {
                switch filter {
                case .deinterlace(let mode):
                    let child = XMLElement(name: "deinterlace")
                    child.set("mode", mode.rawValue)
                    element.addChild(child)
                case .scale(let width, let height):
                    let child = XMLElement(name: "scale")
                    child.set("width", width.map(String.init))
                    child.set("height", height.map(String.init))
                    element.addChild(child)
                case .custom(let text):
                    element.addChild(XMLElement(name: "filter", stringValue: text))
                }
            }
            for (name, value) in settings.options.sorted(by: { $0.key < $1.key }) {
                let child = XMLElement(name: "option")
                child.set("name", name)
                child.set("value", value)
                element.addChild(child)
            }
            return element
        }
    }

    static func number(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(value)
    }

    // MARK: - Reading

    public static func ruleset(from data: Data) throws -> Ruleset {
        // Well-formedness first, through the event parser, for the reason SmdKit's reader gives:
        // the document parser on Linux is libxml2 in recovery mode, and a truncated file comes
        // back with its tags closed for it.
        let parser = XMLParser(data: data)
        let parsed = parser.parse()
        if let error = parser.parserError {
            throw RulesetFileError.malformed(
                "line \(parser.lineNumber), column \(parser.columnNumber): \(error.localizedDescription)"
            )
        }
        guard parsed else { throw RulesetFileError.malformed("not well-formed XML") }
        let document: XMLDocument
        do {
            document = try XMLDocument(data: data, options: [])
        } catch {
            throw RulesetFileError.malformed(error.localizedDescription)
        }
        guard let root = document.rootElement(), root.name == "ruleset" else {
            throw RulesetFileError.notARuleset
        }
        try root.knows("format", "name", "version")
        let format = try root.integer("format")
        guard format >= 1 else {
            throw RulesetFileError.invalidValue(element: "ruleset", attribute: "format", value: String(format))
        }
        guard format <= Self.format else { throw RulesetFileError.unsupportedFormat(format) }

        let name = try root.required("name")
        let version = try root.optionalInteger("version")

        var outputs: [OutputPolicy] = []
        for element in root.elements(forName: "output") {
            let output = try output(from: element)
            guard !outputs.contains(where: { $0.profile == output.profile }) else {
                throw RulesetFileError.outputMadeTwice(profile: output.profile)
            }
            outputs.append(output)
        }

        var rules: [Rule] = []
        for case let element as XMLElement in root.children ?? [] {
            switch element.name {
            case "output":
                continue
            case "video", "audio", "subtitle":
                rules.append(try rule(from: element, scope: Scope(rawValue: element.name!)!, position: rules.count + 1))
            default:
                throw RulesetFileError.unknownElement(element.name ?? "?")
            }
        }

        try checkIDs(of: rules)
        return Ruleset(name: name, version: version, rules: rules, outputs: outputs)
    }

    /// A version of a container's or a binding's rules: one root `<rules>` of rule elements, read as
    /// a ruleset's are, and nothing else — no outputs, which are the applied ruleset's alone. Refused whole, as a ruleset is.
    public static func layerRules(from data: Data) throws -> [Rule] {
        let parser = XMLParser(data: data)
        let parsed = parser.parse()
        if let error = parser.parserError {
            throw RulesetFileError.malformed(
                "line \(parser.lineNumber), column \(parser.columnNumber): \(error.localizedDescription)"
            )
        }
        guard parsed, !data.isEmpty else { throw RulesetFileError.malformed("not well-formed XML") }
        let document: XMLDocument
        do {
            document = try XMLDocument(data: data, options: [])
        } catch {
            throw RulesetFileError.malformed(error.localizedDescription)
        }
        guard let root = document.rootElement(), root.name == "rules" else {
            throw RulesetFileError.notLayerRules
        }
        try root.knows()
        var rules: [Rule] = []
        for case let element as XMLElement in root.children ?? [] {
            switch element.name {
            case "video", "audio", "subtitle":
                rules.append(try rule(from: element, scope: Scope(rawValue: element.name!)!, position: rules.count + 1))
            default:
                throw RulesetFileError.notALayerElement(element.name ?? "?")
            }
        }
        try checkIDs(of: rules)
        return rules
    }

    /// Each rule's `id` names one rule of the document, since a recipe names the rule that decided
    /// a stream by it, and none is spelled `#n`, the name an unnamed rule is given by its position.
    private static func checkIDs(of rules: [Rule]) throws {
        var seen: Set<String> = []
        for id in rules.compactMap(\.id) {
            if id.first == "#", id.count > 1, id.dropFirst().allSatisfy({ $0.isASCII && $0.isNumber }) {
                throw RulesetFileError.positionalRuleID(id)
            }
            guard seen.insert(id).inserted else { throw RulesetFileError.sharedRuleID(id) }
        }
    }

    /// A rule, at its 1-based position among the document's rules of every scope. A refusal names
    /// it as a recipe and the resolver do: by its `id`, or `#n` for that position when it has none.
    private static func rule(from element: XMLElement, scope: Scope, position: Int) throws -> Rule {
        try element.knows("id")
        let id = element.attribute("id")
        let label = id ?? "#\(position)"
        var conditions: [Condition] = []
        var action: Action?
        for case let child as XMLElement in element.children ?? [] {
            switch child.name {
            case "when":
                conditions.append(try condition(from: child, scope: scope, rule: label))
            case "copy", "drop", "encode":
                guard action == nil else { throw RulesetFileError.multipleActions(rule: label) }
                action = try Self.action(from: child)
            default:
                throw RulesetFileError.unknownElement(child.name ?? "?")
            }
        }
        guard let action else { throw RulesetFileError.noAction(rule: label) }
        return Rule(id: id, scope: scope, conditions: conditions, action: action)
    }

    private static func condition(from element: XMLElement, scope: Scope, rule: String) throws -> Condition {
        try element.knows("fact", "is", "ne", "in", "lt", "le", "gt", "ge")
        let key = try element.required("fact")
        guard let fact = FactKey(rawValue: key) else { throw RulesetFileError.unknownFact(key) }
        guard fact.isVisible(in: scope) else { throw RulesetFileError.factOutOfScope(fact: key, scope: scope) }

        let tests: [(String, (String) throws -> Condition.Test)] = [
            ("is", { .equal($0) }),
            ("ne", { .notEqual($0) }),
            ("in", { .oneOf($0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }) }),
            ("lt", { .less(try number($0, element: element, attribute: "lt")) }),
            ("le", { .lessOrEqual(try number($0, element: element, attribute: "le")) }),
            ("gt", { .greater(try number($0, element: element, attribute: "gt")) }),
            ("ge", { .greaterOrEqual(try number($0, element: element, attribute: "ge")) }),
        ]
        let present = tests.filter { element.attribute($0.0) != nil }
        guard present.count == 1, let (operatorName, make) = present.first else {
            throw RulesetFileError.oneTestRequired(rule: rule, fact: key)
        }
        let test = try make(element.attribute(operatorName)!)
        if test.isNumeric && !fact.isNumeric {
            throw RulesetFileError.notNumeric(fact: key, operator: operatorName)
        }
        if let values = fact.values, let value = test.values.first(where: { !values.contains($0) }) {
            throw RulesetFileError.notAValueOf(fact: key, value: value)
        }
        return Condition(fact, test)
    }

    private static func number(_ text: String, element: XMLElement, attribute: String) throws -> Double {
        guard let value = Double(text) else {
            throw RulesetFileError.invalidValue(element: element.name ?? "?", attribute: attribute, value: text)
        }
        return value
    }

    private static func action(from element: XMLElement) throws -> Action {
        switch element.name {
        case "copy":
            try element.knows()
            return .copy
        case "drop":
            try element.knows()
            return .drop
        default:
            try element.knows("codec", "preset", "crf", "bitrate", "channels", "pixelFormat")
            var settings = EncodeSettings(codec: try element.required("codec"))
            settings.preset = element.attribute("preset")
            settings.crf = try element.optionalInteger("crf")
            settings.bitrate = element.attribute("bitrate")
            settings.channels = try element.optionalInteger("channels")
            settings.pixelFormat = element.attribute("pixelFormat")
            for case let child as XMLElement in element.children ?? [] {
                if child.name == "option" {
                    try child.knows("name", "value")
                    settings.options[try child.required("name")] = try child.required("value")
                } else {
                    settings.filters.append(try filter(from: child))
                }
            }
            return .encode(settings)
        }
    }

    private static func filter(from element: XMLElement) throws -> Filter {
        switch element.name {
        case "deinterlace":
            try element.knows("mode")
            let mode = element.attribute("mode") ?? "auto"
            guard let parsed = Filter.DeinterlaceMode(rawValue: mode) else {
                throw RulesetFileError.invalidValue(element: "deinterlace", attribute: "mode", value: mode)
            }
            return .deinterlace(parsed)
        case "scale":
            try element.knows("width", "height")
            let width = try element.optionalInteger("width")
            let height = try element.optionalInteger("height")
            guard width != nil || height != nil else { throw RulesetFileError.scaleWithoutSize }
            return .scale(width: width, height: height)
        case "filter":
            try element.knows()
            let filter = element.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !filter.isEmpty else { throw RulesetFileError.emptyFilter }
            return .custom(filter)
        default:
            throw RulesetFileError.unknownElement(element.name ?? "?")
        }
    }

    private static func output(from element: XMLElement) throws -> OutputPolicy {
        try element.knows("profile", "container")
        let container = element.attribute("container") ?? "mkv"
        guard OutputPolicy.containers.contains(container) else {
            throw RulesetFileError.invalidValue(element: "output", attribute: "container", value: container)
        }
        return OutputPolicy(profile: element.attribute("profile"), container: container)
    }
}

public enum RulesetFileError: Error, Equatable, CustomStringConvertible {
    case malformed(String)
    case notARuleset
    case unsupportedFormat(Int)
    case missingAttribute(element: String, attribute: String)
    case invalidValue(element: String, attribute: String, value: String)
    case unknownElement(String)
    case unknownFact(String)
    case factOutOfScope(fact: String, scope: Scope)
    case oneTestRequired(rule: String, fact: String)
    case notNumeric(fact: String, operator: String)
    case noAction(rule: String)
    case multipleActions(rule: String)
    case outputMadeTwice(profile: String?)
    case notLayerRules
    case notALayerElement(String)
    case sharedRuleID(String)
    case positionalRuleID(String)
    case unknownAttribute(element: String, attribute: String)
    case notAValueOf(fact: String, value: String)
    case scaleWithoutSize
    case emptyFilter

    public var description: String {
        switch self {
        case .malformed(let reason): "malformed XML: \(reason)"
        case .notARuleset: "the document is not rooted at <ruleset>"
        case .unsupportedFormat(let format):
            "ruleset format \(format) is newer than this reader (\(RulesetFile.format))"
        case .missingAttribute(let element, let attribute): "<\(element)> is missing its \(attribute) attribute"
        case .invalidValue(let element, let attribute, let value):
            "<\(element) \(attribute)=\"\(value)\"> is not a value this reader accepts"
        case .unknownElement(let name): "<\(name)> is not an element of a ruleset"
        case .unknownFact(let key): "\"\(key)\" is not a fact a rule can test"
        case .factOutOfScope(let fact, let scope): "\"\(fact)\" cannot be tested in a <\(scope.rawValue)> rule"
        case .oneTestRequired(let rule, let fact):
            "rule \(rule): <when fact=\"\(fact)\"> needs exactly one of is, ne, in, lt, le, gt, ge"
        case .notNumeric(let fact, let op): "\"\(fact)\" is not a number and cannot be compared with \(op)"
        case .noAction(let rule): "rule \(rule) has no <copy/>, <drop/> or <encode>"
        case .multipleActions(let rule): "rule \(rule) has more than one action"
        case .outputMadeTwice(let profile?): "the profile \(profile) is made twice"
        case .outputMadeTwice(nil): "the unqualified output is made twice"
        case .notLayerRules: "the document is not rooted at <rules>"
        case .notALayerElement(let name): "<\(name)> is not an element of a container's or a binding's rules"
        case .sharedRuleID(let id): "two rules are called \(id)"
        case .positionalRuleID(let id): "\(id) is how an unnamed rule is named by its position, and cannot be an id"
        case .unknownAttribute(let element, let attribute): "\(attribute) is not an attribute of <\(element)>"
        case .notAValueOf(let fact, let value):
            "\"\(value)\" is not a value \"\(fact)\" takes: \(FactKey(rawValue: fact)?.values?.joined(separator: ", ") ?? "")"
        case .scaleWithoutSize: "<scale> needs a width, a height or both"
        case .emptyFilter: "<filter> has no filter in it"
        }
    }
}

// MARK: - XML helpers

// The same helpers SmdKit's ContainerFile keeps private, spelled the same way. Duplicated rather
// than exported from there, because a ruleset is this project's document and SmdKit's public
// surface is the container model, not an XML convenience.
extension XMLElement {
    func set(_ name: String, _ value: String?) {
        guard let value else { return }
        // Foundation types the factory's result as `Any` on every platform, though it is always an
        // attribute node.
        guard let attribute = XMLNode.attribute(withName: name, stringValue: value) as? XMLNode else {
            preconditionFailure("XMLNode.attribute(withName:stringValue:) returned a non-node")
        }
        addAttribute(attribute)
    }

    /// Refuses an attribute the element does not have, rather than ignoring it: a misspelling would
    /// otherwise be read as the default it was meant to change.
    func knows(_ names: String...) throws {
        for attribute in attributes ?? [] {
            guard let name = attribute.name, !names.contains(name) else { continue }
            throw RulesetFileError.unknownAttribute(element: self.name ?? "?", attribute: name)
        }
    }

    func attribute(_ name: String) -> String? {
        attribute(forName: name)?.stringValue
    }

    func required(_ name: String) throws -> String {
        guard let value = attribute(name) else {
            throw RulesetFileError.missingAttribute(element: self.name ?? "?", attribute: name)
        }
        return value
    }

    func integer(_ name: String) throws -> Int {
        let value = try required(name)
        guard let integer = Int(value) else {
            throw RulesetFileError.invalidValue(element: self.name ?? "?", attribute: name, value: value)
        }
        return integer
    }

    func optionalInteger(_ name: String) throws -> Int? {
        guard let value = attribute(name) else { return nil }
        guard let integer = Int(value) else {
            throw RulesetFileError.invalidValue(element: self.name ?? "?", attribute: name, value: value)
        }
        return integer
    }

    func bool(_ name: String) throws -> Bool? {
        guard let value = attribute(name) else { return nil }
        switch value {
        case "true": return true
        case "false": return false
        default: throw RulesetFileError.invalidValue(element: self.name ?? "?", attribute: name, value: value)
        }
    }

    func child(_ name: String) -> XMLElement? {
        elements(forName: name).first
    }
}

extension Condition.Test {
    /// The test as a document writes it: the attribute's name, and its value as text.
    public var attribute: (name: String, value: String) {
        switch self {
        case .equal(let value): ("is", value)
        case .notEqual(let value): ("ne", value)
        case .oneOf(let values): ("in", values.joined(separator: ","))
        case .less(let value): ("lt", RulesetFile.number(value))
        case .lessOrEqual(let value): ("le", RulesetFile.number(value))
        case .greater(let value): ("gt", RulesetFile.number(value))
        case .greaterOrEqual(let value): ("ge", RulesetFile.number(value))
        }
    }
    /// The test a document writes as `name="value"`, or nil when the name is not a test or a
    /// comparison's value is not a number.
    public init?(attribute name: String, value: String) {
        switch name {
        case "is": self = .equal(value)
        case "ne": self = .notEqual(value)
        case "in": self = .oneOf(value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        case "lt", "le", "gt", "ge":
            guard let number = Double(value.trimmingCharacters(in: .whitespaces)) else { return nil }
            switch name {
            case "lt": self = .less(number)
            case "le": self = .lessOrEqual(number)
            case "gt": self = .greater(number)
            default: self = .greaterOrEqual(number)
            }
        default: return nil
        }
    }
}
