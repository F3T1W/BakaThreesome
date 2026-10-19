import Catalog
import Foundation
import Playback
import Testing
import Tracking

private func coverageMedia(_ second: Double, duration: Double = 100) -> PlaybackSnapshot {
    PlaybackSnapshot(isPaused: false, isIdle: false, position: PlaybackPosition(seconds: second, duration: duration), videoCodec: "h264")
}
private func coverageEpisode(user: Int64 = 1, number: Int = 1, season: Int = 1) -> WatchedEpisode {
    WatchedEpisode(userID: user, context: EpisodeContext(animeID: AnimeID(rawValue: 7), title: "Example", kind: "tv",
                                                        kinopubItemID: 42, season: season, episode: 1), number: number)
}

@Test func disjointSessionsRestoreUniqueCoverageWithoutCountingTheResumeGap() throws {
    var first = WatchedCoverage()
    for second in stride(from: 0, through: 50, by: 2) { first.observe(coverageMedia(Double(second)), at: Double(second)) }
    let bytes = try JSONEncoder().encode(#require(first.state))
    let saved = try JSONDecoder().decode(WatchedCoverageState.self, from: bytes)
    var resumed = WatchedCoverage(restoring: saved)
    resumed.observe(coverageMedia(70), at: 500)
    #expect(abs(resumed.fraction - 0.5) < 0.001)
    for second in stride(from: 70, through: 90, by: 2) { resumed.observe(coverageMedia(Double(second)), at: 500 + Double(second - 70)) }
    #expect(abs(resumed.fraction - 0.7) < 0.001)
    #expect(!resumed.isComplete)
    var third = WatchedCoverage(restoring: resumed.state)
    for second in stride(from: 50, through: 70, by: 2) { third.observe(coverageMedia(Double(second)), at: Double(second)) }
    #expect(third.isComplete)
    var repeated = WatchedCoverage(restoring: third.state)
    for second in stride(from: 0, through: 50, by: 2) { repeated.observe(coverageMedia(Double(second)), at: Double(second)) }
    #expect(abs(repeated.fraction - 0.9) < 0.001)
    repeated.observe(coverageMedia(2, duration: 200), at: 1000)
    #expect(repeated.fraction == 0)
}

@Test func coverageDiskRestartMergesCheckpointsAndIsolatesAccountsMappingAndMediaDuration() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("coverage-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("coverage.json")
    let first = WatchedCoverageStore(file: file)
    let state = WatchedCoverageState(duration: 100, intervals: [0...50])
    try await first.save(WatchedCoverageRecord(episode: coverageEpisode(), state: state, updatedAt: Date(timeIntervalSince1970: 100)))
    let restarted = WatchedCoverageStore(file: file)
    #expect(try await restarted.state(for: coverageEpisode()) == state)
    for other in [coverageEpisode(user: 2), coverageEpisode(number: 2), coverageEpisode(season: 2)] {
        #expect(try await restarted.state(for: other) == nil)
    }
    try await restarted.save(WatchedCoverageRecord(episode: coverageEpisode(), state: .init(duration: 100, intervals: [40...90]),
                                                   updatedAt: Date(timeIntervalSince1970: 200)))
    #expect(try await restarted.state(for: coverageEpisode())?.intervals == [0...90])
    try await restarted.save(WatchedCoverageRecord(episode: coverageEpisode(), state: .init(duration: 200, intervals: [0...10]),
                                                   updatedAt: Date(timeIntervalSince1970: 300)))
    try await restarted.save(WatchedCoverageRecord(episode: coverageEpisode(), state: state,
                                                   updatedAt: Date(timeIntervalSince1970: 150)))
    #expect(try await restarted.state(for: coverageEpisode())?.duration == 200)
    #expect(try await restarted.state(for: coverageEpisode())?.intervals == [0...10])
}

@Test func corruptCoverageIsPreservedAndInvalidIntervalsAreRejected() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("coverage-corrupt-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: file) }
    let original = Data("{broken".utf8)
    try original.write(to: file)
    let store = WatchedCoverageStore(file: file)
    await #expect(throws: (any Error).self) { try await store.state(for: coverageEpisode()) }
    await #expect(throws: (any Error).self) {
        try await store.save(WatchedCoverageRecord(episode: coverageEpisode(), state: .init(duration: 100, intervals: [0...50])))
    }
    #expect(try Data(contentsOf: file) == original)
    #expect(!WatchedCoverageState(duration: 100, intervals: [0...50, 40...60]).isValid)
    #expect(!WatchedCoverageState(duration: 100, intervals: [90...110]).isValid)
    #expect(!WatchedCoverageState(duration: .infinity, intervals: []).isValid)
}
