import Accounts
@testable import BakaUI
import Catalog
import Foundation
import Playback
import ShikimoriBridge
import Testing
import Tracking

private actor CoverageSessionStore: CredentialStore {
    func read(_ key: CredentialKey) throws -> Data? {
        Data("""
        {"credentials":{"clientID":"synthetic-client","clientSecret":"synthetic-secret"},
         "tokens":{"accessToken":"synthetic-access","refreshToken":"synthetic-refresh","expiresAt":4102444800},
         "profile":{"id":42,"nickname":"Example"}}
        """.utf8)
    }
    func write(_ data: Data, for key: CredentialKey) throws {}
    func delete(_ key: CredentialKey) throws {}
}
private actor OfflineCoverageTransport: BridgeTransport {
    func exchange(_ data: Data, cancelSafe: Bool) async throws -> Data { throw ShikimoriError.disconnected }
    func shutdown() async {}
}

@MainActor
@Test func progressModelRestoresPartialCoverageAndQueuesOnlyAfterCombinedThreshold() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("progress-model-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let suite = "ProgressPersistenceTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let shikimori = ShikimoriModel(client: ShikimoriClient(transport: OfflineCoverageTransport()), store: CoverageSessionStore())
    await shikimori.restore()
    #expect(shikimori.snapshot.profile?.id == 42)
    let context = EpisodeContext(animeID: AnimeID(rawValue: 7), title: "Example", kind: "tv",
                                 kinopubItemID: 42, season: 1, episode: 1)
    let journalFile = directory.appendingPathComponent("journal.json")
    let coverageFile = directory.appendingPathComponent("coverage.json")
    let firstJournal = ProgressJournal(file: journalFile)
    let first = ProgressSyncModel(shikimori: shikimori, store: firstJournal,
                                  coverageStore: WatchedCoverageStore(file: coverageFile), defaults: defaults)
    first.isEnabled = true
    await first.start()
    await first.confirm(context, number: 1)
    await first.begin(context)
    func sample(_ second: Int) -> PlaybackSnapshot {
        PlaybackSnapshot(isPaused: false, isIdle: false, position: .init(seconds: Double(second), duration: 100), videoCodec: "h264")
    }
    for second in stride(from: 0, through: 50, by: 2) { await first.capture(sample(second), at: Double(second)) }
    await first.begin(nil)
    #expect(try await firstJournal.snapshot().pending.isEmpty)
    await first.shutdown()
    let secondJournal = ProgressJournal(file: journalFile)
    let second = ProgressSyncModel(shikimori: shikimori, store: secondJournal,
                                   coverageStore: WatchedCoverageStore(file: coverageFile), defaults: defaults)
    await second.start()
    await second.begin(context)
    for position in stride(from: 50, through: 88, by: 2) { await second.capture(sample(position), at: Double(position + 1000)) }
    #expect(try await secondJournal.snapshot().pending.isEmpty)
    await second.capture(sample(90), at: 1090)
    #expect(try await secondJournal.snapshot().pending.map(\.number) == [1])
    await second.shutdown()
    await shikimori.shutdown()
}
