// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Foundation
import SiloKit
import SmdKit

/// The proposal's three rules, as values: what `Examples/household.xml` must read as.
extension Ruleset {
    static let household = Ruleset(
        name: "household",
        rules: [
            Rule(
                id: "small-extras", scope: .video,
                conditions: [
                    Condition(.kind, .oneOf(["featurette", "interview", "deletedScene", "behindTheScenes", "trailer", "scene", "short", "clip"])),
                    Condition(.videoWidth, .less(576)),
                ],
                action: .encode(EncodeSettings(codec: "libx264", preset: "slow", crf: 22, pixelFormat: "yuv420p", filters: [.deinterlace(.auto)]))
            ),
            Rule(
                id: "lossless-main", scope: .audio,
                conditions: [Condition(.audioLossless, .equal("true")), Condition(.audioRole, .notEqual("commentary"))],
                action: .encode(EncodeSettings(codec: "flac"))
            ),
            Rule(
                id: "commentary", scope: .audio,
                conditions: [Condition(.audioRole, .equal("commentary"))],
                action: .encode(EncodeSettings(codec: "aac", bitrate: "160k", channels: 2))
            ),
            Rule(scope: .video, action: .copy),
            Rule(scope: .audio, action: .copy),
            Rule(scope: .subtitle, action: .copy),
        ]
    )

    /// `Examples/household.xml`, read from the repository.
    static func exampleFile() throws -> Ruleset {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Examples/household.xml")
        return try RulesetFile.ruleset(from: Data(contentsOf: url))
    }
}

extension SourceFacts {
    /// A Blu-ray episode: a lossless master mix, a stereo commentary, a lossy stereo mix, two
    /// subtitle streams of which the second is forced.
    static let episode = SourceFacts(
        kind: .episode,
        format: .bluray,
        duration: 1500,
        video: VideoFacts(absoluteIndex: 0, codec: "h264", width: 1920, height: 1080, frameRate: 25),
        audio: [
            AudioFacts(index: 1, absoluteIndex: 1, codec: "truehd", lossless: true, channels: 8, language: "eng", role: .main),
            AudioFacts(index: 2, absoluteIndex: 2, codec: "ac3", lossless: false, channels: 2, language: "eng", role: .commentary),
            AudioFacts(index: 3, absoluteIndex: 3, codec: "ac3", lossless: false, channels: 2, language: "eng", role: .main),
        ],
        subtitles: [
            SubtitleFacts(index: 1, absoluteIndex: 4, codec: "hdmv_pgs_subtitle", language: "eng"),
            SubtitleFacts(index: 2, absoluteIndex: 5, codec: "hdmv_pgs_subtitle", language: "eng", forced: true),
        ]
    )

    /// A DVD featurette at CIF size, interlaced, with one lossy stereo track.
    static let featurette = SourceFacts(
        kind: .featurette,
        format: .dvd,
        duration: 600,
        video: VideoFacts(absoluteIndex: 0, codec: "mpeg2video", width: 352, height: 288, frameRate: 25, interlaced: true),
        audio: [AudioFacts(index: 1, absoluteIndex: 1, codec: "ac3", lossless: false, channels: 2, language: "eng")]
    )
}
