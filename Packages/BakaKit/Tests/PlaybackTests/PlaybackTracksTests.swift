import Foundation
@testable import Playback
import Testing

@Test func trackPreferencesMatchLanguagesAndPreferFullSubtitles() throws {
    let tracks = [
        PlaybackTrack(id: 1, kind: .audio, language: "rus", isSelected: true),
        PlaybackTrack(id: 2, kind: .audio, language: "jpn"),
        PlaybackTrack(id: 1, kind: .subtitle, title: "01. Signs", language: "ru", isSelected: true, isForced: true),
        PlaybackTrack(id: 2, kind: .subtitle, title: "Full", language: "rus")
    ]
    let preferences = PlaybackTrackPreferences.originalWithRussianSubtitles
    #expect(preferences.audio.preferred(in: tracks, kind: .audio)?.id == 2)
    #expect(preferences.subtitles.preferred(in: tracks, kind: .subtitle)?.id == 2)
    #expect(PlaybackTrackPreference(language: "ru-RU", title: "02. Signs")
        .preferred(in: tracks, kind: .subtitle)?.id == 1)
    #expect(PlaybackTrackPreference(language: "ru", isEnabled: false).preferred(in: tracks, kind: .subtitle) == nil)
    #expect(PlaybackTrackPreference(language: "en").preferred(in: tracks, kind: .audio) == nil)
    let source = try PlaybackSource(url: URL(string: "https://media.example/master.m3u8")!)
        .preferringTracks(preferences).conservativeStartup()
    #expect(source.mpvOptions["alang"] == .string("ja"))
    #expect(source.mpvOptions["slang"] == .string("ru"))
    #expect(source.mpvOptions["subs-fallback"] == .string("no"))
    #expect(try PlaybackSource(url: source.url).mpvOptions["slang"] == nil)
}

@Test func trackMetadataIsValidatedAndSignedAddressesAreNeverLabels() throws {
    let tracks = try MPVPlaybackEngine.decodeTracks(.array([
        .object(["type": .string("video")]),
        .object(["type": .string("audio"), "id": .number(2), "lang": .string("jpn"),
                 "metadata": .object(["comment": .string("Original")]), "selected": .bool(true)]),
        .object(["type": .string("sub"), "id": .number(3), "lang": .string("rus"),
                 "title": .string("https://media.example/sub.srt?token=secret")])
    ]))
    #expect(tracks.count == 2)
    #expect(tracks[0].label.contains("Japanese"))
    #expect(tracks[0].isSelected)
    #expect(tracks[0].title == "Original")
    #expect(tracks[1].title == nil)
    for id in [-1.0, 0, 1.5, .infinity] {
        #expect(throws: PlaybackError.invalidResponse) {
            try MPVPlaybackEngine.decodeTracks(.array([.object(["type": .string("audio"), "id": .number(id)])]))
        }
    }
}
