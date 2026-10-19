@testable import BakaUI
import Catalog
import Foundation
import Playback
import Testing
import Tracking

@Suite(.enabled(if: ProcessInfo.processInfo.environment["BAKA_MPV_INTEGRATION"] == "1"))
struct EpisodeAutoplayIntegrationTests {
    @MainActor
    @Test func realPlayerEOFOffersTheNextEpisodeWithoutASeekOrRemoteWrites() async throws {
        let executable = try #require(PlaybackEnvironment.discover().mpvURL)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("autoplay-test-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let media = directory.appendingPathComponent("episode.y4m")
        var frames = Data("YUV4MPEG2 W2 H2 F4:1 Ip A1:1 C420jpeg\n".utf8)
        for _ in 0..<12 {
            frames.append(Data("FRAME\n".utf8))
            frames.append(contentsOf: [16, 16, 16, 16, 128, 128])
        }
        try frames.write(to: media)
        let suite = "AutoplayIntegrationTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let autoplay = EpisodeAutoplayModel(defaults: defaults)
        autoplay.isEnabled = true
        defer { autoplay.cancel() }
        let first = EpisodeContext(animeID: AnimeID(rawValue: 7), title: "Fixture", kind: "tv",
                                   kinopubItemID: 42, season: 1, episode: 1)
        let next = try #require(first.selectingEpisode(itemID: 42, season: 1, episode: 2))
        let session = UUID()
        let player = MPVPlaybackEngine(executable: executable, headless: true)
        do {
            try await player.start()
            try await player.load(PlaybackSource(url: media))
            let deadline = ContinuousClock.now.advanced(by: .seconds(8))
            while autoplay.pending == nil, ContinuousClock.now < deadline {
                let snapshot = try await player.snapshot()
                #expect(!snapshot.hasFailed)
                autoplay.observe(snapshot, context: first, sessionID: session, next: next)
                if !snapshot.hasEnded { #expect(autoplay.pending == nil) }
                try await Task.sleep(for: .milliseconds(100))
            }
            #expect(autoplay.pending?.destination == next)
            #expect(autoplay.remainingSeconds > 0)
            autoplay.cancel()
            autoplay.observe(try await player.snapshot(), context: first, sessionID: session, next: next)
            #expect(autoplay.pending == nil)
            await player.stop()
        } catch {
            await player.stop()
            throw error
        }
    }
}
