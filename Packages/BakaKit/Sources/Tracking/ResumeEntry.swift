import Catalog
import Foundation
import Playback

public struct ResumeEntry: Codable, Sendable {
    public let animeID: AnimeID
    public let episode: Int
    public let position: PlaybackPosition
    public let updatedAt: Date

    public init(animeID: AnimeID, episode: Int, position: PlaybackPosition, updatedAt: Date) {
        self.animeID = animeID
        self.episode = episode
        self.position = position
        self.updatedAt = updatedAt
    }
}
