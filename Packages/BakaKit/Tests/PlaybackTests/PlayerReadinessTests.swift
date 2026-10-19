import Foundation
import Playback
import Testing

@Test func transientPlayerTimeoutCanRecoverWhileFiltersInitialize() async throws {
    let player = ReadinessPlayer(timeouts: 1)
    let state = try await player.snapshot(until: ContinuousClock.now.advanced(by: .seconds(2)))
    #expect(state.videoCodec == "h264")
    #expect(await player.calls == 2)
}

@Test func unresponsivePlayerStillHasABoundedDeadlineAndDisconnectIsImmediate() async throws {
    let player = ReadinessPlayer(timeouts: Int.max)
    let start = ContinuousClock.now
    await #expect(throws: PlaybackError.timedOut) {
        try await player.snapshot(until: start.advanced(by: .milliseconds(30)))
    }
    #expect(start.duration(to: .now) < .seconds(1))
    let disconnected = ReadinessPlayer(timeouts: 0, disconnected: true)
    await #expect(throws: PlaybackError.disconnected) {
        try await disconnected.snapshot(until: ContinuousClock.now.advanced(by: .seconds(30)))
    }
    #expect(await disconnected.calls == 1)
}

@Test func cancellingReadinessWaitDoesNotStartAnotherSnapshot() async throws {
    let player = ReadinessPlayer(timeouts: Int.max)
    let task = Task { try await player.snapshot(until: ContinuousClock.now.advanced(by: .seconds(30))) }
    while await player.calls == 0 { await Task.yield() }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(await player.calls == 1)
}

private actor ReadinessPlayer: PlaybackEngine {
    private let timeouts: Int
    private let disconnected: Bool
    private(set) var calls = 0

    init(timeouts: Int, disconnected: Bool = false) {
        self.timeouts = timeouts
        self.disconnected = disconnected
    }

    func snapshot() throws -> PlaybackSnapshot {
        calls += 1
        if disconnected { throw PlaybackError.disconnected }
        if calls <= timeouts { throw PlaybackError.timedOut }
        return PlaybackSnapshot(isPaused: false, isIdle: false,
                                position: PlaybackPosition(seconds: 1, duration: 100), videoCodec: "h264")
    }

    func start() async throws {}
    func load(_ source: PlaybackSource) async throws {}
    func setPaused(_ paused: Bool) async throws {}
    func seek(to seconds: Double) async throws {}
    func stop() async {}
}
