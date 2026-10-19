import Catalog
import Foundation
import Playback
import Testing
import Tracking

private func continuation(_ episode: Int, anime: Int64 = 7, date: Double) -> ResumeEntry {
    ResumeEntry(context: EpisodeContext(animeID: AnimeID(rawValue: anime), title: "Example", kind: "tv",
                                        kinopubItemID: 42, season: 1, episode: episode),
                position: PlaybackPosition(seconds: 30, duration: 1200), updatedAt: Date(timeIntervalSince1970: date))
}

@Test func continueWatchingShowsLatestActivityPerAnimeAndRetainsEveryEpisodePosition() async throws {
    let store = SwiftDataResumeStore(inMemory: true)
    for entry in [continuation(2, date: 100), continuation(3, date: 200), continuation(1, anime: 8, date: 150)] {
        try await store.save(entry)
    }
    let first = try await store.snapshot()
    #expect(first.entries.count == 3)
    #expect(first.continueEntries.map(\.context.animeID.rawValue) == [7, 8])
    #expect(first.continueEntries.first?.context.episode == 3)
    try await store.save(continuation(2, date: 300))
    #expect(try await store.snapshot().continueEntries.first?.context.episode == 2)
    try await store.save(continuation(3, date: 250))
    #expect(try await store.snapshot().continueEntries.first?.context.episode == 2)
}

@Test func completionAndRemovalNeverResurfaceAnOlderEpisodeAfterDiskRestart() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("continuation-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("history.store")
    let store = SwiftDataResumeStore(file: file)
    let old = continuation(2, date: 100)
    let latest = continuation(3, date: 200)
    try await store.save(old)
    try await store.save(latest)
    try await store.remove(id: latest.id)
    #expect(try await store.snapshot().continueEntries.isEmpty)
    let restarted = SwiftDataResumeStore(file: file)
    #expect(try await restarted.snapshot().continueEntries.isEmpty)
    #expect(try await restarted.entries().first?.id == old.id)
    try await restarted.save(continuation(2, date: 300))
    #expect(try await restarted.snapshot().continueEntries.first?.context.episode == 2)
}
