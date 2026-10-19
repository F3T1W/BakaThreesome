import Foundation
@testable import Playback
import Testing

@Suite(.enabled(if: ProcessInfo.processInfo.environment["BAKA_HLS_INTEGRATION"] == "1"))
struct HLSStartupTests {
    @Test func fastAndConservativeHLSRetainVideoAudioAndResumePosition() async throws {
        let executable = try #require(PlaybackEnvironment.discover().mpvURL)
        let directory = try OwnedTemporaryDirectory()
        defer { directory.remove() }
        let ffmpeg = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        #expect(FileManager.default.isExecutableFile(atPath: ffmpeg.path))
        let generator = try ManagedProcess(executable: ffmpeg, arguments: [
            "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc2=size=160x90:rate=24",
            "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000", "-t", "8",
            "-c:v", "libx264", "-preset", "ultrafast", "-g", "48", "-c:a", "aac",
            "-f", "hls", "-hls_time", "2", "-hls_playlist_type", "vod",
            "-hls_segment_filename", directory.url.appendingPathComponent("chunk%d.ts").path,
            directory.url.appendingPathComponent("media.m3u8").path
        ])
        try await generator.start()
        let status = await generator.waitForExit(timeout: .seconds(15))
        await generator.stop()
        #expect(status == 0)
        try """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=400000,RESOLUTION=160x90,CODECS="avc1.42c00b,mp4a.40.2"
        media.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=160x90,CODECS="avc1.42c00b,mp4a.40.2"
        media.m3u8
        """.write(to: directory.url.appendingPathComponent("master.m3u8"), atomically: true, encoding: .utf8)
        let serverFile = directory.url.appendingPathComponent("server.py")
        try """
        import http.server,os,time
        os.chdir(os.path.dirname(__file__))
        class Handler(http.server.SimpleHTTPRequestHandler):
            def log_message(self,*args): pass
            def do_GET(self):
                time.sleep(0.05)
                super().do_GET()
        server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
        with open('port','w') as output: output.write(str(server.server_port))
        server.serve_forever()
        """.write(to: serverFile, atomically: true, encoding: .utf8)
        let server = try ManagedProcess(executable: URL(fileURLWithPath: "/usr/bin/python3"), arguments: [serverFile.path])
        try await server.start()
        do {
            let portFile = directory.url.appendingPathComponent("port")
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while !FileManager.default.fileExists(atPath: portFile.path), ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            let port = try String(contentsOf: portFile, encoding: .utf8)
            let url = try #require(URL(string: "http://127.0.0.1:\(port)/master.m3u8"))
            for fast in [false, true] {
                let engine = MPVPlaybackEngine(executable: executable, headless: true)
                do {
                    let requested = ContinuousClock.now
                    try await engine.start()
                    let launched = ContinuousClock.now
                    try await engine.setPaused(true)
                    try await engine.load(PlaybackSource(url: url, startSeconds: 2, fastHLSStartup: fast))
                    var state = try await engine.snapshot()
                    let readyDeadline = ContinuousClock.now.advanced(by: .seconds(5))
                    while (state.videoCodec == nil || state.audioCodec == nil || abs(state.position.seconds - 2) > 0.15),
                          ContinuousClock.now < readyDeadline {
                        try await Task.sleep(for: .milliseconds(20))
                        state = try await engine.snapshot()
                    }
                    #expect(state.videoCodec?.contains("H.264") == true)
                    #expect(state.audioCodec?.contains("AAC") == true)
                    #expect(abs(state.position.seconds - 2) < 0.15)
                    print("Synthetic HLS startup fast=\(fast): process=\(requested.duration(to: launched)), ready=\(requested.duration(to: .now))")
                    try await engine.setPaused(false)
                    let advanceDeadline = ContinuousClock.now.advanced(by: .seconds(4))
                    var position = try await engine.snapshot().position.seconds
                    while position <= 2, ContinuousClock.now < advanceDeadline {
                        try await Task.sleep(for: .milliseconds(50))
                        position = try await engine.snapshot().position.seconds
                    }
                    #expect(position > 2)
                    await engine.stop()
                } catch { await engine.stop(); throw error }
            }
            await server.stop()
        } catch { await server.stop(); throw error }
    }
}
