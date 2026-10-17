import Catalog

public struct EpisodeMapping: Codable, Sendable {
    public let animeID: AnimeID
    public let kinopubItemID: Int64
    public let season: Int
    public let episodeOffset: Int

    public init(animeID: AnimeID, kinopubItemID: Int64, season: Int, episodeOffset: Int) {
        self.animeID = animeID
        self.kinopubItemID = kinopubItemID
        self.season = season
        self.episodeOffset = episodeOffset
    }
}
