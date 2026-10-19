import Foundation
@testable import Playback
import Testing

@Test func streamOptionsArePerFileAndKeepQuotedValuesIntact() throws {
    let url = try #require(URL(string: "https://media.example/master.m3u8?token=synthetic-secret"))
    let referrer = try #require(URL(string: "https://mirror.example/"))
    let source = try PlaybackSource(url: url, referrer: referrer, userAgent: "Example/1.0 \"quoted\"")
    #expect(source.mpvOptions["referrer"] == .string("https://mirror.example/"))
    #expect(source.mpvOptions["user-agent"] == .string("Example/1.0 \"quoted\""))
    #expect(source.mpvOptions["ytdl"] == .string("no"))
    #expect(try PlaybackSource(url: url).mpvOptions["referrer"] == nil)
    #expect(throws: PlaybackError.invalidMediaURL) {
        try PlaybackSource(url: url, userAgent: "valid\r\nCookie: injected")
    }
}

@Test func externalAudioUsesOneLiteralItemAndDoesNotCarryToTheNextSource() throws {
    let video = try #require(URL(string: "https://video.example/main.m3u8"))
    let audio = try #require(URL(string: "https://audio.example:443/audio.m3u8?token=synthetic,quoted%25value"))
    let source = try PlaybackSource(url: video, audioURL: audio)
    #expect(source.mpvOptions["audio-files-append"] == .string(audio.absoluteString))
    #expect(try PlaybackSource(url: video).mpvOptions["audio-files-append"] == nil)
    #expect(throws: PlaybackError.invalidMediaURL) {
        try PlaybackSource(url: video, audioURL: URL(string: "https://user:secret@audio.example/file.m3u8")!)
    }
}

@Test func originHeaderUsesOnlyThePageOriginAndIsLocalToItsSource() throws {
    let url = try #require(URL(string: "https://cdn.example/master.m3u8"))
    let origin = try #require(URL(string: "https://mirror.example/"))
    #expect(try PlaybackSource(url: url, origin: origin).mpvOptions["http-header-fields-append"] == .string("Origin: https://mirror.example"))
    #expect(try PlaybackSource(url: url).mpvOptions["http-header-fields-append"] == nil)
    #expect(throws: PlaybackError.invalidMediaURL) {
        try PlaybackSource(url: url, origin: URL(string: "https://mirror.example/private?token=synthetic")!)
    }
}

@Test func resumePositionIsValidatedAndAppliesOnlyToItsOwnFile() throws {
    let url = URL(string: "https://media.example/master.m3u8")!
    #expect(try PlaybackSource(url: url, startSeconds: 125.5).mpvOptions["start"] == .string("125.5"))
    #expect(try PlaybackSource(url: url).mpvOptions["start"] == nil)
    for value in [-1.0, .infinity, .nan] {
        #expect(throws: PlaybackError.invalidSeek) { try PlaybackSource(url: url, startSeconds: value) }
    }
}
