@testable import BakaUI
import Catalog
import Foundation
import Playback
import Testing
import Tracking

private func autoplayEpisode(_ number: Int, season: Int = 1) -> EpisodeContext {
    EpisodeContext(animeID: AnimeID(rawValue: 7), title: "Example", kind: "tv",
                   kinopubItemID: 42, season: season, episode: number)
}

private func autoplaySnapshot(ended: Bool = true, failed: Bool = false, seeking: Bool = false) -> PlaybackSnapshot {
    PlaybackSnapshot(isPaused: ended, isIdle: false, position: PlaybackPosition(seconds: ended ? 120 : 30, duration: 120),
                     videoCodec: "h264", audioCodec: "aac", hasEnded: ended, hasFailed: failed, isSeeking: seeking)
}

@MainActor
@Test func autoplayDefaultsOffAndACompletedCountdownAdvancesOnlyOnce() async throws {
    let suite = "AutoplayTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = EpisodeAutoplayModel(defaults: defaults, sleep: {})
    #expect(!model.isEnabled)
    let ignoredSession = UUID()
    model.observe(autoplaySnapshot(), context: autoplayEpisode(1), sessionID: ignoredSession, next: autoplayEpisode(2))
    #expect(model.pending == nil)
    model.isEnabled = true
    #expect(EpisodeAutoplayModel(defaults: defaults).isEnabled)
    model.observe(autoplaySnapshot(), context: autoplayEpisode(1), sessionID: ignoredSession, next: autoplayEpisode(2))
    #expect(model.pending == nil)
    var advances: [Int] = []
    model.onAdvance = { source, destination in
        #expect(source.episode == 1)
        advances.append(destination.episode)
    }
    let session = UUID()
    model.observe(autoplaySnapshot(), context: autoplayEpisode(1), sessionID: session, next: autoplayEpisode(2))
    #expect(model.remainingSeconds == 8)
    for _ in 0..<100 where advances.isEmpty { await Task.yield() }
    #expect(advances == [2])
    #expect(model.pending == nil)
    model.observe(autoplaySnapshot(), context: autoplayEpisode(1), sessionID: session, next: autoplayEpisode(2))
    #expect(model.pending == nil)
}

@MainActor
@Test func autoplayCancellationAndPlayNowDoNotLeaveAStaleCountdown() async throws {
    let suite = "AutoplayTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = EpisodeAutoplayModel(defaults: defaults)
    model.isEnabled = true
    var advances = 0
    model.onAdvance = { _, _ in advances += 1 }
    let session = UUID()
    model.observe(autoplaySnapshot(), context: autoplayEpisode(1), sessionID: session, next: autoplayEpisode(2))
    model.cancel()
    model.observe(autoplaySnapshot(), context: autoplayEpisode(1), sessionID: session, next: autoplayEpisode(2))
    #expect(model.pending == nil)
    #expect(advances == 0)
    model.observe(autoplaySnapshot(), context: autoplayEpisode(1), sessionID: UUID(), next: autoplayEpisode(2))
    model.playNow()
    model.playNow()
    for _ in 0..<100 where advances == 0 { await Task.yield() }
    #expect(advances == 1)
    #expect(model.pending == nil)
    model.observe(autoplaySnapshot(), context: autoplayEpisode(1), sessionID: UUID(), next: autoplayEpisode(2))
    model.isEnabled = false
    #expect(model.pending == nil)
    #expect(!EpisodeAutoplayModel(defaults: defaults).isEnabled)
    model.cancel()
}

@MainActor
@Test func autoplayRejectsFailuresMissingDestinationsAndChangedPlayback() throws {
    let suite = "AutoplayTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = EpisodeAutoplayModel(defaults: defaults)
    model.isEnabled = true
    for state in [autoplaySnapshot(ended: false), autoplaySnapshot(failed: true), autoplaySnapshot(seeking: true)] {
        model.observe(state, context: autoplayEpisode(1), sessionID: UUID(), next: autoplayEpisode(2))
        #expect(model.pending == nil)
    }
    for next in [nil, autoplayEpisode(3), autoplayEpisode(2, season: 2)] {
        model.observe(autoplaySnapshot(), context: autoplayEpisode(1), sessionID: UUID(), next: next)
        #expect(model.pending == nil)
    }
    let session = UUID()
    model.observe(autoplaySnapshot(), context: autoplayEpisode(1), sessionID: session, next: autoplayEpisode(2))
    #expect(model.pending != nil)
    model.observe(autoplaySnapshot(), context: autoplayEpisode(1), sessionID: session, next: nil)
    #expect(model.pending == nil)
    model.observe(autoplaySnapshot(), context: autoplayEpisode(1), sessionID: UUID(), next: autoplayEpisode(2))
    model.observe(autoplaySnapshot(ended: false), context: autoplayEpisode(1), sessionID: UUID(), next: autoplayEpisode(2))
    #expect(model.pending == nil)
    model.cancel()
}
