import Foundation
@testable import Playback
import Testing

@Suite(.enabled(if: ProcessInfo.processInfo.environment["BAKA_MPV_INTEGRATION"] == "1"))
struct MPVIntegrationTests {
    @Test func installedPlayerSupportsProbeIPCAndRestart() async throws {
        let executable = try #require(PlaybackEnvironment.discover().mpvURL)
        let capabilities = try await MPVCapabilityProbe(executable: executable).inspect()
        #expect(capabilities.version.hasPrefix("mpv "))
        #expect(capabilities.hasVapourSynth)
        let engine = MPVPlaybackEngine(executable: executable, headless: true)
        try await PlayerIPCCheck().run(using: engine)
        try await PlayerIPCCheck().run(using: engine)
        await #expect(throws: PlaybackError.notRunning) { try await engine.snapshot() }
    }

    @Test func duplicateStartIsRejectedAndStopIsIdempotent() async throws {
        let executable = try #require(PlaybackEnvironment.discover().mpvURL)
        let engine = MPVPlaybackEngine(executable: executable, headless: true)
        do {
            try await engine.start()
            await #expect(throws: PlaybackError.alreadyRunning) { try await engine.start() }
            await #expect(throws: PlaybackError.alreadyRunning) {
                try await PlayerIPCCheck().run(using: engine)
            }
            #expect(try await engine.snapshot().isIdle)
            await engine.stop()
            await engine.stop()
        } catch {
            await engine.stop()
            throw error
        }
    }

    @Test func loadsQuotedFileNameAndSeeksThroughIPC() async throws {
        let executable = try #require(PlaybackEnvironment.discover().mpvURL)
        let directory = try OwnedTemporaryDirectory()
        defer { directory.remove() }
        let media = directory.url.appendingPathComponent("episode \"quoted\" & $(echo).wav")
        try silentWave().write(to: media)
        let engine = MPVPlaybackEngine(executable: executable, headless: true)
        do {
            try await engine.start()
            try await engine.setPaused(true)
            try await engine.load(media)
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            var state = try await engine.snapshot()
            while state.position.duration == nil, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(30))
                state = try await engine.snapshot()
            }
            #expect(state.isPaused)
            #expect(state.position.duration == 3)
            try await engine.seek(to: 1.25)
            state = try await engine.snapshot()
            while state.position.seconds < 1, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(30))
                state = try await engine.snapshot()
            }
            #expect(abs(state.position.seconds - 1.25) < 0.05)
            await engine.stop()
        } catch {
            await engine.stop()
            throw error
        }
    }

    @Test func pairsSeparateVideoAndAudioWithReservedPathCharacters() async throws {
        let executable = try #require(PlaybackEnvironment.discover().mpvURL)
        let directory = try OwnedTemporaryDirectory()
        defer { directory.remove() }
        let video = directory.url.appendingPathComponent("video.y4m")
        let audio = directory.url.appendingPathComponent("audio:,percent%quoted.wav")
        var frames = Data("YUV4MPEG2 W2 H2 F1:1 Ip A1:1 C420jpeg\n".utf8)
        for _ in 0..<3 {
            frames.append(Data("FRAME\n".utf8))
            frames.append(contentsOf: [16, 16, 16, 16, 128, 128])
        }
        try frames.write(to: video)
        try silentWave().write(to: audio)
        let engine = MPVPlaybackEngine(executable: executable, headless: true)
        do {
            try await engine.start()
            try await engine.setPaused(true)
            try await engine.load(PlaybackSource(url: video, audioURL: audio))
            let deadline = ContinuousClock.now.advanced(by: .seconds(4))
            var state = try await engine.snapshot()
            while (state.videoCodec == nil || state.audioCodec == nil), ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(40))
                state = try await engine.snapshot()
            }
            #expect(state.videoCodec != nil)
            #expect(state.audioCodec != nil)
            await engine.stop()
        } catch {
            await engine.stop()
            throw error
        }
    }

    @Test func failedFileLoadReportsItsEventInsteadOfPollingAnIdlePlayer() async throws {
        let executable = try #require(PlaybackEnvironment.discover().mpvURL)
        let directory = try OwnedTemporaryDirectory()
        defer { directory.remove() }
        let engine = MPVPlaybackEngine(executable: executable, headless: true)
        do {
            try await engine.start()
            await #expect(throws: PlaybackError.commandRejected) {
                try await engine.load(directory.url.appendingPathComponent("missing-video.mkv"))
            }
            await engine.stop()
        } catch {
            await engine.stop()
            throw error
        }
    }

    @Test func perFileResumeRestoresPositionAndReportsEndWithoutLeakingToTheNextFile() async throws {
        let executable = try #require(PlaybackEnvironment.discover().mpvURL)
        let directory = try OwnedTemporaryDirectory()
        defer { directory.remove() }
        let media = directory.url.appendingPathComponent("resume.wav")
        try silentWave().write(to: media)
        let engine = MPVPlaybackEngine(executable: executable, headless: true)
        do {
            try await engine.start()
            try await engine.setPaused(true)
            try await engine.load(PlaybackSource(url: media, startSeconds: 1.25))
            var state = try await engine.snapshot()
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while abs(state.position.seconds - 1.25) > 0.05, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(40))
                state = try await engine.snapshot()
            }
            #expect(abs(state.position.seconds - 1.25) < 0.05)
            try await engine.setPaused(false)
            while !state.hasEnded, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(40))
                state = try await engine.snapshot()
            }
            #expect(state.hasEnded)
            try await engine.load(PlaybackSource(url: media, startSeconds: 0))
            #expect(try await engine.snapshot().position.seconds < 0.1)
            await engine.stop()
        } catch {
            await engine.stop()
            throw error
        }
    }

    @Test func cancelledCheckStopsItsOwnedPlayer() async throws {
        let executable = try #require(PlaybackEnvironment.discover().mpvURL)
        let engine = MPVPlaybackEngine(executable: executable, headless: true)
        let task = Task { try await PlayerIPCCheck().run(using: engine) }
        task.cancel()
        do {
            try await task.value
            Issue.record("The check should have been cancelled.")
        } catch is CancellationError {
        }
        await #expect(throws: PlaybackError.notRunning) { try await engine.snapshot() }
    }
}

private func silentWave() -> Data {
    let sampleRate: UInt32 = 8_000
    let dataSize = sampleRate * 3 * 2
    var data = Data()
    func append(_ value: UInt32) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
    data.append(Data("RIFF".utf8))
    append(36 + dataSize)
    data.append(Data("WAVEfmt ".utf8))
    append(16)
    data.append(contentsOf: [1, 0, 1, 0])
    append(sampleRate)
    append(sampleRate * 2)
    data.append(contentsOf: [2, 0, 16, 0])
    data.append(Data("data".utf8))
    append(dataSize)
    data.append(Data(repeating: 0, count: Int(dataSize)))
    return data
}
