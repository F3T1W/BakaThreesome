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
        let audioGenerator = try ManagedProcess(executable: ffmpeg, arguments: [
            "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "sine=frequency=220:sample_rate=48000",
            "-t", "8", "-c:a", "aac", "-f", "hls", "-hls_time", "2", "-hls_playlist_type", "vod",
            "-hls_segment_filename", directory.url.appendingPathComponent("audio%d.ts").path,
            directory.url.appendingPathComponent("audio.m3u8").path
        ])
        try await audioGenerator.start()
        let audioStatus = await audioGenerator.waitForExit(timeout: .seconds(15))
        await audioGenerator.stop()
        try #require(audioStatus == 0)
        try "WEBVTT\n\n00:00.000 --> 00:08.000\nExample subtitles\n".write(
            to: directory.url.appendingPathComponent("sub.vtt"), atomically: true, encoding: .utf8)
        try "#EXTM3U\n#EXT-X-TARGETDURATION:8\n#EXT-X-VERSION:3\n#EXTINF:8,\nsub.vtt\n#EXT-X-ENDLIST\n".write(
            to: directory.url.appendingPathComponent("sub.m3u8"), atomically: true, encoding: .utf8)
        var rich = ["#EXTM3U", "#EXT-X-VERSION:6"]
        rich.append("#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID=\"subs\",NAME=\"Russian\",LANGUAGE=\"ru\",URI=\"sub.m3u8\"")
        for group in 1...2 {
            for language in ["ja", "ru"] {
                rich.append("#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"a\(group)\",NAME=\"\(language)\",LANGUAGE=\"\(language)\",URI=\"audio.m3u8?group=\(group)&lang=\(language)\"")
            }
            rich.append("#EXT-X-STREAM-INF:BANDWIDTH=\(group * 400000),RESOLUTION=160x90,CODECS=\"avc1.42c00b,mp4a.40.2\",AUDIO=\"a\(group)\",SUBTITLES=\"subs\"")
            rich.append("media.m3u8?program=\(group)")
        }
        try rich.joined(separator: "\n").write(to: directory.url.appendingPathComponent("rich.m3u8"), atomically: true, encoding: .utf8)
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
            for (fast, mode) in [(false, HLSStartupMode.compatible), (true, .compatible), (false, .selectedProgram)] {
                let engine = MPVPlaybackEngine(executable: executable, headless: true)
                do {
                    let requested = ContinuousClock.now
                    try await engine.start()
                    let launched = ContinuousClock.now
                    try await engine.setPaused(true)
                    try await engine.load(PlaybackSource(url: url, startSeconds: 2, fastHLSStartup: fast, hlsStartupMode: mode))
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
            let richURL = try #require(URL(string: "http://127.0.0.1:\(port)/rich.m3u8"))
            for mode in HLSStartupMode.allCases {
                let player = MPVPlaybackEngine(executable: executable, headless: true, networkDiagnostics: true)
                do {
                    try await player.start()
                    try await player.setPaused(true)
                    try await player.load(PlaybackSource(url: richURL, startSeconds: 2,
                        trackPreferences: .originalWithRussianSubtitles, hlsStartupMode: mode))
                    let tracks = try await player.tracks()
                    if mode == .selectedProgram {
                        #expect(await player.networkDiagnostics().contains { $0.hasPrefix("HLS selected program: 2 → 1") })
                    }
                    #expect(tracks.contains { $0.kind == .audio && PlaybackTrackPreference.languageKey($0.language) == "ja" && $0.isSelected })
                    #expect(tracks.contains { $0.kind == .audio && PlaybackTrackPreference.languageKey($0.language) == "ru" })
                    #expect(tracks.contains { $0.kind == .subtitle && PlaybackTrackPreference.languageKey($0.language) == "ru" && $0.isSelected })
                    #expect(abs(try await player.snapshot().position.seconds - 2) < 0.15)
                    let dubbed = try #require(tracks.first { $0.kind == .audio && PlaybackTrackPreference.languageKey($0.language) == "ru" })
                    try await player.selectTrack(dubbed.id, kind: .audio)
                    #expect(try await player.tracks().contains { $0.id == dubbed.id && $0.kind == .audio && $0.isSelected })
                    if mode == .selectedProgram {
                        let original = try PlaybackSource(url: richURL, startSeconds: 2,
                            trackPreferences: .originalWithRussianSubtitles).conservativeStartup()
                        try await player.load(original)
                        let restored = try await player.tracks()
                        #expect(restored.filter { $0.kind == .audio }.count > tracks.filter { $0.kind == .audio }.count)
                        #expect(restored.contains { $0.kind == .subtitle && $0.isSelected })
                        #expect(abs(try await player.snapshot().position.seconds - 2) < 0.15)
                    }
                    await player.stop()
                } catch { await player.stop(); throw error }
            }
            await server.stop()
        } catch { await server.stop(); throw error }
    }
}
