import Catalog
import Foundation

public enum WatchStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case planned, watching, rewatching, completed, onHold = "on_hold", dropped
    public var id: Self { self }
    public var title: String {
        switch self {
        case .planned: "Planned"
        case .watching: "Watching"
        case .rewatching: "Rewatching"
        case .completed: "Completed"
        case .onHold: "On Hold"
        case .dropped: "Dropped"
        }
    }
}

public struct AnimeUserRate: Codable, Identifiable, Sendable {
    public let id: Int64
    public let animeID: Int64
    public let status: WatchStatus
    public let episodes: Int
    public let score: Int
}

public struct AnimeListEntry: Codable, Identifiable, Sendable {
    public var id: Int64 { anime.id }
    public let anime: AnimeSummary
    public let rate: AnimeUserRate
}

public struct AnimeDetails: Codable, Sendable {
    public let anime: AnimeSummary
    public let rate: AnimeUserRate?
}
