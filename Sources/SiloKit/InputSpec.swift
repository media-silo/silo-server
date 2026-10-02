// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation

/// How a producer describes a source: what is physically in the file — its streams and chapters,
/// and what was observed of them — in a vocabulary the silo defines and no mechanism owns. The silo
/// derives the facts a rule tests from it; it never sees how the file was obtained.
///
/// The shape is versioned and read strictly. `format` is read first, so a spec of a newer format is
/// refused as newer rather than for the fields that are new; then any key the vocabulary does not
/// have is refused, naming it, rather than ignored, because ignoring a misspelt `intelaced` would
/// turn interlaced video into progressive. `Ingestion.md` argues both.
public struct InputSpec: Hashable, Sendable {
    /// The format this reader reads.
    public static let format = 1

    public var format: Int
    public var label: String?
    public var medium: SourceFormat?
    /// Seconds.
    public var duration: Double?
    public var chapters: [Chapter]
    public var streams: [Stream]
    public var notes: [Note]

    public init(
        format: Int = InputSpec.format, label: String? = nil, medium: SourceFormat? = nil, duration: Double? = nil,
        chapters: [Chapter] = [], streams: [Stream], notes: [Note] = []
    ) {
        self.format = format
        self.label = label
        self.medium = medium
        self.duration = duration
        self.chapters = chapters
        self.streams = streams
        self.notes = notes
    }

    /// A chapter: where the source divides itself. It runs to the next chapter's start, or to the
    /// source's end.
    public struct Chapter: Hashable, Sendable {
        /// From one, in order.
        public var index: Int
        /// Seconds from the source's start.
        public var start: Double
        public var title: String?

        public init(index: Int, start: Double, title: String? = nil) {
            self.index = index
            self.start = start
            self.title = title
        }
    }

    public struct Stream: Hashable, Sendable {
        public enum Kind: String, Hashable, Sendable, CaseIterable {
            case video, audio, subtitle, other
        }

        /// Among all the source's streams, from zero, as `ffmpeg` addresses it.
        public var index: Int
        public var kind: Kind
        /// `ffmpeg`'s name where it has one; otherwise the producer's documented name.
        public var codec: String
        public var profile: String?
        public var width: Int?
        public var height: Int?
        public var frameRate: FrameRate?
        public var interlaced: Bool?
        /// `ffmpeg`'s name for the transfer characteristic: `bt709`, `smpte2084`, `arib-std-b67`.
        public var transfer: String?
        public var bitDepth: Int?
        public var channels: Int?
        public var layout: String?
        public var language: LanguageTag?
        public var title: String?
        public var marks: Set<Mark>
        /// For a lossy core extracted from inside a lossless stream, that stream's index.
        public var coreOf: Int?

        public init(
            index: Int, kind: Kind, codec: String, profile: String? = nil, width: Int? = nil, height: Int? = nil,
            frameRate: FrameRate? = nil, interlaced: Bool? = nil, transfer: String? = nil, bitDepth: Int? = nil,
            channels: Int? = nil, layout: String? = nil, language: LanguageTag? = nil, title: String? = nil,
            marks: Set<Mark> = [], coreOf: Int? = nil
        ) {
            self.index = index
            self.kind = kind
            self.codec = codec
            self.profile = profile
            self.width = width
            self.height = height
            self.frameRate = frameRate
            self.interlaced = interlaced
            self.transfer = transfer
            self.bitDepth = bitDepth
            self.channels = channels
            self.layout = layout
            self.language = language
            self.title = title
            self.marks = marks
            self.coreOf = coreOf
        }
    }

    /// What a stream is for, or how it is flagged.
    public enum Mark: String, Hashable, Sendable, CaseIterable, Comparable {
        case `default`, forced, commentary, descriptive, hearingImpaired

        public static func < (lhs: Mark, rhs: Mark) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Something the producer noticed and a person should see; never a fact.
    public struct Note: Hashable, Sendable {
        /// The stream it is about, by index, when it is about one.
        public var stream: Int?
        public var text: String

        public init(stream: Int? = nil, text: String) {
            self.stream = stream
            self.text = text
        }
    }
}

/// A frame rate, exactly: `24000/1001` cannot be written as a decimal. Spelt as `ffmpeg` spells
/// it — a fraction, or a whole number — and compared by value, so `25/1` and `25` are one rate.
public struct FrameRate: Hashable, Sendable, CustomStringConvertible {
    public let numerator: Int
    public let denominator: Int

    /// Nil for anything but a positive fraction or whole number; `0/0`, which `ffprobe` writes for a
    /// stream with no rate, among them.
    public init?(_ text: String) {
        let parts = text.split(separator: "/", omittingEmptySubsequences: false)
        switch parts.count {
        case 1:
            guard let whole = Int(parts[0]), whole > 0 else { return nil }
            self.init(whole, 1)
        case 2:
            guard let numerator = Int(parts[0]), let denominator = Int(parts[1]), numerator > 0, denominator > 0 else { return nil }
            self.init(numerator, denominator)
        default:
            return nil
        }
    }

    public init(_ numerator: Int, _ denominator: Int = 1) {
        self.numerator = numerator
        self.denominator = denominator
    }

    public var value: Double { Double(numerator) / Double(denominator) }

    public var description: String { denominator == 1 ? "\(numerator)" : "\(numerator)/\(denominator)" }

    public static func == (lhs: FrameRate, rhs: FrameRate) -> Bool {
        lhs.numerator * rhs.denominator == rhs.numerator * lhs.denominator
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(value)
    }
}

extension FrameRate: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self.init(value)
    }
}

extension FrameRate: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let whole = try? container.decode(Int.self), whole > 0 {
            self.init(whole)
            return
        }
        let text = try container.decode(String.self)
        guard let rate = FrameRate(text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "\(text) is not a frame rate")
        }
        self = rate
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

// MARK: - Refusals

/// Why an input spec was refused, in words a producer can act on.
public enum InputSpecError: Error, Hashable, Sendable, CustomStringConvertible {
    case notJSON(String)
    case missingFormat
    case newerFormat(Int)
    case unknownField(String)
    case missingField(String)
    case invalidValue(field: String, value: String, expected: String)
    case repeatedStreamIndex(Int)
    case repeatedChapterIndex(Int)
    case chapterOutOfOrder(Int)
    case notCanonical(field: String, value: String, canonical: String)
    case unknownLanguage(field: String)
    case coreOfNothing(stream: Int, names: Int)

    public var description: String {
        switch self {
        case .notJSON(let reason): "the input spec is not a JSON object: \(reason)"
        case .missingFormat: "the input spec has no format"
        case .newerFormat(let format): "input spec format \(format) is newer than this silo reads (\(InputSpec.format))"
        case .unknownField(let path): "\(path) is not a field of an input spec"
        case .missingField(let path): "\(path) is required"
        case .invalidValue(let field, let value, let expected): "\(field) is \(value), which is not \(expected)"
        case .repeatedStreamIndex(let index): "stream index \(index) is used twice"
        case .repeatedChapterIndex(let index): "chapter \(index) is listed twice"
        case .chapterOutOfOrder(let index): "chapter \(index) is out of order"
        case .notCanonical(let field, let value, let canonical): "\(field) is \(value), which is not canonical; write \(canonical)"
        case .unknownLanguage(let field): "\(field) is und; an unknown language is no tag"
        case .coreOfNothing(let stream, let names): "stream \(stream)'s coreOf names \(names), which is not another audio stream of this spec"
        }
    }
}

// MARK: - Reading and writing

extension InputSpec: Codable {
    /// Reads strictly and checks the whole spec, throwing an `InputSpecError` that names the fault.
    public init(from decoder: any Decoder) throws {
        let value = try JSONValue(from: decoder)
        guard case .object(let object) = value else { throw InputSpecError.notJSON("its top level is not an object") }
        self = try InputSpec(object: object)
        try validate()
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(format, forKey: Key("format"))
        try container.encodeIfPresent(label, forKey: Key("label"))
        try container.encodeIfPresent(medium, forKey: Key("medium"))
        try container.encodeIfPresent(duration, forKey: Key("duration"))
        if !chapters.isEmpty {
            var list = container.nestedUnkeyedContainer(forKey: Key("chapters"))
            for chapter in chapters {
                var each = list.nestedContainer(keyedBy: Key.self)
                try each.encode(chapter.index, forKey: Key("index"))
                try each.encode(chapter.start, forKey: Key("start"))
                try each.encodeIfPresent(chapter.title, forKey: Key("title"))
            }
        }
        var list = container.nestedUnkeyedContainer(forKey: Key("streams"))
        for stream in streams {
            var each = list.nestedContainer(keyedBy: Key.self)
            try each.encode(stream.index, forKey: Key("index"))
            try each.encode(stream.kind.rawValue, forKey: Key("kind"))
            try each.encode(stream.codec, forKey: Key("codec"))
            try each.encodeIfPresent(stream.profile, forKey: Key("profile"))
            try each.encodeIfPresent(stream.width, forKey: Key("width"))
            try each.encodeIfPresent(stream.height, forKey: Key("height"))
            try each.encodeIfPresent(stream.frameRate, forKey: Key("frameRate"))
            try each.encodeIfPresent(stream.interlaced, forKey: Key("interlaced"))
            try each.encodeIfPresent(stream.transfer, forKey: Key("transfer"))
            try each.encodeIfPresent(stream.bitDepth, forKey: Key("bitDepth"))
            try each.encodeIfPresent(stream.channels, forKey: Key("channels"))
            try each.encodeIfPresent(stream.layout, forKey: Key("layout"))
            try each.encodeIfPresent(stream.language?.description, forKey: Key("language"))
            try each.encodeIfPresent(stream.title, forKey: Key("title"))
            if !stream.marks.isEmpty {
                try each.encode(stream.marks.sorted().map(\.rawValue), forKey: Key("marks"))
            }
            try each.encodeIfPresent(stream.coreOf, forKey: Key("coreOf"))
        }
        if !notes.isEmpty {
            var list = container.nestedUnkeyedContainer(forKey: Key("notes"))
            for note in notes {
                var each = list.nestedContainer(keyedBy: Key.self)
                try each.encodeIfPresent(note.stream, forKey: Key("stream"))
                try each.encode(note.text, forKey: Key("text"))
            }
        }
    }

    private struct Key: CodingKey {
        let stringValue: String
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }
}

extension InputSpec {
    /// Reads an input spec from JSON, strictly, and checks it whole: the one way a document becomes a
    /// spec the silo uses.
    public static func read(from data: Data) throws(InputSpecError) -> InputSpec {
        do {
            return try JSONDecoder().decode(InputSpec.self, from: data)
        } catch let error as InputSpecError {
            throw error
        } catch {
            throw .notJSON(String(describing: error))
        }
    }

    /// Checks what a reading of one object at a time cannot: indices across streams and chapters,
    /// and what a `coreOf` names.
    public func validate() throws(InputSpecError) {
        var seen: Set<Int> = []
        for stream in streams where !seen.insert(stream.index).inserted {
            throw .repeatedStreamIndex(stream.index)
        }
        var chapterIndices: Set<Int> = []
        for (position, chapter) in chapters.enumerated() {
            guard chapterIndices.insert(chapter.index).inserted else { throw .repeatedChapterIndex(chapter.index) }
            if position > 0 {
                let previous = chapters[position - 1]
                guard chapter.index > previous.index, chapter.start > previous.start else { throw .chapterOutOfOrder(chapter.index) }
            }
        }
        let audio = Set(streams.filter { $0.kind == .audio }.map(\.index))
        for stream in streams {
            if let core = stream.coreOf, core == stream.index || !audio.contains(core) || stream.kind != .audio {
                throw .coreOfNothing(stream: stream.index, names: core)
            }
        }
    }

    fileprivate init(object: [String: JSONValue]) throws(InputSpecError) {
        let reader = Reader(object: object, path: "")
        guard let format = try reader.int("format") else { throw .missingFormat }
        guard format <= InputSpec.format else { throw .newerFormat(format) }
        try reader.refuseUnknown(["format", "label", "medium", "duration", "chapters", "streams", "notes"])
        self.format = format
        label = try reader.string("label")
        if let text = try reader.string("medium") {
            guard let medium = SourceFormat(rawValue: text) else {
                throw .invalidValue(field: reader.at("medium"), value: "\"\(text)\"", expected: "dvd, bluray or uhd")
            }
            self.medium = medium
        } else {
            medium = nil
        }
        duration = try reader.number("duration")
        var chapters: [Chapter] = []
        for chapter in try reader.objects("chapters") {
            try chapter.refuseUnknown(["index", "start", "title"])
            chapters.append(Chapter(index: try chapter.requiredInt("index"), start: try chapter.requiredNumber("start"), title: try chapter.string("title")))
        }
        self.chapters = chapters
        guard reader.has("streams") else { throw .missingField(reader.at("streams")) }
        var streams: [Stream] = []
        for stream in try reader.objects("streams") {
            streams.append(try Stream(reader: stream))
        }
        self.streams = streams
        var notes: [Note] = []
        for note in try reader.objects("notes") {
            try note.refuseUnknown(["stream", "text"])
            notes.append(Note(stream: try note.int("stream"), text: try note.requiredString("text")))
        }
        self.notes = notes
    }
}

extension InputSpec.Stream {
    fileprivate init(reader: Reader) throws(InputSpecError) {
        try reader.refuseUnknown([
            "index", "kind", "codec", "profile", "width", "height", "frameRate", "interlaced", "transfer", "bitDepth",
            "channels", "layout", "language", "title", "marks", "coreOf",
        ])
        index = try reader.requiredInt("index")
        let kindText = try reader.requiredString("kind")
        guard let kind = Kind(rawValue: kindText) else {
            throw .invalidValue(field: reader.at("kind"), value: "\"\(kindText)\"", expected: "video, audio, subtitle or other")
        }
        self.kind = kind
        codec = try reader.requiredString("codec")
        profile = try reader.string("profile")
        width = try reader.int("width")
        height = try reader.int("height")
        frameRate = try reader.frameRate("frameRate")
        interlaced = try reader.bool("interlaced")
        transfer = try reader.string("transfer")
        bitDepth = try reader.int("bitDepth")
        channels = try reader.int("channels")
        layout = try reader.string("layout")
        language = try reader.language("language")
        title = try reader.string("title")
        var marks: Set<InputSpec.Mark> = []
        for text in try reader.strings("marks") {
            guard let mark = InputSpec.Mark(rawValue: text) else {
                throw .invalidValue(field: reader.at("marks"), value: "\"\(text)\"", expected: "a mark: default, forced, commentary, descriptive or hearingImpaired")
            }
            marks.insert(mark)
        }
        self.marks = marks
        coreOf = try reader.int("coreOf")
        switch kind {
        case .video:
            guard width != nil else { throw .missingField(reader.at("width")) }
            guard height != nil else { throw .missingField(reader.at("height")) }
        case .audio:
            guard channels != nil else { throw .missingField(reader.at("channels")) }
        case .subtitle, .other:
            break
        }
    }
}

/// A JSON value as `JSONDecoder` read it, so that a flag is told from a number on every platform.
private enum JSONValue: Decodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    var rendered: String {
        switch self {
        case .null: "null"
        case .bool(let value): "\(value)"
        case .number(let value): value == value.rounded() && abs(value) < 1e15 ? "\(Int(value))" : "\(value)"
        case .string(let value): "\"\(value)\""
        case .array: "a list"
        case .object: "an object"
        }
    }
}

/// One JSON object, read field by field, every refusal naming the field's path.
private struct Reader {
    let object: [String: JSONValue]
    let path: String

    func at(_ key: String) -> String { path.isEmpty ? key : "\(path).\(key)" }

    func has(_ key: String) -> Bool {
        guard let value = object[key] else { return false }
        if case .null = value { return false }
        return true
    }

    func refuseUnknown(_ known: Set<String>) throws(InputSpecError) {
        if let unknown = object.keys.filter({ !known.contains($0) }).sorted().first {
            throw .unknownField(at(unknown))
        }
    }

    private func refuse(_ key: String, expected: String) -> InputSpecError {
        .invalidValue(field: at(key), value: object[key]?.rendered ?? "null", expected: expected)
    }

    func string(_ key: String) throws(InputSpecError) -> String? {
        guard has(key) else { return nil }
        guard case .string(let value) = object[key] else { throw refuse(key, expected: "text") }
        return value
    }

    func requiredString(_ key: String) throws(InputSpecError) -> String {
        guard let value = try string(key) else { throw .missingField(at(key)) }
        return value
    }

    func int(_ key: String) throws(InputSpecError) -> Int? {
        guard has(key) else { return nil }
        guard case .number(let number) = object[key], let value = Int(exactly: number) else { throw refuse(key, expected: "a whole number") }
        return value
    }

    func requiredInt(_ key: String) throws(InputSpecError) -> Int {
        guard let value = try int(key) else { throw .missingField(at(key)) }
        return value
    }

    func number(_ key: String) throws(InputSpecError) -> Double? {
        guard has(key) else { return nil }
        guard case .number(let value) = object[key] else { throw refuse(key, expected: "a number") }
        return value
    }

    func requiredNumber(_ key: String) throws(InputSpecError) -> Double {
        guard let value = try number(key) else { throw .missingField(at(key)) }
        return value
    }

    func bool(_ key: String) throws(InputSpecError) -> Bool? {
        guard has(key) else { return nil }
        guard case .bool(let value) = object[key] else { throw refuse(key, expected: "true or false") }
        return value
    }

    func frameRate(_ key: String) throws(InputSpecError) -> FrameRate? {
        guard has(key) else { return nil }
        let expected = "a fraction such as 24000/1001, or a whole number"
        switch object[key] {
        case .number(let number):
            guard let whole = Int(exactly: number), whole > 0 else { throw refuse(key, expected: expected) }
            return FrameRate(whole)
        case .string(let text):
            guard let rate = FrameRate(text) else { throw refuse(key, expected: expected) }
            return rate
        default:
            throw refuse(key, expected: expected)
        }
    }

    func language(_ key: String) throws(InputSpecError) -> LanguageTag? {
        guard let text = try string(key) else { return nil }
        guard let tag = LanguageTag(canonicalizing: text) else { throw refuse(key, expected: "a BCP 47 language tag") }
        guard tag.description != "und" else { throw .unknownLanguage(field: at(key)) }
        guard tag.description == text else { throw .notCanonical(field: at(key), value: text, canonical: tag.description) }
        return tag
    }

    func strings(_ key: String) throws(InputSpecError) -> [String] {
        guard has(key) else { return [] }
        guard case .array(let values) = object[key] else { throw refuse(key, expected: "a list of text") }
        var strings: [String] = []
        for value in values {
            guard case .string(let text) = value else { throw refuse(key, expected: "a list of text") }
            strings.append(text)
        }
        return strings
    }

    func objects(_ key: String) throws(InputSpecError) -> [Reader] {
        guard has(key) else { return [] }
        guard case .array(let values) = object[key] else { throw refuse(key, expected: "a list") }
        var readers: [Reader] = []
        for (position, value) in values.enumerated() {
            guard case .object(let object) = value else {
                throw .invalidValue(field: "\(at(key))[\(position)]", value: value.rendered, expected: "an object")
            }
            readers.append(Reader(object: object, path: "\(at(key))[\(position)]"))
        }
        return readers
    }
}
