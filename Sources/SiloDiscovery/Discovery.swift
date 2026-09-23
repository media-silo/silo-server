// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Encoder
import Foundation
import Logging

/// A silo on the local network, as Bonjour describes it.
public struct DiscoveredSilo: Hashable, Sendable, Codable {
    public var name: String
    public var host: String
    public var port: Int
    public var txt: [String: String]

    public init(name: String, host: String, port: Int, txt: [String: String] = [:]) {
        self.name = name
        self.host = host
        self.port = port
        self.txt = txt
    }

    public var url: URL {
        URL(string: "http://\(host):\(port)")!
    }
}

/// Bonjour, as convenience rather than mechanism: it fills in a URL a person could type, and
/// nothing depends on it. Done through the tools each platform ships — `dns-sd` on macOS, Avahi's
/// on Linux — as child processes, so that nothing Apple-only is linked and a machine without the
/// tool is told so rather than failed.
public enum Discovery {
    public static let serviceType = "_silo._tcp"

    enum Tool {
        case dnssd(URL)
        case avahi(publish: URL?, browse: URL?)
    }

    static var tool: Tool? {
        if let dnssd = Tools.locate("dns-sd", environmentKey: "DNS_SD_PATH") { return .dnssd(dnssd) }
        let publish = Tools.locate("avahi-publish", environmentKey: "AVAHI_PUBLISH_PATH")
        let browse = Tools.locate("avahi-browse", environmentKey: "AVAHI_BROWSE_PATH")
        if publish != nil || browse != nil { return .avahi(publish: publish, browse: browse) }
        return nil
    }

    public static var isAvailable: Bool { tool != nil }

    /// What a machine without the tool is told.
    public static let unavailable = "no Bonjour tool: dns-sd on macOS, or avahi-utils on Linux"

    // MARK: - Advertising

    /// Keeps the advertisement up until stopped or dropped.
    public final class Advertisement: @unchecked Sendable {
        private let process: Process

        init(process: Process) {
            self.process = process
        }

        public func stop() {
            if process.isRunning { process.terminate() }
        }

        deinit { stop() }
    }

    /// Announces a silo on the local network. The process stays up for as long as the
    /// advertisement should.
    public static func advertise(name: String, port: Int, txt: [String: String]) throws -> Advertisement {
        let records = txt.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }
        let process = Process()
        switch tool {
        case .dnssd(let url):
            process.executableURL = url
            process.arguments = ["-R", name, serviceType, ".", String(port)] + records
        case .avahi(let publish?, _):
            process.executableURL = publish
            process.arguments = ["-s", name, serviceType, String(port)] + records
        default:
            throw DiscoveryError.unavailable
        }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return Advertisement(process: process)
    }

    // MARK: - Browsing

    /// The silos on the network, found within the time given.
    public static func browse(timeout: Duration = .seconds(3)) async throws -> [DiscoveredSilo] {
        switch tool {
        case .dnssd(let url):
            let names = parseDNSSDBrowse(try await collect(url, ["-B", serviceType, "local."], for: timeout))
            var found: [DiscoveredSilo] = []
            for name in names {
                if let silo = parseDNSSDLookup(try await collect(url, ["-L", name, serviceType, "local."], for: .seconds(2)), name: name) {
                    found.append(silo)
                }
            }
            return found
        case .avahi(_, let browse?):
            // -t terminates once the cache is dumped; -r resolves, -p is the parsable form.
            let collected = OutputCollector()
            _ = try await ProcessRunner.run(browse, arguments: ["-rtp", serviceType]) { collected.append($0) }
            return parseAvahi(collected.text.split(separator: "\n").map(String.init))
        default:
            throw DiscoveryError.unavailable
        }
    }

    /// Runs a tool that never exits on its own for a while, and keeps what it said.
    private static func collect(_ url: URL, _ arguments: [String], for timeout: Duration) async throws -> [String] {
        let collected = OutputCollector()
        let run = Task {
            _ = try await ProcessRunner.run(url, arguments: arguments) { collected.append($0) }
        }
        try? await Task.sleep(for: timeout)
        run.cancel()
        _ = try? await run.value
        return collected.text.split(separator: "\n").map(String.init)
    }

    // MARK: - Parsing, kept apart so it is tested on captured output

    /// `dns-sd -B` prints a header and then one line per event, the instance name last:
    /// `15:21:03.123  Add        3   6 local.               _silo._tcp.          Living Room`.
    static func parseDNSSDBrowse(_ lines: [String]) -> [String] {
        var names: [String] = []
        for line in lines {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 7, fields[1] == "Add" else { continue }
            guard let typeIndex = fields.firstIndex(where: { $0.hasPrefix(serviceType) }) else { continue }
            let name = fields[(typeIndex + 1)...].joined(separator: " ")
            if !name.isEmpty, !names.contains(name) { names.append(name) }
        }
        return names
    }

    /// `dns-sd -L` prints `Name._silo._tcp.local. can be reached at host.local.:8080 (interface 6)`
    /// and, on the next line, the TXT records as ` key=value key=value`.
    static func parseDNSSDLookup(_ lines: [String], name: String) -> DiscoveredSilo? {
        var host: String?
        var port: Int?
        var txt: [String: String] = [:]
        for line in lines {
            if let range = line.range(of: "can be reached at ") {
                let rest = line[range.upperBound...]
                let address = rest.split(separator: " ").first.map(String.init) ?? ""
                guard let colon = address.lastIndex(of: ":") else { continue }
                var found = String(address[..<colon])
                while found.hasSuffix(".") { found.removeLast() }
                host = found
                port = Int(address[address.index(after: colon)...])
            } else if host != nil, port != nil, txt.isEmpty {
                txt = parseTXT(line)
            }
        }
        guard let host, let port else { return nil }
        return DiscoveredSilo(name: name, host: host, port: port, txt: txt)
    }

    /// `avahi-browse -rtp` prints one `=;` line per resolved service:
    /// `=;eth0;IPv4;Living\032Room;_silo._tcp;local;host.local;192.168.1.5;8080;"v=1" "name=x"`.
    static func parseAvahi(_ lines: [String]) -> [DiscoveredSilo] {
        var found: [DiscoveredSilo] = []
        for line in lines where line.hasPrefix("=;") {
            let fields = line.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 9, fields[2] == "IPv4" || !found.contains(where: { $0.name == unescape(fields[3]) }) else { continue }
            let name = unescape(fields[3])
            guard let port = Int(fields[8]) else { continue }
            let txt = fields.count > 9 ? parseTXT(fields[9]) : [:]
            let silo = DiscoveredSilo(name: name, host: fields[6], port: port, txt: txt)
            if !found.contains(where: { $0.name == silo.name }) { found.append(silo) }
        }
        return found
    }

    /// `key=value` records separated by spaces, each possibly quoted, as both tools print them;
    /// a quoted record may hold spaces.
    static func parseTXT(_ text: String) -> [String: String] {
        var records: [String] = []
        var current = ""
        var quoted = false
        for character in text {
            switch character {
            case "\"":
                quoted.toggle()
            case " " where !quoted:
                if !current.isEmpty { records.append(current) }
                current = ""
            default:
                current.append(character)
            }
        }
        if !current.isEmpty { records.append(current) }
        var txt: [String: String] = [:]
        for record in records {
            guard let equals = record.firstIndex(of: "=") else { continue }
            txt[String(record[..<equals])] = String(record[record.index(after: equals)...])
        }
        return txt
    }

    /// Avahi escapes a space in a name as `\032`.
    static func unescape(_ name: String) -> String {
        var result = ""
        var rest = Substring(name)
        while let backslash = rest.firstIndex(of: "\\") {
            result += rest[..<backslash]
            let digits = rest[rest.index(after: backslash)...].prefix(3)
            if digits.count == 3, let code = UInt8(digits), let scalar = UnicodeScalar(code) as UnicodeScalar? {
                result.append(Character(scalar))
                rest = rest[rest.index(backslash, offsetBy: 4)...]
            } else {
                result.append("\\")
                rest = rest[rest.index(after: backslash)...]
            }
        }
        return result + rest
    }
}

public enum DiscoveryError: Error, CustomStringConvertible {
    case unavailable

    public var description: String { Discovery.unavailable }
}
