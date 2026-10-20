// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

#if canImport(SwiftUI)
import AppKit
import SwiftUI
import SiloAdminKit

/// Choosing the bindings to try a branch's version on: those its impact lists, chosen at first, and
/// any other by its id.
struct TrialSheet: View {
    let trying: ConsoleModel.Trying
    let model: ConsoleModel
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Set<String> = []
    @State private var other = ""
    @State private var others: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Try \(trying.ruleset) Version \(trying.version) on \(trying.branch)").font(.headline)
            Text(
                "Each binding chosen is resolved through this version and encoded as a trial, kept apart from the library to compare with what is placed. Nothing is placed."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            List {
                Section(
                    trying.candidates.isEmpty ? "The branch changes nothing placed" : "What the branch would change"
                ) {
                    ForEach(trying.candidates) { candidate in
                        Toggle(
                            isOn: Binding(
                                get: { chosen.contains(candidate.binding) },
                                set: {
                                    if $0 { chosen.insert(candidate.binding) } else { chosen.remove(candidate.binding) }
                                }
                            )
                        ) {
                            VStack(alignment: .leading) {
                                Text([candidate.container, candidate.item].compactMap { $0 }.joined(separator: " › "))
                                Text(candidate.profile ?? "unqualified").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Other bindings") {
                    ForEach(others, id: \.self) { Text($0).font(.body.monospaced()) }
                    HStack {
                        TextField("Binding id", text: $other)
                        Button("Add") {
                            let id = other.trimmingCharacters(in: .whitespaces)
                            if !id.isEmpty, !others.contains(id) {
                                others.append(id)
                                chosen.insert(id)
                            }
                            other = ""
                        }
                    }
                }
            }
            .frame(minHeight: 220)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Make Trials") {
                    var started = trying
                    started.chosen = chosen
                    Task { await model.startTrials(started) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(chosen.isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 480)
        .onAppear { chosen = trying.chosen }
    }
}

/// The trials of the version's branch: the jobs still encoding, and each tried trial beside what its
/// binding placed, stream by stream, with both files to play.
struct TrialsPanel: View {
    let silo: AdminConsole.Silo
    let model: ConsoleModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Trials").font(.headline)
            ForEach(model.trialRefusals[silo.id] ?? [], id: \.self) { refusal in
                Label(refusal, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.caption)
            }
            ForEach((model.trialJobs[silo.id] ?? []).filter { $0.state.rawValue != "tried" }, id: \.id) { job in
                HStack {
                    Text(job.id.prefix(8)).font(.caption.monospaced())
                    Text(job.state.rawValue)
                    if let fraction = job.progress?.fraction, job.state.rawValue == "encoding" {
                        ProgressView(value: fraction).frame(width: 120)
                    }
                    if let failure = job.failure { Text(failure).foregroundStyle(.red).font(.caption) }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.trials[silo.id] ?? [], id: \.trial.job) { compared in
                        TrialRow(compared: compared) { Task { await model.deleteTrial(compared.trial.job, on: silo) } }
                    }
                }
            }
            .frame(maxHeight: 260)
        }
        .padding(8)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct TrialRow: View {
    let compared: AdminConsole.TrialComparison
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(
                    "\(compared.trial.binding.prefix(8)) · \(compared.trial.profile ?? "unqualified") · \(compared.trial.ruleset)@\(compared.trial.version ?? 0)"
                )
                .font(.callout.monospaced())
                Spacer()
                Button("Play Trial") { NSWorkspace.shared.open(compared.trialFile) }
                Button("Play Placed") { if let url = compared.placedFile { NSWorkspace.shared.open(url) } }
                    .disabled(compared.placedFile == nil)
                Button("Delete", role: .destructive, action: delete)
            }
            .controlSize(.small)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
                GridRow {
                    Text("Stream").bold()
                    Text("Placed").bold()
                    Text("Trial").bold()
                }
                ForEach(compared.streams, id: \.stream) { stream in
                    GridRow {
                        Text(stream.stream)
                        Text(stream.placed?.summary ?? "—")
                        Text(stream.tried?.summary ?? "—")
                            .foregroundStyle(stream.placed == stream.tried ? Color.primary : Color.orange)
                    }
                }
            }
            .font(.caption)
            if compared.placedFile == nil {
                Text(
                    "No placed presentation of this binding is one the branch would change, so there is none to compare with."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

/// A reader's refusal, in its words.
struct RefusalView: View {
    let reason: String

    var body: some View {
        ScrollView {
            Label(reason, systemImage: "exclamationmark.octagon")
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(8)
        }
    }
}

/// Lines of two texts' difference: removed in red, added in green, the rest as they were.
struct DifferenceView: View {
    let lines: [LineDifference.Line]

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(prefix(line.kind) + line.text)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(line.kind == .same ? Color.secondary : Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(background(line.kind))
                }
            }
            .padding(6)
        }
        .frame(minHeight: 80)
        .background(.background.secondary, in: .rect(cornerRadius: 6))
    }

    private func prefix(_ kind: LineDifference.Line.Kind) -> String {
        switch kind {
        case .same: "  "
        case .removed: "- "
        case .added: "+ "
        }
    }

    private func background(_ kind: LineDifference.Line.Kind) -> Color {
        switch kind {
        case .same: .clear
        case .removed: .red.opacity(0.15)
        case .added: .green.opacity(0.15)
        }
    }
}
#endif
