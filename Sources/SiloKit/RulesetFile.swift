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
///   <extraction embeddedAudio="false" subtitles="true" embeddedSubtitles="true"/>
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

        let extraction = XMLElement(name: "extraction")
        extraction.set("embeddedAudio", ruleset.extraction.includeEmbeddedAudioTracks ? "true" : "false")
        extraction.set("subtitles", ruleset.extraction.includeSubtitles ? "true" : "false")
        extraction.set("embeddedSubtitles", ruleset.extraction.includeEmbeddedSubtitleTracks ? "true" : "false")
        root.addChild(extraction)

        for rule in ruleset.rules {
            let element = XMLElement(name: rule.scope.rawValue)
            element.set("id", rule.id)
            for condition in rule.conditions {
                let when = XMLElement(name: "when")
                when.set("fact", condition.fact.rawValue)
                switch condition.test {
                case .equal(let value): when.set("is", value)
                case .notEqual(let value): when.set("ne", value)
                case .oneOf(let values): when.set("in", values.joined(separator: ","))
                case .less(let value): when.set("lt", Self.number(value))
                case .lessOrEqual(let value): when.set("le", Self.number(value))
                case .greater(let value): when.set("gt", Self.number(value))
                case .greaterOrEqual(let value): when.set("ge", Self.number(value))
                }
                element.addChild(when)
            }
            element.addChild(actionElement(rule.action))
            root.addChild(element)
        }

        let output = XMLElement(name: "output")
        output.set("container", ruleset.output.container)
        root.addChild(output)

        let document = XMLDocument(rootElement: root)
        document.version = "1.0"
        document.characterEncoding = "UTF-8"
        var data = document.xmlData(options: [.nodePrettyPrint, .nodeCompactEmptyElement])
        if data.last != UInt8(ascii: "\n") { data.append(UInt8(ascii: "\n")) }
        return data
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

    private static func number(_ value: Double) -> String {
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
            throw RulesetFileError.malformed(error.localizedDescription)
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
        let format = try root.integer("format")
        guard format <= Self.format else { throw RulesetFileError.unsupportedFormat(format) }

        let name = try root.required("name")
        let version = try root.optionalInteger("version")

        var extraction = ExtractionPolicy()
        if let element = root.child("extraction") {
            extraction.includeEmbeddedAudioTracks = try element.bool("embeddedAudio") ?? extraction.includeEmbeddedAudioTracks
            extraction.includeSubtitles = try element.bool("subtitles") ?? extraction.includeSubtitles
            extraction.includeEmbeddedSubtitleTracks = try element.bool("embeddedSubtitles") ?? extraction.includeEmbeddedSubtitleTracks
        }

        var output = OutputPolicy()
        if let element = root.child("output"), let container = element.attribute("container") {
            output.container = container
        }

        var rules: [Rule] = []
        for case let element as XMLElement in root.children ?? [] {
            switch element.name {
            case "extraction", "output":
                continue
            case "video", "audio", "subtitle":
                rules.append(try rule(from: element, scope: Scope(rawValue: element.name!)!))
            default:
                throw RulesetFileError.unknownElement(element.name ?? "?")
            }
        }

        return Ruleset(name: name, version: version, extraction: extraction, rules: rules, output: output)
    }

    private static func rule(from element: XMLElement, scope: Scope) throws -> Rule {
        let id = element.attribute("id")
        let label = id ?? scope.rawValue
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
            return .copy
        case "drop":
            return .drop
        default:
            var settings = EncodeSettings(codec: try element.required("codec"))
            settings.preset = element.attribute("preset")
            settings.crf = try element.optionalInteger("crf")
            settings.bitrate = element.attribute("bitrate")
            settings.channels = try element.optionalInteger("channels")
            settings.pixelFormat = element.attribute("pixelFormat")
            for case let child as XMLElement in element.children ?? [] {
                switch child.name {
                case "deinterlace":
                    let mode = child.attribute("mode") ?? "auto"
                    guard let parsed = Filter.DeinterlaceMode(rawValue: mode) else {
                        throw RulesetFileError.invalidValue(element: "deinterlace", attribute: "mode", value: mode)
                    }
                    settings.filters.append(.deinterlace(parsed))
                case "scale":
                    settings.filters.append(.scale(width: try child.optionalInteger("width"), height: try child.optionalInteger("height")))
                case "filter":
                    settings.filters.append(.custom(child.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""))
                case "option":
                    settings.options[try child.required("name")] = try child.required("value")
                default:
                    throw RulesetFileError.unknownElement(child.name ?? "?")
                }
            }
            return .encode(settings)
        }
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

    public var description: String {
        switch self {
        case .malformed(let reason): "malformed XML: \(reason)"
        case .notARuleset: "the document is not rooted at <ruleset>"
        case .unsupportedFormat(let format): "ruleset format \(format) is newer than this reader (\(RulesetFile.format))"
        case .missingAttribute(let element, let attribute): "<\(element)> is missing its \(attribute) attribute"
        case .invalidValue(let element, let attribute, let value): "<\(element) \(attribute)=\"\(value)\"> is not a value this reader accepts"
        case .unknownElement(let name): "<\(name)> is not an element of a ruleset"
        case .unknownFact(let key): "\"\(key)\" is not a fact a rule can test"
        case .factOutOfScope(let fact, let scope): "\"\(fact)\" cannot be tested in a <\(scope.rawValue)> rule"
        case .oneTestRequired(let rule, let fact): "rule \(rule): <when fact=\"\(fact)\"> needs exactly one of is, ne, in, lt, le, gt, ge"
        case .notNumeric(let fact, let op): "\"\(fact)\" is not a number and cannot be compared with \(op)"
        case .noAction(let rule): "rule \(rule) has no <copy/>, <drop/> or <encode>"
        case .multipleActions(let rule): "rule \(rule) has more than one action"
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
        addAttribute(XMLNode.attribute(withName: name, stringValue: value) as! XMLNode)
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
