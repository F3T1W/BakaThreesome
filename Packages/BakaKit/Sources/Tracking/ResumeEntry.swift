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
    func save(_ entry: ResumeEntry) async throws
    func remove(id: String) async throws
}
