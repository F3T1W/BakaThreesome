import Catalog
import Foundation
import Playback
import Testing
import Tracking

private func episode(_ number: Int = 2) -> EpisodeContext {
    EpisodeContext(animeID: AnimeID(rawValue: 1), title: "Example", kind: "tv", kinopubItemID: 10, season: 1, episode: number)
}
private func snapshot(_ seconds: Double, paused: Bool = false, idle: Bool = false, ended: Bool = false) -> PlaybackSnapshot {
    PlaybackSnapshot(isPaused: paused, isIdle: idle, position: PlaybackPosition(seconds: seconds, duration: 1200),
                     videoCodec: "h264", audioCodec: "aac", hasEnded: ended)
}

@Test func periodicPauseAndFinalCheckpointsKeepTheLatestSampleForTheBoundEpisode() async throws {
    let store = SwiftDataResumeStore(inMemory: true)
    let recorder = ResumeRecorder(context: episode(), store: store)
    let now = Date()
    #expect(try await recorder.capture(snapshot(10), at: now))
    #expect(try await !recorder.capture(snapshot(12), at: now.addingTimeInterval(2)))
    #expect(try await recorder.capture(snapshot(13, paused: true), at: now.addingTimeInterval(3)))
    #expect(try await !recorder.capture(snapshot(13, paused: true), at: now.addingTimeInterval(4)))
    #expect(try await recorder.capture(snapshot(20), at: now.addingTimeInterval(10)))
    #expect(try await !recorder.capture(snapshot(21), at: now.addingTimeInterval(11)))
    #expect(try await recorder.flush())
    let entry = try #require(try await store.entries().first)
    #expect(entry.context.episode == 2)
    #expect(entry.position.seconds == 21)
    #expect(entry.context.kinopubItemID == 10)
}

@Test func startupIdleAndInvalidPositionsCannotEraseAnExistingResumePoint() async throws {
    let store = SwiftDataResumeStore(inMemory: true)
    let recorder = ResumeRecorder(context: episode(), store: store)
    try await recorder.capture(snapshot(100))
    for state in [snapshot(0), snapshot(0, idle: true), snapshot(.nan), snapshot(2000)] {
        #expect(try await !recorder.capture(state, force: true))
    }
    try await recorder.flush()
    #expect(try await store.entries().first?.position.seconds == 100)
}

@Test func reachingTheEndRemovesOnlyThatEpisodeAndSeekingBackCanCreateANewResumePoint() async throws {
    let store = SwiftDataResumeStore(inMemory: true)
    let second = ResumeRecorder(context: episode(3), store: store)
    let first = ResumeRecorder(context: episode(2), store: store)
    try await second.capture(snapshot(30))
    try await first.capture(snapshot(40))
    try await first.capture(snapshot(1200, paused: true, ended: true))
    try await first.flush()
    #expect(try await store.entries().map(\.context.episode) == [3])
    try await first.capture(snapshot(50), force: true)
    #expect(try await store.entries().count == 2)
}

@Test func failedWritesAreRetriedWithTheLatestPosition() async throws {
    let store = FailingHistoryStore()
    let recorder = ResumeRecorder(context: episode(), store: store)
    await #expect(throws: (any Error).self) { try await recorder.capture(snapshot(50)) }
    await store.allowWrites()
    try await recorder.capture(snapshot(60), force: true)
    #expect(await store.entries().first?.position.seconds == 60)
}

@Test func diskRoundTripPreservesEpisodeIdentityAndAllowsAnIntentionalRestart() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("progress.store")
    let store = SwiftDataResumeStore(file: file)
    let now = Date()
    try await store.save(ResumeEntry(context: episode(), position: PlaybackPosition(seconds: 100, duration: 1200), updatedAt: now))
    let reopened = SwiftDataResumeStore(file: file)
    #expect(try await reopened.entries().first?.context == episode())
    try await reopened.save(ResumeEntry(context: episode(), position: PlaybackPosition(seconds: 5, duration: 1200),
                                       updatedAt: now.addingTimeInterval(10)))
    try await reopened.save(ResumeEntry(context: episode(), position: PlaybackPosition(seconds: 200, duration: 1200), updatedAt: now))
    #expect(try await reopened.entries().first?.position.seconds == 5)
    await #expect(throws: (any Error).self) {
        try await reopened.save(ResumeEntry(context: episode(), position: PlaybackPosition(seconds: .infinity, duration: 1200), updatedAt: now))
    }
    try await reopened.remove(id: episode().id)
    #expect(try await reopened.entries().isEmpty)
}

private actor FailingHistoryStore: ResumeHistoryStore {
    private var canWrite = false
    private var values: [ResumeEntry] = []
    func allowWrites() { canWrite = true }
    func entries() -> [ResumeEntry] { values }
    func save(_ entry: ResumeEntry) throws {
        guard canWrite else { throw CocoaError(.fileWriteNoPermission) }
        values = [entry]
    }
    func remove(id: String) { values.removeAll { $0.id == id } }
}

@Test func episodeSelectionCannotCrossTheConfirmedTitleOrSeason() {
    let bound = episode()
    #expect(bound.selectingEpisode(itemID: 10, season: 1, episode: 4)?.episode == 4)
    #expect(bound.selectingEpisode(itemID: 11, season: 1, episode: 4) == nil)
    #expect(bound.selectingEpisode(itemID: 10, season: 2, episode: 4) == nil)
    #expect(bound.selectingEpisode(itemID: 10, season: 1, episode: 0) == nil)
}

@Test func failedMediaCannotEraseTheLastCheckpointEvenIfEOFIsAlsoReported() async throws {
    let store = SwiftDataResumeStore(inMemory: true)
    let recorder = ResumeRecorder(context: episode(), store: store)
    let now = Date()
    try await recorder.capture(snapshot(100), at: now)
    try await recorder.capture(snapshot(102), at: now.addingTimeInterval(2))
    let failed = PlaybackSnapshot(isPaused: false, isIdle: false,
                                  position: PlaybackPosition(seconds: 0, duration: 1200),
                                  videoCodec: "h264", hasEnded: true, hasFailed: true)
    #expect(try await !recorder.capture(failed, force: true))
    try await recorder.flush()
    #expect(try await store.entries().first?.position.seconds == 102)
    let resumed = ResumeRecorder(context: episode(), store: store)
    try await resumed.capture(snapshot(103), at: now.addingTimeInterval(3), force: true)
    #expect(try await store.entries().first?.position.seconds == 103)
}
