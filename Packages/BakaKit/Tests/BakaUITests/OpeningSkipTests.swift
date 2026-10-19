@testable import BakaUI
import Foundation
import Playback
import Testing

private actor OpeningPlayer: PlaybackEngine, PlaybackChapterController {
    var seconds: Double = 3
    var seekCount = 0
    func start() async throws {}
    func load(_ source: PlaybackSource) async throws {}
    func setPaused(_ paused: Bool) async throws {}
    func stop() async {}
    func chapters() async throws -> [PlaybackChapter] {
        [.init(title: "Prologue", seconds: 0), .init(title: "OP", seconds: 2), .init(title: "Story", seconds: 7)]
    }
    func snapshot() async throws -> PlaybackSnapshot {
        PlaybackSnapshot(isPaused: false, isIdle: false, position: .init(seconds: seconds, duration: 20), videoCodec: "h264")
    }
    func seek(to seconds: Double) async throws { self.seconds = seconds; seekCount += 1 }
    func advanceOutsideOpening() { seconds = 10 }
}

@MainActor
@Test func skipOpeningRechecksTheCurrentPositionAndNeverRunsAutomatically() async throws {
    let suite = "OpeningTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let player = OpeningPlayer()
    let model = OpeningSkipModel(defaults: defaults)
    await model.connect(player: player, chapters: player)
    model.observe(try await player.snapshot())
    #expect(model.hasMarkers)
    #expect(model.canSkip)
    #expect(await player.seekCount == 0)
    var interrupts = 0
    model.onSeek = { interrupts += 1 }
    model.skip()
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while model.isWorking, ContinuousClock.now < deadline { await Task.yield() }
    #expect(await player.seconds == 7)
    #expect(await player.seekCount == 1)
    #expect(interrupts == 2)
    #expect(model.segment == nil)
    model.isEnabled = false
    #expect(!OpeningSkipModel(defaults: defaults).isEnabled)
    model.disconnect()
    #expect(!model.hasMarkers)
}

@MainActor
@Test func staleOpeningButtonDoesNotSeekAfterThePlayerHasLeftThatSegment() async throws {
    let suite = "OpeningTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let player = OpeningPlayer()
    let model = OpeningSkipModel(defaults: defaults)
    await model.connect(player: player, chapters: player)
    model.observe(try await player.snapshot())
    await player.advanceOutsideOpening()
    model.skip()
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while model.isWorking, ContinuousClock.now < deadline { await Task.yield() }
    #expect(await player.seekCount == 0)
    #expect(await player.seconds == 10)
    model.disconnect()
}
