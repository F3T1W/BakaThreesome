import Foundation
@testable import Playback
import Testing

@Test func cachedCapabilitiesAreSharedAndInvalidatedWhenTheExecutableChanges() async throws {
    let directory = try OwnedTemporaryDirectory()
    defer { directory.remove() }
    let executable = directory.url.appendingPathComponent("synthetic-player")
    try Data("v1".utf8).write(to: executable)
    let counter = ProbeCounter()
    let cache = MPVCapabilityCache { url in try await counter.inspect(url) }
    async let first = cache.inspect(executable)
    async let second = cache.inspect(executable)
    _ = try await (first, second)
    #expect(await counter.calls == 1)
    _ = try await cache.inspect(executable)
    #expect(await counter.calls == 1)
    try Data("version-two".utf8).write(to: executable)
    _ = try await cache.inspect(executable)
    #expect(await counter.calls == 2)
    await cache.shutdown()
}

@Test func aFailedProbeDoesNotPoisonTheCapabilityCache() async throws {
    let counter = RecoveringProbe()
    let cache = MPVCapabilityCache { url in try await counter.inspect(url) }
    let executable = URL(fileURLWithPath: "/usr/bin/true")
    await #expect(throws: PlaybackError.probeFailed) { try await cache.inspect(executable) }
    _ = try await cache.inspect(executable)
    #expect(await counter.calls == 2)
    await cache.shutdown()
}

@Test func fastHLSProbingIsPerFileAndConservativeRetryPreservesSourceOptions() throws {
    let source = try PlaybackSource(url: URL(string: "https://example.com/manifest/master.m3u8?synthetic=1")!,
                                    referrer: URL(string: "https://example.com/")!, userAgent: "Synthetic Browser",
                                    audioURL: URL(string: "https://example.com/audio.m3u8")!,
                                    origin: URL(string: "https://example.com")!, startSeconds: 42.5)
    #expect(source.usesFastHLSStartup)
    #expect(source.mpvOptions["demuxer-lavf-probe-info"] == .string("nostreams"))
    #expect(source.mpvOptions["demuxer-lavf-o"] == .string("http_persistent=1,http_multiple=1"))
    let conservative = try source.conservativeStartup()
    #expect(!conservative.usesFastHLSStartup)
    #expect(conservative.mpvOptions["demuxer-lavf-o"] == .string("http_persistent=0,http_multiple=0"))
    #expect(conservative.mpvOptions["demuxer-lavf-probe-info"] == .string("auto"))
    for key in ["start", "user-agent", "referrer", "http-header-fields-append", "audio-files-append"] {
        #expect(conservative.mpvOptions[key] == source.mpvOptions[key])
    }
    let local = try PlaybackSource(url: URL(fileURLWithPath: "/tmp/example.m3u8"))
    #expect(!local.usesFastHLSStartup)
    let movie = try PlaybackSource(url: URL(string: "https://example.com/movie.mp4")!)
    #expect(!movie.usesFastHLSStartup)
}

private actor ProbeCounter {
    private(set) var calls = 0
    func inspect(_ url: URL) async throws -> PlayerCapabilities {
        calls += 1
        try await Task.sleep(for: .milliseconds(30))
        return PlayerCapabilities(version: "mpv synthetic", hasVapourSynth: true)
    }
}

private actor RecoveringProbe {
    private(set) var calls = 0
    func inspect(_ url: URL) throws -> PlayerCapabilities {
        calls += 1
        if calls == 1 { throw PlaybackError.probeFailed }
        return PlayerCapabilities(version: "mpv synthetic", hasVapourSynth: true)
    }
}
