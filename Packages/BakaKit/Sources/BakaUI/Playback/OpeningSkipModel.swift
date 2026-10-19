import Foundation
import Observation
import Playback

@MainActor
@Observable
final class OpeningSkipModel {
    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: "playback.showSkipOpening") }
    }
    private(set) var segment: OpeningSegment?
    private(set) var hasMarkers = false
    private(set) var isWorking = false
    private(set) var error: String?
    var onSeek: (@MainActor () -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var player: (any PlaybackEngine)?
    @ObservationIgnored private var markers: [OpeningSegment] = []
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var operation: Task<Void, Never>?
    var canSkip: Bool { isEnabled && segment != nil && !isWorking }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: "playback.showSkipOpening") as? Bool ?? true
    }

    func connect(player: any PlaybackEngine, chapters: any PlaybackChapterController) async {
        disconnect()
        self.player = player
        let current = generation
        guard let chapters = try? await chapters.chapters(), current == generation, !Task.isCancelled else { return }
        markers = OpeningSegment.from(chapters: chapters)
        hasMarkers = !markers.isEmpty
    }

    func observe(_ snapshot: PlaybackSnapshot) {
        guard !snapshot.hasEnded, !snapshot.hasFailed, !snapshot.isIdle, !snapshot.isSeeking,
              snapshot.videoCodec != nil, let duration = snapshot.position.duration else { segment = nil; return }
        segment = markers.first { $0.end < duration && $0.contains(snapshot.position.seconds) }
    }

    func skip() {
        guard canSkip, let segment, let player else { return }
        let current = generation
        isWorking = true; error = nil
        operation = Task {
            defer { if current == generation { isWorking = false } }
            do {
                let snapshot = try await player.snapshot()
                guard current == generation, !Task.isCancelled, isEnabled,
                      !snapshot.hasEnded, !snapshot.hasFailed, !snapshot.isSeeking,
                      let duration = snapshot.position.duration, segment.end < duration,
                      segment.contains(snapshot.position.seconds) else { return }
                onSeek?()
                try await player.seek(to: segment.end)
                guard current == generation, !Task.isCancelled else { return }
                onSeek?()
                self.segment = nil
            } catch {
                guard current == generation, !Task.isCancelled else { return }
                self.error = "The opening could not be skipped. Try again in the player."
            }
        }
    }

    func disconnect() {
        generation = UUID()
        operation?.cancel(); operation = nil; player = nil
        markers = []; segment = nil; hasMarkers = false; isWorking = false; error = nil
    }
}
