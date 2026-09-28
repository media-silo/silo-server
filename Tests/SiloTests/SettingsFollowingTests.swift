// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the media-silo project authors

import Encoder
import Foundation
import SiloKit
import SiloStore
import Testing
@testable import SiloApp
@testable import silo

/// The services that follow the settings while the silo runs: what the advertiser would say as the
/// setting, the name and bootstrap change, with no Bonjour needed to ask it.
struct AdvertiserTests {
    @Test func theAnnouncementFollowsTheSettingTheNameAndBootstrap() throws {
        let settings = SettingsStore(Settings(name: "Silo on attic", advertise: false))
        let credential = OperatorCredential()
        let server = ServerService(identity: ServerIdentity(id: "s1"), settings: settings, credential: credential)
        let advertiser = Advertiser(
            config: SiloConfig(serverID: "s1", host: "0.0.0.0", port: 8742, stateDirectory: URL(fileURLWithPath: "/dev/null"), libraries: []),
            server: server, settings: settings, interval: .milliseconds(10)
        )
        #expect(advertiser.announcement == nil, "the setting is off")

        try settings.update { $0.advertise = true }
        #expect(advertiser.announcement == Advertiser.Announcement(name: "Silo on attic", txt: ["v": "1", "id": "s1", "b": "1"]))

        try settings.update { $0.name = "Living Room Silo" }
        try server.land(StoredOperatorCredential(passkeyHash: NodeStore.hash("horse-battery")))
        #expect(advertiser.announcement == Advertiser.Announcement(name: "Living Room Silo", txt: ["v": "1", "id": "s1"]), "renamed, and out of bootstrap")
    }
}

/// The embedded node following its setting, with the real tools on a sample the tools make: off, it
/// claims nothing; on, it claims without a restart; off again, it claims no more. Skipped where ffmpeg
/// is missing.
@Suite(.enabled(if: FFmpeg.isAvailable && FFprobe.isAvailable, "ffmpeg and ffprobe are needed"))
struct EmbeddedNodeTests {
    private func sample(in bench: JobServiceTests.Bench, named name: String) async throws -> (FileRef, ProbedSource) {
        let file = bench.root.appendingPathComponent(name)
        try await FFmpeg().run([
            "-y", "-nostdin", "-hide_banner", "-loglevel", "error",
            "-f", "lavfi", "-i", "testsrc=size=320x240:rate=25:duration=1",
            "-f", "lavfi", "-i", "sine=frequency=440:duration=1",
            "-f", "lavfi", "-i", "sine=frequency=880:duration=1",
            "-map", "0:v", "-map", "1:a", "-map", "2:a", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "flac",
            file.path,
        ])
        return (FileRef(holder: "embedded", url: file, path: file.path, secret: ""), try await FFprobe().probe(file))
    }

    private func state(of job: String, in bench: JobServiceTests.Bench, becomes wanted: Set<JobState>, within seconds: Double) async throws -> JobState {
        let deadline = Date.now.addingTimeInterval(seconds)
        var state = try bench.service.job(job).state
        while !wanted.contains(state) && Date.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
            state = try bench.service.job(job).state
        }
        return state
    }

    @Test func theEmbeddedNodeFollowsItsSetting() async throws {
        let bench = try JobServiceTests.Bench()
        defer { bench.remove() }
        let settings = SettingsStore(Settings(name: "Silo on attic", embeddedNode: false))
        let node = EmbeddedNode(config: bench.config, jobs: bench.service, settings: settings, pollInterval: .milliseconds(50), progressInterval: .milliseconds(100))
        let running = Task { await node.follow() }
        defer { running.cancel() }

        let (first, firstProbe) = try await sample(in: bench, named: "first.mkv")
        let firstJob = try bench.service.register(source: first, discName: nil, probe: firstProbe, makeMKV: nil)
        _ = try bench.service.assign(firstJob.id, JobServiceTests.Bench.assignment(profile: "mobile"))
        try await Task.sleep(for: .milliseconds(400))
        #expect(try bench.service.job(firstJob.id).state == .pending, "off, it claims nothing")

        try settings.update { $0.embeddedNode = true }
        #expect(try await state(of: firstJob.id, in: bench, becomes: [.encoded, .failed], within: 30) == .encoded, "on, it claims and encodes without a restart")

        try settings.update { $0.embeddedNode = false }
        try await Task.sleep(for: .milliseconds(200))
        let (second, secondProbe) = try await sample(in: bench, named: "second.mkv")
        let secondJob = try bench.service.register(source: second, discName: nil, probe: secondProbe, makeMKV: nil)
        _ = try bench.service.assign(secondJob.id, JobServiceTests.Bench.assignment(item: "part2", profile: "mobile"))
        try await Task.sleep(for: .milliseconds(400))
        #expect(try bench.service.job(secondJob.id).state == .pending, "off again, it claims no more")
    }
}
