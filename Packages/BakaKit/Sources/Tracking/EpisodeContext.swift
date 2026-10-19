import Catalog
import Foundation

/// A verified title association and a concrete Kinopub episode, independent of temporary media URLs.
public struct EpisodeContext: Codable, Hashable, Identifiable, Sendable {
    public let animeID: AnimeID
    public let title: String
    public let kind: String
    public let kinopubItemID: Int64
    public let season: Int
    public let episode: Int
    public var id: String { "\(animeID.rawValue):\(kinopubItemID):\(season):\(episode)" }
    public var label: String {
        season == 0 ? "Movie" : String(format: "S%02dE%02d", season, episode)
    }

    public init(animeID: AnimeID, title: String, kind: String, kinopubItemID: Int64, season: Int, episode: Int) {
        self.animeID = animeID; self.title = title; self.kind = kind
        self.kinopubItemID = kinopubItemID; self.season = season; self.episode = episode
    }

    public func selectingEpisode(itemID: Int64, season: Int, episode: Int) -> EpisodeContext? {
        guard kinopubItemID == itemID, self.season == season else { return nil }
        let value = EpisodeContext(animeID: animeID, title: title, kind: kind, kinopubItemID: itemID,
                                   season: season, episode: episode)
        return value.isValid ? value : nil
    }

    public var isValid: Bool {
        animeID.rawValue > 0 && kinopubItemID > 0 && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && title.utf8.count <= 2048 && (1...100000).contains(episode)
            && ((1...999).contains(season) || (season == 0 && episode == 1 && kind == "movie"))
    }
}
