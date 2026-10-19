@testable import BakaUI
import Foundation
import Playback
import Testing

private actor TrackPlayer: PlaybackTrackController {
    var fail = false
    var values = [PlaybackTrack(id: 1, kind: .audio, language: "rus", isSelected: true),
                  PlaybackTrack(id: 2, kind: .audio, title: "Original", language: "jpn"),
                  PlaybackTrack(id: 3, kind: .subtitle, title: "Full", language: "rus")]
    var selections = 0
    func tracks() async throws -> [PlaybackTrack] { values }
    func selectTrack(_ id: Int?, kind: PlaybackTrackKind) async throws {
        if fail { throw PlaybackError.commandRejected }
        selections += 1
        values = values.map {
            PlaybackTrack(id: $0.id, kind: $0.kind, title: $0.title, language: $0.language,
                          isSelected: $0.kind == kind ? $0.id == id : $0.isSelected)
        }
    }
    func rejectChanges() { fail = true }
}

@MainActor
@Test func playerDefaultsManualSelectionAndOffPersistWithoutTrackIDs() async throws {
    let suite = "PlaybackTracksTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let player = TrackPlayer()
    let model = PlaybackTrackModel(defaults: defaults)
    await model.connect(player)
    #expect(model.selected(.audio) == 2)
    #expect(model.selected(.subtitle) == 3)
    model.select(0, kind: .subtitle)
    while model.isChanging { await Task.yield() }
    #expect(model.selected(.subtitle) == 0)
    let restored = PlaybackTrackModel(defaults: defaults)
    #expect(!restored.preferences.subtitles.isEnabled)
    let data = try #require(defaults.data(forKey: "playback.trackPreferences"))
    let json = String(decoding: data, as: UTF8.self)
    #expect(!json.contains("\"id\""))
    await player.rejectChanges()
    model.select(3, kind: .subtitle)
    while model.isChanging { await Task.yield() }
    #expect(!model.preferences.subtitles.isEnabled)
    #expect(model.error != nil)
    model.disconnect()
    #expect(!model.isConnected)
    #expect(model.available.isEmpty)
}

@MainActor
@Test func externalPlayerSelectionRefreshDoesNotReapplyPreferences() async throws {
    let player = TrackPlayer()
    let suite = "PlaybackTracksTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = PlaybackTrackModel(defaults: defaults)
    await model.connect(player)
    try await player.selectTrack(1, kind: .audio)
    let count = await player.selections
    await model.refresh()
    #expect(model.selected(.audio) == 1)
    #expect(await player.selections == count)
    #expect(model.preferences.audio.language == "ja")
}
