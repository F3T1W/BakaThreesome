import Foundation
import Observation
import Playback
import Tracking

@MainActor
@Observable
final class EpisodeAutoplayModel {
    struct Pending {
        let source: EpisodeContext
        let destination: EpisodeContext
        let sessionID: UUID
    }

    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.storageKey)
            if !isEnabled { cancel() }
        }
    }
    private(set) var pending: Pending?
    private(set) var remainingSeconds = 0
    var onAdvance: (@MainActor (EpisodeContext, EpisodeContext) async -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let sleep: @Sendable () async throws -> Void
    @ObservationIgnored private var countdown: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var handledSession: UUID?
    private static let storageKey = "playback.autoplayNextEpisode"

    init(defaults: UserDefaults = .standard,
         sleep: @escaping @Sendable () async throws -> Void = { try await Task.sleep(for: .seconds(1)) }) {
        self.defaults = defaults; self.sleep = sleep
        isEnabled = defaults.bool(forKey: Self.storageKey)
    }

    func observe(_ snapshot: PlaybackSnapshot, context: EpisodeContext?, sessionID: UUID,
                 next: EpisodeContext?) {
        if let pending, pending.sessionID != sessionID || pending.source.id != context?.id
            || pending.destination.id != next?.id || !snapshot.hasEnded || snapshot.hasFailed {
            cancel()
        }
        guard snapshot.hasEnded, handledSession != sessionID else { return }
        // One offer per player session, including an offer the user cancels or declines.
        handledSession = sessionID
        guard isEnabled, !snapshot.hasFailed, !snapshot.isSeeking, snapshot.videoCodec != nil,
              let context, context.isValid, let next, next.isValid,
              next.animeID == context.animeID, next.kinopubItemID == context.kinopubItemID,
              next.season == context.season, context.season > 0, next.episode == context.episode + 1 else { return }
        cancel()
        pending = Pending(source: context, destination: next, sessionID: sessionID)
        remainingSeconds = 8
        let current = generation
        countdown = Task { [weak self, sleep] in
            for remaining in stride(from: 7, through: 0, by: -1) {
                do { try await sleep(); try Task.checkCancellation() }
                catch { return }
                guard let self, self.generation == current else { return }
                self.remainingSeconds = remaining
                if remaining == 0 { self.playNow() }
            }
        }
    }

    func playNow() {
        guard isEnabled, let pending else { return }
        cancel()
        countdown = Task { [weak self] in
            guard !Task.isCancelled else { return }
            await self?.onAdvance?(pending.source, pending.destination)
        }
    }

    func cancel() {
        generation = UUID()
        countdown?.cancel(); countdown = nil
        pending = nil
        remainingSeconds = 0
    }
}
