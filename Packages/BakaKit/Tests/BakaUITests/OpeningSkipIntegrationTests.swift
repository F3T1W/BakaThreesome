@testable import BakaUI
import Foundation
import Playback
import Testing

@Suite(.enabled(if: ProcessInfo.processInfo.environment["BAKA_MPV_INTEGRATION"] == "1"))
struct OpeningSkipIntegrationTests {
    @MainActor
    @Test func realMPVChaptersOfferAnOpeningAndSkipToItsKnownEnd() async throws {
        let executable = try #require(PlaybackEnvironment.discover().mpvURL)
        let ffmpeg = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        guard FileManager.default.isExecutableFile(atPath: ffmpeg.path) else { return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("opening-test-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let metadata = directory.appendingPathComponent("chapters.txt")
        let chapterText = ";FFMETADATA1\n[CHAPTER]\nTIMEBASE=1/1000\nSTART=0\nEND=2000\ntitle=Prologue\n" +
            "[CHAPTER]\nTIMEBASE=1/1000\nSTART=2000\nEND=7000\ntitle=Opening\n" +
            "[CHAPTER]\nTIMEBASE=1/1000\nSTART=7000\nEND=20000\ntitle=Story\n"
        try Data(chapterText.utf8).write(to: metadata)
        let media = directory.appendingPathComponent("episode.mkv")
        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = ["-v", "error", "-f", "lavfi", "-i", "color=size=16x16:rate=10:duration=20",
                             "-f", "ffmetadata", "-i", metadata.path, "-map", "0:v", "-map_metadata", "1",
                             "-map_chapters", "1", "-c:v", "mpeg4", media.path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        let suite = "OpeningIntegrationTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = OpeningSkipModel(defaults: defaults)
        defer { model.disconnect() }
        let player = MPVPlaybackEngine(executable: executable, headless: true)
        do {
            try await player.start()
            try await player.setPaused(true)
            try await player.load(PlaybackSource(url: media, startSeconds: 3))
            await model.connect(player: player, chapters: player)
            model.observe(try await player.snapshot())
            #expect(model.canSkip)
            model.skip()
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while model.isWorking, ContinuousClock.now < deadline { await Task.yield() }
            #expect(model.error == nil)
            #expect(try await player.snapshot().position.seconds >= 6.9)
            await player.stop()
        } catch {
            await player.stop()
            throw error
        }
    }
}
