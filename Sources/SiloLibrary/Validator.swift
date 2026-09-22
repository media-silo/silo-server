// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SmdKit
import SmdSidecar

/// The checks a sidecar has to pass: the ones the sidecar proposal lists that a library can
/// answer, and the ones the layout here adds. Returns findings and never resolves one.
public enum Validator {
    /// Checks that need nothing but the value.
    public static func check(_ sidecar: Sidecar) -> [Finding] {
        var findings: [Finding] = []
        let container = sidecar.container

        var seen: Set<String> = []
        for entry in container.sequences.flatMap(\.items) + container.extras {
            guard let id = entry.id else { continue }
            if !seen.insert(id).inserted {
                findings.append(Finding(.error, "item id \(id) is used twice"))
            }
            if !Slug.isValid(id) {
                findings.append(Finding(.error, "item id \(id) is not a slug"))
            }
        }
        let sequences = Set(container.sequences.compactMap(\.id))
        for alternative in container.alternatives where !sequences.contains(alternative.sequence) {
            findings.append(Finding(.error, "alternative \(alternative.id) plays sequence \(alternative.sequence), which is not there"))
        }
        if let preferred = container.defaultAlternative, !container.alternatives.contains(where: { $0.id == preferred }) {
            findings.append(Finding(.error, "the default alternative \(preferred) is not there"))
        }

        let alternatives = Set(container.alternatives.map(\.id))
        let features = Set(container.features.map(\.id))
        let items = Dictionary(container.sequences.flatMap(\.items).map { ($0, false) } + container.extras.map { ($0, true) }, uniquingKeysWith: { first, _ in first })
            .reduce(into: [String: (entry: Entry, isExtra: Bool)]()) { result, pair in
                if let id = pair.key.id { result[id] = (pair.key, pair.value) }
            }

        for (id, presentations) in sidecar.presentations.sorted(by: { $0.key < $1.key }) {
            guard let (entry, isExtra) = items[id] else {
                findings.append(Finding(.error, "a presentation for item \(id), which the container does not have"))
                continue
            }
            var shapes: Set<String> = []
            for presentation in presentations {
                let shape = "\(presentation.alternative ?? "")|\(presentation.profile ?? "")"
                if !shapes.insert(shape).inserted {
                    findings.append(Finding(.error, "item \(id) has two presentations for the same alternative and profile"))
                }
                if let alternative = presentation.alternative, !alternatives.contains(alternative) {
                    findings.append(Finding(.error, "item \(id): presentation names alternative \(alternative), which is not there"))
                }
                if !LibraryLayout.isInside(presentation.file) {
                    findings.append(Finding(.error, "item \(id): \"\(presentation.file)\" leaves the container's folder"))
                }
                for track in presentation.tracks {
                    if !features.contains(track.feature) {
                        findings.append(Finding(.error, "item \(id): a track for feature \(track.feature), which is not there"))
                    }
                    if track.audio == nil && track.subtitle == nil {
                        findings.append(Finding(.error, "item \(id): a track for \(track.feature) that names no stream"))
                    }
                    if let audio = track.audio, audio < 1 {
                        findings.append(Finding(.error, "item \(id): audio streams count from one; \(track.feature) is at \(audio)"))
                    }
                    if let subtitle = track.subtitle, subtitle < 1 {
                        findings.append(Finding(.error, "item \(id): subtitle streams count from one; \(track.feature) is at \(subtitle)"))
                    }
                }
                var chapterIndices: Set<Int> = []
                for chapter in presentation.chapters {
                    if chapter.index < 1 || !chapterIndices.insert(chapter.index).inserted {
                        findings.append(Finding(.error, "item \(id): chapter index \(chapter.index) is repeated or below one"))
                    }
                }
                let ext = (presentation.file as NSString).pathExtension
                let expected = LibraryLayout.relativePath(for: entry, isExtra: isExtra, displayName: sidecar.displayName(of: presentation), fileExtension: ext.isEmpty ? "mkv" : ext)
                if presentation.file != expected {
                    findings.append(Finding(.warning, "item \(id): \"\(presentation.file)\" is not the name the layout would give it, \"\(expected)\""))
                }
            }
        }
        return findings
    }

    /// The value's checks plus the ones that need the disk: every file a sidecar names exists,
    /// and so does every child it points at.
    public static func check(_ node: LibraryNode) -> [Finding] {
        var findings = check(node.sidecar).map { finding -> Finding in
            var located = finding
            located.path = node.relativeSidecar
            return located
        }
        for (id, presentations) in node.sidecar.presentations.sorted(by: { $0.key < $1.key }) {
            for presentation in presentations where LibraryLayout.isInside(presentation.file) {
                let url = node.folder.appendingPathComponent(presentation.file)
                if !FileManager.default.fileExists(atPath: url.path) {
                    findings.append(Finding(.error, path: node.relativeSidecar, "item \(id): \"\(presentation.file)\" is not there"))
                }
            }
        }
        for (child, path) in node.sidecar.children.sorted(by: { $0.value < $1.value }) where LibraryLayout.isInside(path) {
            if !FileManager.default.fileExists(atPath: node.folder.appendingPathComponent(path).path) {
                findings.append(Finding(.error, path: node.relativeSidecar, "child \(child) at \"\(path)\" is not there"))
            }
        }
        return findings
    }

    /// Every node in a tree, plus what the walk itself found.
    public static func check(_ tree: LibraryTree) -> [Finding] {
        tree.findings + tree.nodes.flatMap(check)
    }
}
