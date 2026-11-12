// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import SmdKit

// MARK: - What a new stop is ticked with to begin with

/// A new container in a walk is ticked with everything it is offered but the fields this Mac's settings
/// leave unticked, whenever it joins the walk.
extension ReviewWalk {
    /// The fields a new stop is not ticked with to begin with, as this Mac's settings say, by the ids
    /// `wikidataDefaultFields` and `tmdbDefaultFields` list.
    public var unticked: Set<String> {
        get { untickedFields ?? [] }
        set { untickedFields = newValue.isEmpty ? nil : newValue }
    }

    /// The fields of Wikidata's a new container may be left unticked with by default: its year, first
    /// date, cast, directors and writers, and its references to providers other than Wikidata.
    public static let wikidataDefaultFields = ["year", "premiered", "cast", "crew", "references"]
    /// The fields of TMDb's a new container may be left unticked with by default: its outline, and its
    /// artwork by kind.
    public static let tmdbDefaultFields = ["outline"] + TMDb.Images.kinds.map { "artwork:\($0)" }

    /// The default field a difference falls under: a reference to a provider other than Wikidata under
    /// `references`, and anything else under its own id. Its Wikidata reference, which the library knows
    /// the item by, falls under none.
    static func defaultField(of difference: String) -> String {
        let parts = difference.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.first == "ref" else { return difference }
        return parts.count > 2 && parts[2] == Provider.wikidata.rawValue ? difference : "references"
    }

    /// A new stop for a container of a draft, ticked as the walk's defaults say.
    func newStop(in tree: DraftTree, _ id: String, parent: String?) -> Stop {
        Stop(newIn: tree, id, parent: parent, offering: offered(id, in: tree), unticked: unticked)
    }
}
