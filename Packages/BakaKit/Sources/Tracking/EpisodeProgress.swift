import Foundation

public struct EpisodeNumbering: Codable, Equatable, Identifiable, Sendable {
    public let userID: Int64
    public let context: EpisodeContext
    public let shikimoriEpisode: Int
    public var id: String { "\(userID):\(context.animeID.rawValue):\(context.kinopubItemID):\(context.season)" }

    public init(userID: Int64, context: EpisodeContext, shikimoriEpisode: Int) {
        self.userID = userID; self.context = context; self.shikimoriEpisode = shikimoriEpisode
    }
    public var isValid: Bool { userID > 0 && context.isValid && (1...100000).contains(shikimoriEpisode) }
    public func episode(for candidate: EpisodeContext, userID: Int64) -> Int? {
        guard isValid, candidate.isValid, self.userID == userID,
              context.animeID == candidate.animeID, context.kinopubItemID == candidate.kinopubItemID,
              context.season == candidate.season else { return nil }
        let number = shikimoriEpisode + candidate.episode - context.episode
        return (1...100000).contains(number) ? number : nil
    }
}

/// An absolute, account-bound observation; replaying it never increments a rate twice.
public struct WatchedEpisode: Codable, Equatable, Identifiable, Sendable {
    public let userID: Int64
    public let context: EpisodeContext
    public let number: Int
    public var id: String { "\(userID):\(context.animeID.rawValue):\(number)" }
    public init(userID: Int64, context: EpisodeContext, number: Int) {
        self.userID = userID; self.context = context; self.number = number
    }
    public var isValid: Bool { userID > 0 && context.isValid && (1...100000).contains(number) }
}

public enum ProgressDecision: Equatable, Sendable {
    case alreadyApplied, advance, waiting(String)
}

public enum EpisodeProgressPolicy {
    public static func decision(number: Int, current: Int?, total: Int, status: WatchStatus?) -> ProgressDecision {
        guard (1...100000).contains(number), total >= 0, total == 0 || number <= total else {
            return .waiting("The episode number is outside this Shikimori title. Check the numbering.")
        }
        guard let current, let status else {
            return .waiting("Add this title to Watching on Shikimori before syncing progress.")
        }
        guard status != .rewatching else {
            return .waiting("Automatic progress is paused for Rewatching. Update rewatch progress manually.")
        }
        if current >= number { return .alreadyApplied }
        guard status == .watching else {
            return .waiting("Move this title to Watching before syncing progress. Its current status was kept.")
        }
        guard number == current + 1 else {
            return .waiting("Earlier episodes are missing on Shikimori. Update them manually or watch them first.")
        }
        return .advance
    }
}

public protocol EpisodeProgressClient: Sendable {
    func advance(_ episode: WatchedEpisode) async throws -> ProgressDecision
}

public struct ProgressJournalSnapshot: Codable, Sendable {
    public var version = 1
    public var numbering: [EpisodeNumbering] = []
    public var pending: [WatchedEpisode] = []
    public init() {}
}

/// Removes an outbox entry only after a successful reconciliation. Unknown outcomes remain retryable.
public struct ProgressDelivery: Sendable {
    private let journal: ProgressJournal
    private let client: any EpisodeProgressClient
    public init(journal: ProgressJournal, client: any EpisodeProgressClient) {
        self.journal = journal; self.client = client
    }
    public func deliver(_ episode: WatchedEpisode, for userID: Int64) async throws -> ProgressDecision {
        guard episode.isValid, episode.userID == userID else { throw CocoaError(.coderInvalidValue) }
        let decision = try await client.advance(episode)
        switch decision {
        case .advance, .alreadyApplied: try await journal.remove(id: episode.id)
        case .waiting: break
        }
        return decision
    }
}
