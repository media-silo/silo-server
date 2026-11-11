// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

#if canImport(SwiftUI)
import SiloAdminKit
import SwiftUI

extension AdminConsole.Silo: Identifiable {}

extension AdminConsole.PreparedSetup: Identifiable {
    public var id: String { serverID }
}

/// This Mac's settings, kept on it for every silo: TMDb, and what a walk ticks to begin with.
struct SettingsWindow: View {
    let model: ConsoleModel

    var body: some View {
        TabView {
            Tab("TMDb", systemImage: "film") { TMDbSettings(model: model) }
            Tab("Walks", systemImage: "checklist") { WalkDefaults(model: model) }
        }
        .frame(width: 480)
    }
}

/// TMDb as this Mac reads it: the token, kept in the keychain, the language it answers in, why it cannot
/// be read when it cannot, and the notice TMDb's terms ask for. The console reaches TMDb itself; the
/// silo is never given the token.
private struct TMDbSettings: View {
    let model: ConsoleModel
    @State private var token = ""
    @State private var language = ""

    var body: some View {
        Form {
            Section {
                SecureField(
                    "Read access token",
                    text: $token,
                    prompt: Text(model.tmdbToken == nil ? "None given" : "Kept in the keychain")
                )
                .onSubmit {
                    Task {
                        await model.setTMDbToken(token)
                        token = ""
                    }
                }
                TextField("Language", text: $language).onSubmit { model.setTMDbLanguage(language) }
                HStack {
                    if let problem = model.tmdbProblem {
                        Text(problem).foregroundStyle(.orange).textSelection(.enabled)
                    } else if model.tmdbToken != nil {
                        Text("TMDb accepts the token.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Check") { Task { await model.checkTMDb() } }
                }
                .font(.callout)
            } footer: {
                HStack(alignment: .top) {
                    TMDbMark()
                    Text(TMDb.notice).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .task { language = model.tmdbLanguage }
    }
}

/// What a new container in a walk is ticked with to begin with, field by field: everything it is offered
/// unless unticked here. Each stop can still be ticked otherwise in the walk.
private struct WalkDefaults: View {
    let model: ConsoleModel

    var body: some View {
        Form {
            Section("From Wikidata") {
                ForEach(ReviewWalk.wikidataDefaultFields, id: \.self, content: toggle)
            }
            Section {
                ForEach(ReviewWalk.tmdbDefaultFields, id: \.self, content: toggle)
            } header: {
                HStack {
                    Text("From TMDb")
                    TMDbMark()
                }
            } footer: {
                Text(
                    "A new container is ticked with each field ticked here that it is offered, and a held one "
                        + "with nothing. Either can be ticked otherwise at its stop in the walk."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func toggle(_ field: String) -> some View {
        Toggle(
            Self.name(field),
            isOn: Binding(
                get: { !model.untickedFields.contains(field) },
                set: { model.tick(field, byDefault: $0) }
            )
        )
    }

    static func name(_ field: String) -> String {
        switch field {
        case "year": "Year"
        case "premiered": "First date"
        case "cast": "Cast"
        case "crew": "Directors and writers"
        case "references": "References to other providers"
        case "outline": "Outline"
        case "artwork:poster": "Poster"
        case "artwork:fanart": "Fanart"
        case "artwork:logo": "Logo"
        default: field
        }
    }
}
#endif
