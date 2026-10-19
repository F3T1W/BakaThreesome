import Tracking

/// Adjacent playback requires a concrete, discovered destination in the linked season.
enum EpisodePlaybackNavigation {
    enum Direction: Int { case previous = -1, next = 1 }

    static func destination(from page: EpisodeContext?, playing: EpisodeContext?,
                            choices: [BrowserEpisodeChoice], direction: Direction) -> EpisodeContext? {
        guard let page, page.isValid, page.season > 0,
              playing == nil || playing?.id == page.id else { return nil }
        let number = page.episode + direction.rawValue
        guard let choice = choices.first(where: {
            $0.destination.itemID == page.kinopubItemID && $0.destination.season == page.season
                && $0.destination.episode == number
        }) else { return nil }
        return page.selectingEpisode(itemID: choice.destination.itemID, season: choice.destination.season,
                                     episode: choice.destination.episode)
    }
}
