import Foundation
import Playback

/// Bound to one immutable episode for the lifetime of one player, regardless of browser navigation.
public actor ResumeRecorder {
    public let context: EpisodeContext
    private let store: any ResumeHistoryStore
    private var lastEntry: ResumeEntry?
    private var savedEntry: ResumeEntry?
    private var lastSave: Date?
    private var lastPaused = false
    private var completed = false

    public init(context: EpisodeContext, store: any ResumeHistoryStore) {
        self.context = context; self.store = store
    }

    @discardableResult
    public func capture(_ snapshot: PlaybackSnapshot, at date: Date = .now, force: Bool = false) async throws -> Bool {
        guard context.isValid else { return false }
        if snapshot.hasEnded {
            guard !completed else { return false }
            try await store.remove(id: context.id)
            completed = true; lastEntry = nil; savedEntry = nil
            return true
        }
        guard !snapshot.isIdle, snapshot.videoCodec != nil else { return false }
        let entry = ResumeEntry(context: context, position: snapshot.position, updatedAt: date)
        guard entry.isValid else { return false }
        completed = false
        lastEntry = entry
        let pauseChanged = lastPaused != snapshot.isPaused
        lastPaused = snapshot.isPaused
        guard force || pauseChanged || (lastSave.map({ date.timeIntervalSince($0) >= 5 }) ?? true) else { return false }
        return try await persist(entry, at: date)
    }

    @discardableResult
    public func flush() async throws -> Bool {
        guard !completed, let lastEntry else { return false }
        return try await persist(lastEntry, at: .now)
    }

    private func persist(_ entry: ResumeEntry, at date: Date) async throws -> Bool {
        guard entry.position != savedEntry?.position else { return false }
        try await store.save(entry)
        savedEntry = entry
        lastSave = date
        return true
    }
}
