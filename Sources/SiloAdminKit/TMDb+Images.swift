// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

// MARK: - TMDb's images

extension TMDb {
    /// An image's path as a JPEG or a PNG, as the console shows an image and the silo takes one: a logo
    /// TMDb holds as an SVG is rendered by TMDb as a PNG at the same path ending `.png`.
    public static func raster(_ path: String) -> String {
        path.hasSuffix(".svg") ? path.dropLast(4) + ".png" : path
    }

    /// The images TMDb holds for a record, by their paths there, best first: what the artwork kinds
    /// `poster`, `fanart`, `logo` and, for an episode, `thumb` are offered from.
    public struct Images: Hashable, Sendable, Codable {
        /// The artwork kinds TMDb's images are offered for, in the order a stop offers them.
        public static let kinds = ["poster", "fanart", "logo", "thumb"]

        public var posters: [String]
        public var backdrops: [String]
        public var logos: [String]
        /// An episode's stills, which no other record has.
        public var stills: [String]
        /// Each image's size as TMDb holds it, the one put, by its path; one TMDb does not say has none.
        public var sizes: [String: Size]

        public init(
            posters: [String] = [],
            backdrops: [String] = [],
            logos: [String] = [],
            stills: [String] = [],
            sizes: [String: Size] = [:]
        ) {
            self.posters = posters
            self.backdrops = backdrops
            self.logos = logos
            self.stills = stills
            self.sizes = sizes
        }

        /// Reads images a walk kept before stills or sizes were read as having none.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            posters = try container.decode([String].self, forKey: .posters)
            backdrops = try container.decode([String].self, forKey: .backdrops)
            logos = try container.decode([String].self, forKey: .logos)
            stills = try container.decodeIfPresent([String].self, forKey: .stills) ?? []
            sizes = try container.decodeIfPresent([String: Size].self, forKey: .sizes) ?? [:]
        }

        /// The images offered for an artwork kind.
        public func offered(for kind: String) -> [String] {
            switch kind {
            case "poster": posters
            case "fanart": backdrops
            case "logo": logos
            case "thumb": stills
            default: []
            }
        }
    }

    /// An image's width and height, in pixels.
    public struct Size: Hashable, Sendable, Codable {
        public var width: Int
        public var height: Int

        public init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }
    }

    /// Where TMDb holds an episode's stills, beneath its series and its season by their numbers, and the
    /// still its season gives it, which leads them.
    public struct EpisodeStills: Hashable, Sendable, Codable {
        public var series: Int
        public var season: Int
        public var episode: Int
        public var still: String?

        public init(series: Int, season: Int, episode: Int, still: String? = nil) {
            self.series = series
            self.season = season
            self.episode = episode
            self.still = still
        }
    }
}
