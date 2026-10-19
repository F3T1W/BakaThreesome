import Catalog
import Foundation
@testable import Playback
import Testing
import Tracking

@Suite(.enabled(if: ProcessInfo.processInfo.environment["BAKA_HLS_INTEGRATION"] == "1"))
struct HLSRecoveryTests {
    @Test func HTTPFailurePreservesCheckpointAndARefreshedStreamRestoresPlayback() async throws {
        let executable = try #require(PlaybackEnvironment.discover().mpvURL)
        let directory = try OwnedTemporaryDirectory()
        defer { directory.remove() }
        let generator = try ManagedProcess(executable: URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg"), arguments: [
            "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc2=size=160x90:rate=24",
            "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000", "-t", "20",
            "-c:v", "libx264", "-preset", "ultrafast", "-g", "48", "-c:a", "aac",
            "-f", "hls", "-hls_time", "2", "-hls_playlist_type", "vod",
            "-hls_segment_filename", directory.url.appendingPathComponent("chunk%d.ts").path,
            directory.url.appendingPathComponent("media.m3u8").path
        ])
        try await generator.start()
        let generated = await generator.waitForExit(timeout: .seconds(15))
        await generator.stop()
        try #require(generated == 0)
        let serverFile = directory.url.appendingPathComponent("server.py")
        try """
        import http.server,os,time,urllib.parse
        os.chdir(os.path.dirname(__file__))
        class Handler(http.server.SimpleHTTPRequestHandler):
            def log_message(self,*args): pass
            def do_GET(self):
                path=urllib.parse.urlsplit(self.path).path
                if path.endswith('.ts'):
                    time.sleep(0.3)
                    if os.path.exists('broken'):
                        self.send_error(503)
                        return
                super().do_GET()
        server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
        with open('port','w') as output: output.write(str(server.server_port))
        server.serve_forever()
        """.write(to: serverFile, atomically: true, encoding: .utf8)
        let server = try ManagedProcess(executable: URL(fileURLWithPath: "/usr/bin/python3"), arguments: [serverFile.path])
        try await server.start()
        let player = MPVPlaybackEngine(executable: executable, headless: true)
        let replacement = MPVPlaybackEngine(executable: executable, headless: true)
        do {
            let portFile = directory.url.appendingPathComponent("port")
            let serverDeadline = ContinuousClock.now.advanced(by: .seconds(5))
            while !FileManager.default.fileExists(atPath: portFile.path), ContinuousClock.now < serverDeadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            let port = try String(contentsOf: portFile, encoding: .utf8)
            let url = try #require(URL(string: "http://127.0.0.1:\(port)/media.m3u8?attempt=first"))
            let context = EpisodeContext(animeID: AnimeID(rawValue: 1), title: "Recovery fixture", kind: "tv",
                                         kinopubItemID: 42, season: 1, episode: 2)
            let historyFile = directory.url.appendingPathComponent("history.store")
            let store = SwiftDataResumeStore(file: historyFile)
            let recorder = ResumeRecorder(context: context, store: store)
            try await player.start()
            try await player.load(PlaybackSource(url: url))
            var state = try await player.snapshot()
            let readyDeadline = ContinuousClock.now.advanced(by: .seconds(6))
            while (state.position.seconds < 0.25 || state.videoCodec == nil || state.audioCodec == nil),
                  ContinuousClock.now < readyDeadline {
                try await Task.sleep(for: .milliseconds(50))
                state = try await player.snapshot()
            }
            try #require(state.videoCodec != nil && state.audioCodec != nil && state.position.seconds >= 0.25)
            try await recorder.capture(state, force: true)
            let failure = directory.url.appendingPathComponent("broken")
            try Data().write(to: failure)
            let failureDeadline = ContinuousClock.now.advanced(by: .seconds(30))
            while !state.hasFailed, ContinuousClock.now < failureDeadline {
                try await Task.sleep(for: .milliseconds(100))
                state = try await player.snapshot()
                try await recorder.capture(state)
            }
            try #require(state.hasFailed)
            #expect(!state.hasEnded)
            #expect(try await !recorder.capture(state, force: true))
            try await recorder.flush()
            await player.stop()
            let restartedStore = SwiftDataResumeStore(file: historyFile)
            let saved = try #require(try await restartedStore.snapshot().continueEntries.first)
            #expect(saved.id == context.id)
            #expect(saved.position.seconds > 0 && saved.position.seconds < 20)
            try FileManager.default.removeItem(at: failure)
            let refreshed = try #require(URL(string: "http://127.0.0.1:\(port)/media.m3u8?attempt=refreshed"))
            try await replacement.start()
            try await replacement.setPaused(true)
            try await replacement.load(PlaybackSource(url: refreshed, startSeconds: saved.position.seconds))
            var resumed = try await replacement.snapshot()
            let restoredDeadline = ContinuousClock.now.advanced(by: .seconds(6))
            while (resumed.videoCodec == nil || resumed.audioCodec == nil || abs(resumed.position.seconds - saved.position.seconds) > 0.2),
                  ContinuousClock.now < restoredDeadline {
                try await Task.sleep(for: .milliseconds(50))
                resumed = try await replacement.snapshot()
            }
            #expect(!resumed.hasFailed)
            #expect(resumed.videoCodec != nil && resumed.audioCodec != nil)
            #expect(abs(resumed.position.seconds - saved.position.seconds) <= 0.2)
            try await replacement.setPaused(false)
            let advanceDeadline = ContinuousClock.now.advanced(by: .seconds(3))
            while resumed.position.seconds <= saved.position.seconds + 0.1, ContinuousClock.now < advanceDeadline {
                try await Task.sleep(for: .milliseconds(50))
                resumed = try await replacement.snapshot()
            }
            #expect(resumed.position.seconds > saved.position.seconds + 0.1)
            await replacement.stop()
            await server.stop()
        } catch {
            await player.stop(); await replacement.stop(); await server.stop()
            throw error
        }
    }
}
