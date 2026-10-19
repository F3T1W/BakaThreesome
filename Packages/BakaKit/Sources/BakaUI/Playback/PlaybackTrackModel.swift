import Foundation
import Observation
import Playback

@MainActor
@Observable
final class PlaybackTrackModel {
    private(set) var preferences: PlaybackTrackPreferences
    private(set) var available: [PlaybackTrack] = []
    private(set) var isConnected = false
    private(set) var isChanging = false
    private(set) var error: String?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var controller: (any PlaybackTrackController)?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var operation: Task<Void, Never>?
    private static let storageKey = "playback.trackPreferences"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preferences = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode(PlaybackTrackPreferences.self, from: $0) }
            ?? .originalWithRussianSubtitles
    }

    func selected(_ kind: PlaybackTrackKind) -> Int {
        available.first { $0.kind == kind && $0.isSelected }?.id ?? 0
    }

    func connect(_ controller: any PlaybackTrackController) async {
        disconnect()
        self.controller = controller
        isConnected = true
        await applyPreferences()
    }

    func disconnect() {
        generation = UUID()
        operation?.cancel()
        operation = nil
        controller = nil
        available = []
        isConnected = false
        isChanging = false
        error = nil
    }

    func refresh() async {
        guard !isChanging, let controller else { return }
        let current = generation
        do {
            let result = try await controller.tracks()
            guard current == generation, !Task.isCancelled, !isChanging else { return }
            if available != result { available = result }
        } catch {
            guard current == generation, !Task.isCancelled else { return }
            self.error = "Track information is unavailable. Try selecting a track again."
        }
    }

    func select(_ id: Int, kind: PlaybackTrackKind) {
        guard !isChanging, let controller else { return }
        let track = available.first { $0.id == id && $0.kind == kind }
        guard id == 0 || track != nil else { return }
        let current = generation
        isChanging = true
        error = nil
        operation = Task {
            defer { if current == generation { isChanging = false } }
            do {
                try await controller.selectTrack(id == 0 ? nil : id, kind: kind)
                let result = try await controller.tracks()
                guard current == generation, !Task.isCancelled else { return }
                if available != result { available = result }
                guard selected(kind) == id else { throw PlaybackError.propertyUnavailable }
                let preference = PlaybackTrackPreference(language: track?.language ?? "",
                                                         title: track?.title, isEnabled: id != 0)
                if kind == .audio { preferences.audio = preference }
                else { preferences.subtitles = preference }
                persist()
            } catch {
                guard current == generation, !Task.isCancelled else { return }
                self.error = "The track could not be changed. Your saved preference was kept."
            }
        }
    }

    func restoreDefaults() {
        guard !isChanging else { return }
        preferences = .originalWithRussianSubtitles
        persist()
        operation = Task { await applyPreferences() }
    }

    private func applyPreferences() async {
        guard let controller else { return }
        let current = generation
        isChanging = true
        error = nil
        defer { if current == generation { isChanging = false } }
        do {
            let result = try await controller.tracks()
            guard current == generation, !Task.isCancelled else { return }
            var notices: [String] = []
            for kind in [PlaybackTrackKind.audio, .subtitle] {
                let preference = kind == .audio ? preferences.audio : preferences.subtitles
                let preferred = preference.preferred(in: result, kind: kind)
                if let preferred {
                    if !preferred.isSelected { try await controller.selectTrack(preferred.id, kind: kind) }
                } else if !preference.isEnabled || kind == .subtitle {
                    try await controller.selectTrack(nil, kind: kind)
                }
                guard current == generation, !Task.isCancelled else { return }
                if preference.isEnabled, preferred == nil {
                    notices.append(kind == .audio ? "Preferred audio is unavailable; using the current track."
                                   : "Preferred subtitles are unavailable; subtitles are off.")
                }
            }
            let updated = try await controller.tracks()
            guard current == generation, !Task.isCancelled else { return }
            if available != updated { available = updated }
            error = notices.isEmpty ? nil : notices.joined(separator: " ")
        } catch {
            guard current == generation, !Task.isCancelled else { return }
            self.error = "Track preferences could not be applied. Use the track selectors to retry."
            if let updated = try? await controller.tracks(), current == generation { available = updated }
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: Self.storageKey) }
    }
}
