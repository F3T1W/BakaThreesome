import Foundation
@testable import Playback
import Testing

@Suite(.enabled(if: ProcessInfo.processInfo.environment["BAKA_MPV_INTEGRATION"] == "1"))
struct TrackSwitchingIntegrationTests {
    @Test func languagesAreSelectedAndTracksChangeWithoutReloadingTheEpisode() async throws {
        let executable = try #require(PlaybackEnvironment.discover().mpvURL)
        let ffmpeg = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        guard FileManager.default.isExecutableFile(atPath: ffmpeg.path) else { return }
        let directory = try OwnedTemporaryDirectory()
        defer { directory.remove() }
        let subtitles = directory.url.appendingPathComponent("captions.srt")
        try Data("1\n00:00:00,000 --> 00:00:20,000\nExample subtitles\n".utf8).write(to: subtitles)
        let media = directory.url.appendingPathComponent("tracks.mkv")
        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = ["-v", "error", "-f", "lavfi", "-i", "color=size=16x16:rate=1:duration=20",
                             "-f", "lavfi", "-i", "anullsrc=r=8000:cl=mono", "-i", subtitles.path,
                             "-map", "0:v", "-map", "1:a", "-map", "1:a", "-map", "2:s", "-map", "2:s",
                             "-t", "20", "-c:v", "mpeg4", "-c:a", "aac", "-c:s", "srt",
                             "-metadata:s:a:0", "language=rus", "-metadata:s:a:1", "language=jpn",
                             "-metadata:s:s:0", "language=eng", "-metadata:s:s:1", "language=rus", media.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        let engine = MPVPlaybackEngine(executable: executable, headless: true)
        do {
            try await engine.start()
            try await engine.setPaused(true)
            try await engine.load(PlaybackSource(url: media, startSeconds: 5,
                                                trackPreferences: .originalWithRussianSubtitles))
            let tracks = try await engine.tracks()
            let japanese = try #require(tracks.first { $0.kind == .audio && $0.language == "jpn" })
            let russian = try #require(tracks.first { $0.kind == .subtitle && $0.language == "rus" })
            #expect(japanese.isSelected)
            #expect(russian.isSelected)
            let dubbed = try #require(tracks.first { $0.kind == .audio && $0.language == "rus" })
            try await engine.selectTrack(dubbed.id, kind: .audio)
            try await engine.selectTrack(nil, kind: .subtitle)
            let changed = try await engine.tracks()
            #expect(changed.first { $0.kind == .audio && $0.isSelected }?.id == dubbed.id)
            #expect(!changed.contains { $0.kind == .subtitle && $0.isSelected })
            #expect(try await engine.snapshot().position.seconds >= 4.9)
            try await engine.selectTrack(russian.id, kind: .subtitle)
            #expect(try await engine.tracks().contains { $0.kind == .subtitle && $0.id == russian.id && $0.isSelected })
            await engine.stop()
        } catch {
            await engine.stop()
            throw error
        }
    }
}
