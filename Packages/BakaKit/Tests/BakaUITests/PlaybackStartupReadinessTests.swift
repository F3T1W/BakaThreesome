@testable import BakaUI
import Foundation
import Playback
import Testing

@Test func linkedEpisodeWaitsForVideoAndOptimizedHLSWaitsForAudio() throws {
    let source = try PlaybackSource(url: URL(string: "https://example.com/master.m3u8")!, hlsStartupMode: .selectedProgram)
    let video = PlaybackSnapshot(isPaused: false, isIdle: false, position: PlaybackPosition(seconds: 0, duration: nil), videoCodec: "h264")
    let audio = PlaybackSnapshot(isPaused: false, isIdle: false, position: PlaybackPosition(seconds: 0, duration: nil), audioCodec: "aac")
    let both = PlaybackSnapshot(isPaused: false, isIdle: false, position: PlaybackPosition(seconds: 0, duration: nil),
                                videoCodec: "h264", audioCodec: "aac")
    #expect(!PlaybackStartupReadiness.canBegin(video, source: source, linkedEpisode: true))
    #expect(!PlaybackStartupReadiness.canBegin(audio, source: source, linkedEpisode: true))
    #expect(PlaybackStartupReadiness.canBegin(both, source: source, linkedEpisode: true))
    #expect(PlaybackStartupReadiness.canBegin(video, source: try source.conservativeStartup(), linkedEpisode: true))
    #expect(PlaybackStartupReadiness.canBegin(audio, source: source, linkedEpisode: false))
}

@Test func startupWaitsForSeparateAudioAndRejectsIdleOrEmptySnapshots() throws {
    let source = try PlaybackSource(url: URL(string: "https://example.com/video.mp4")!,
                                    audioURL: URL(string: "https://example.com/audio.m4a")!)
    let video = PlaybackSnapshot(isPaused: false, isIdle: false, position: PlaybackPosition(seconds: 0, duration: nil), videoCodec: "h264")
    let idle = PlaybackSnapshot(isPaused: false, isIdle: true, position: PlaybackPosition(seconds: 0, duration: nil), videoCodec: "h264")
    let empty = PlaybackSnapshot(isPaused: false, isIdle: false, position: PlaybackPosition(seconds: 0, duration: nil))
    #expect(!PlaybackStartupReadiness.canBegin(video, source: source, linkedEpisode: false))
    #expect(!PlaybackStartupReadiness.canBegin(idle, source: source, linkedEpisode: false))
    #expect(!PlaybackStartupReadiness.canBegin(empty, source: source, linkedEpisode: false))
}
