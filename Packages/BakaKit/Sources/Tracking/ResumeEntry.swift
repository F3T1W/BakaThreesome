import Foundation
import Playback

public struct ResumeEntry: Codable, Identifiable, Sendable {
    public let context: EpisodeContext
    public let position: PlaybackPosition
    public let updatedAt: Date
    public var id: String { context.id }

    public init(context: EpisodeContext, position: PlaybackPosition, updatedAt: Date) {
        self.context = context; self.position = position; self.updatedAt = updatedAt
    }

    public var isValid: Bool {
        guard context.isValid, position.seconds.isFinite, position.seconds > 0,
              let duration = position.duration, duration.isFinite, duration > 0,
              position.seconds <= duration, updatedAt.timeIntervalSince1970.isFinite else { return false }
        return true
    }
}

public protocol ResumeHistoryStore: Sendable {
    func entries() async throws -> [ResumeEntry]
    func snapshot() async throws -> ResumeHistorySnapshot
    func save(_ entry: ResumeEntry) async throws
    func remove(id: String) async throws
}

public struct ResumeHistorySnapshot: Sendable {
    public let entries: [ResumeEntry]
    public let continueEntries: [ResumeEntry]
    public init(entries: [ResumeEntry], latestEpisodeIDs: [Int64: String] = [:]) {
        self.entries = entries
        var seen: Set<Int64> = []
        continueEntries = entries.sorted {
            $0.updatedAt == $1.updatedAt ? $0.id < $1.id : $0.updatedAt > $1.updatedAt
        }.filter {
            let animeID = $0.context.animeID.rawValue
            if let latest = latestEpisodeIDs[animeID], latest != $0.id { return false }
            return seen.insert(animeID).inserted
        }
    }
}

public extension ResumeHistoryStore {
    func snapshot() async throws -> ResumeHistorySnapshot {
        ResumeHistorySnapshot(entries: try await entries())
    }
}
