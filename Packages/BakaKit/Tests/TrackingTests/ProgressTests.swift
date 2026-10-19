import Catalog
import Foundation
import Playback
import Testing
import Tracking

private func media(_ position: Double, duration: Double = 100, paused: Bool = false,
                   seeking: Bool = false, speed: Double = 1) -> PlaybackSnapshot {
    PlaybackSnapshot(isPaused: paused, isIdle: false, position: PlaybackPosition(seconds: position, duration: duration),
                     videoCodec: "h264", speed: speed, isSeeking: seeking)
}

@Test func ninetyPercentRequiresUniqueNormallyPlayedIntervals() {
    var coverage = WatchedCoverage()
    for second in stride(from: 0, through: 90, by: 2) {
        coverage.observe(media(Double(second)), at: Double(second))
    }
    #expect(coverage.isComplete)
    #expect(abs(coverage.fraction - 0.9) < 0.001)
}

@Test func seekingToTheEndPausingAndLongGapsCannotCompleteAnEpisode() {
    var coverage = WatchedCoverage()
    coverage.observe(media(0), at: 0)
    coverage.observe(media(99), at: 2)
    coverage.observe(media(100, paused: true), at: 4)
    coverage.observe(media(0), at: 6)
    coverage.observe(media(90), at: 96)
    #expect(coverage.fraction == 0)
    var seeking = WatchedCoverage()
    seeking.observe(media(0), at: 0)
    seeking.observe(media(2, seeking: true), at: 2)
    seeking.observe(media(4), at: 4)
    #expect(seeking.fraction == 0)
}

@Test func repeatedScenesAreCountedOnceAndSpeedIsRespected() {
    var coverage = WatchedCoverage()
    for pass in 0..<3 {
        for second in stride(from: 0, through: 40, by: 2) {
            coverage.observe(media(Double(second)), at: Double(pass * 42 + second))
        }
    }
    #expect(abs(coverage.fraction - 0.4) < 0.001)
    #expect(!coverage.isComplete)
    var fast = WatchedCoverage()
    for second in stride(from: 0, through: 92, by: 4) {
        fast.observe(media(Double(second), speed: 2), at: Double(second) / 2)
    }
    #expect(fast.isComplete)
}

@Test func invalidSamplesAndChangedMediaBreakTheCoverageChain() {
    var coverage = WatchedCoverage()
    coverage.observe(media(0), at: 0)
    coverage.observe(media(2), at: 2)
    coverage.observe(media(.nan), at: 3)
    coverage.observe(media(4), at: 4)
    #expect(coverage.fraction == 0.02)
    coverage.observe(media(6, duration: 200), at: 6)
    #expect(coverage.fraction == 0)
}

@Test func progressNeverSkipsMissingEpisodesOrChangesListStatuses() {
    #expect(EpisodeProgressPolicy.decision(number: 4, current: 3, total: 12, status: .watching) == .advance)
    #expect(EpisodeProgressPolicy.decision(number: 4, current: 4, total: 12, status: .watching) == .alreadyApplied)
    #expect(EpisodeProgressPolicy.decision(number: 4, current: 12, total: 12, status: .completed) == .alreadyApplied)
    for status in [WatchStatus.planned, .onHold, .dropped, .rewatching, .completed] {
        if case .waiting = EpisodeProgressPolicy.decision(number: 4, current: 3, total: 12, status: status) {} else {
            Issue.record("A status that needs manual action was advanced")
        }
    }
    for decision in [
        EpisodeProgressPolicy.decision(number: 5, current: 3, total: 12, status: .watching),
        EpisodeProgressPolicy.decision(number: 13, current: 12, total: 12, status: .watching),
        EpisodeProgressPolicy.decision(number: 1, current: nil, total: 12, status: nil)
    ] {
        if case .waiting = decision {} else { Issue.record("Unsafe progress update was accepted") }
    }
}

private func context(_ episode: Int = 13, season: Int = 1) -> EpisodeContext {
    EpisodeContext(animeID: AnimeID(rawValue: 1), title: "Example", kind: "tv", kinopubItemID: 10,
                   season: season, episode: episode)
}

@Test func numberingSupportsContinuouslyNumberedCoursAndIsBoundToAccountItemAndSeason() {
    let rule = EpisodeNumbering(userID: 42, context: context(), shikimoriEpisode: 1)
    #expect(rule.episode(for: context(14), userID: 42) == 2)
    #expect(rule.episode(for: context(12), userID: 42) == nil)
    #expect(rule.episode(for: context(14), userID: 43) == nil)
    #expect(rule.episode(for: context(14, season: 2), userID: 42) == nil)
}

@Test func outboxSurvivesRelaunchDeduplicatesAndKeepsAccountsSeparate() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("progress.json")
    let store = ProgressJournal(file: file)
    let episode = WatchedEpisode(userID: 42, context: context(), number: 1)
    try await store.confirm(EpisodeNumbering(userID: 42, context: context(), shikimoriEpisode: 1))
    try await store.enqueue(episode)
    try await store.enqueue(episode)
    try await store.enqueue(WatchedEpisode(userID: 43, context: context(), number: 1))
    let reopened = ProgressJournal(file: file)
    #expect(try await reopened.snapshot().pending.count == 2)
    #expect(try await reopened.snapshot().numbering.first?.shikimoriEpisode == 1)
    try await reopened.remove(id: episode.id)
    #expect(try await ProgressJournal(file: file).snapshot().pending.map(\.userID) == [43])
    let text = try String(contentsOf: file, encoding: .utf8)
    #expect(!text.contains("https:") && !text.contains("accessToken"))
}

@Test func corruptOutboxIsNeverSilentlyReplacedAndFailedWritesCanBeRetried() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("progress.json")
    let bad = Data("broken".utf8)
    try bad.write(to: file)
    let store = ProgressJournal(file: file)
    await #expect(throws: (any Error).self) { try await store.enqueue(WatchedEpisode(userID: 42, context: context(), number: 1)) }
    #expect(try Data(contentsOf: file) == bad)
    try FileManager.default.removeItem(at: file)
    try await store.enqueue(WatchedEpisode(userID: 42, context: context(), number: 1))
    #expect(try await store.snapshot().pending.count == 1)
}

@Test func deliveryKeepsFailuresAndBlockedUpdatesAndNeverUsesAnotherAccount() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ProgressJournal(file: directory.appendingPathComponent("progress.json"))
    let entry = WatchedEpisode(userID: 42, context: context(), number: 1)
    try await store.enqueue(entry)
    let client = RetryProgressClient()
    let delivery = ProgressDelivery(journal: store, client: client)
    await #expect(throws: (any Error).self) { try await delivery.deliver(entry, for: 43) }
    #expect(await client.calls == 0)
    await #expect(throws: (any Error).self) { try await delivery.deliver(entry, for: 42) }
    #expect(try await store.snapshot().pending.count == 1)
    await client.respond(.waiting("Missing earlier episodes"))
    #expect(try await delivery.deliver(entry, for: 42) == .waiting("Missing earlier episodes"))
    #expect(try await store.snapshot().pending.count == 1)
    await client.respond(.alreadyApplied)
    #expect(try await delivery.deliver(entry, for: 42) == .alreadyApplied)
    #expect(try await store.snapshot().pending.isEmpty)
}

private actor RetryProgressClient: EpisodeProgressClient {
    private var response: ProgressDecision?
    private(set) var calls = 0
    func respond(_ value: ProgressDecision) { response = value }
    func advance(_ episode: WatchedEpisode) throws -> ProgressDecision {
        calls += 1
        guard let response else { throw CocoaError(.fileReadUnknown) }
        return response
    }
}

@Test func aFailedAtomicWriteDoesNotAcknowledgeOrLoseTheIntentInMemory() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let blocker = root.appendingPathComponent("not-a-directory")
    try Data("fixture".utf8).write(to: blocker)
    let store = ProgressJournal(file: blocker.appendingPathComponent("progress.json"))
    let entry = WatchedEpisode(userID: 42, context: context(), number: 1)
    await #expect(throws: (any Error).self) { try await store.enqueue(entry) }
    #expect(try await store.snapshot().pending.isEmpty)
    try FileManager.default.removeItem(at: blocker)
    try await store.enqueue(entry)
    #expect(try await store.snapshot().pending == [entry])
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["BAKA_MPV_INTEGRATION"] == "1"))
func realMPVSamplesCanCompleteCoverageDuringNormalVideoPlayback() async throws {
    let executable = try #require(PlaybackEnvironment.discover().mpvURL)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let video = directory.appendingPathComponent("coverage.y4m")
    var frames = Data("YUV4MPEG2 W2 H2 F10:1 Ip A1:1 C420jpeg\n".utf8)
    for _ in 0..<100 {
        frames.append(Data("FRAME\n".utf8))
        frames.append(contentsOf: [16, 16, 16, 16, 128, 128])
    }
    try frames.write(to: video)
    let engine = MPVPlaybackEngine(executable: executable, headless: true)
    do {
        try await engine.start()
        try await engine.setPaused(true)
        try await engine.load(video)
        let ready = try await engine.snapshot()
        #expect(ready.videoCodec != nil)
        #expect(ready.speed == 1)
        #expect(!ready.isSeeking)
        var coverage = WatchedCoverage()
        let origin = ContinuousClock.now
        try await engine.setPaused(false)
        while !coverage.isComplete, origin.duration(to: .now) < .seconds(14) {
            let state = try await engine.snapshot()
            let elapsed = origin.duration(to: .now).components
            coverage.observe(state, at: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(coverage.isComplete)
        await engine.stop()
    } catch {
        await engine.stop()
        throw error
    }
}
