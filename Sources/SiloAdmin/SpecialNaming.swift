// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

#if canImport(SwiftUI)
import SiloAdminKit
import SmdKit
import SwiftUI

/// Something new a special is placed as, named by the operator as it is placed.
enum SpecialNaming: Identifiable {
    /// Another version of a container: a sequence of its own, holding the special alone.
    case edition(Special, of: String, String)
    /// Another version of one of a container's items: the special in that item's place.
    case version(Special, of: String, item: String, String)
    /// A new companion series, referred to from a container's extras.
    case companion(Special, from: String)

    var id: String {
        switch self {
        case .edition(let special, let stop, _): "edition:\(special.id):\(stop)"
        case .version(let special, let stop, let item, _): "version:\(special.id):\(stop):\(item)"
        case .companion(let special, let stop): "companion:\(special.id):\(stop)"
        }
    }

    var special: Special {
        switch self {
        case .edition(let special, _, _), .version(let special, _, _, _), .companion(let special, _): special
        }
    }

    var isCompanion: Bool { if case .companion = self { true } else { false } }

    /// What is asked, in words.
    var question: String {
        switch self {
        case .edition(let special, _, let container):
            "\(special.episode.title) as another version of \(container): what is this version called?"
        case .version(let special, _, _, let item):
            "\(special.episode.title) in place of \(item), as another version: what is this version called?"
        case .companion(let special, _):
            "\(special.episode.title) into a new companion series: what is the series called?"
        }
    }
}

/// Asks what something new a special is placed as is called: an alternative's title, from the special's
/// own to begin with, or a new companion series' title and whether the household finds it listed.
struct SpecialNamingSheet: View {
    let naming: SpecialNaming
    let done: (Title, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var listed = false
    @FocusState private var titling: Bool

    init(naming: SpecialNaming, done: @escaping (Title, Bool) -> Void) {
        self.naming = naming
        self.done = done
        _title = State(initialValue: naming.isCompanion ? "" : naming.special.episode.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(naming.question).font(.headline).fixedSize(horizontal: false, vertical: true)
            TextField("Title", text: $title)
                .focused($titling)
                .onSubmit(place)
            if naming.isCompanion {
                Toggle("Listed", isOn: $listed)
                    .help(
                        "Unlisted, it is browsed to only through what refers to it; listed, the household finds it too."
                    )
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Place", action: place).keyboardShortcut(.defaultAction).disabled(named == nil)
            }
        }
        .padding()
        .frame(width: 420)
        .task { titling = true }
    }

    private var named: Title? { Title(title.trimmingCharacters(in: .whitespaces)) }

    private func place() {
        guard let named else { return }
        done(named, listed)
        dismiss()
    }
}
#endif
