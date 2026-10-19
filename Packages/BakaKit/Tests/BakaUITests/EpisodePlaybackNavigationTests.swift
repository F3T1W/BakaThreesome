@testable import BakaUI
import Catalog
import Kinopub
import Testing
import Tracking

private func episode(_ number: Int, item: Int64 = 42, season: Int = 1, anime: Int64 = 7) -> EpisodeContext {
    EpisodeContext(animeID: AnimeID(rawValue: anime), title: "Example", kind: "tv",
                   kinopubItemID: item, season: season, episode: number)
}

private func choice(_ number: Int, item: Int64 = 42, season: Int = 1) throws -> BrowserEpisodeChoice {
    BrowserEpisodeChoice(destination: try #require(KinopubEpisode(itemID: item, season: season, episode: number)),
                         title: "Episode \(number)")
}

@Test func adjacentEpisodeUsesDiscoveredIdentityAndPreservesTheShikimoriAssociation() throws {
    let current = episode(2)
    let choices = try [choice(3), choice(1), choice(2)]
    #expect(EpisodePlaybackNavigation.destination(from: current, playing: current, choices: choices,
                                                  direction: .next) == episode(3))
    #expect(EpisodePlaybackNavigation.destination(from: current, playing: nil, choices: choices,
                                                  direction: .previous) == episode(1))
    #expect(EpisodePlaybackNavigation.destination(from: episode(1), playing: nil, choices: choices,
                                                  direction: .previous) == nil)
    #expect(EpisodePlaybackNavigation.destination(from: episode(3), playing: nil, choices: choices,
                                                  direction: .next) == nil)
}

@Test func adjacentEpisodeDoesNotGuessAcrossGapsSeasonsTitlesOrBrowserChanges() throws {
    let current = episode(2)
    let unrelated = try [choice(4), choice(3, item: 99), choice(3, season: 2)]
    #expect(EpisodePlaybackNavigation.destination(from: current, playing: nil, choices: unrelated,
                                                  direction: .next) == nil)
    let choices = try [choice(3)]
    for playing in [episode(1), episode(2, item: 99), episode(2, season: 2), episode(2, anime: 99)] {
        #expect(EpisodePlaybackNavigation.destination(from: current, playing: playing, choices: choices,
                                                      direction: .next) == nil)
    }
    #expect(EpisodePlaybackNavigation.destination(from: nil, playing: current, choices: choices,
                                                  direction: .next) == nil)
    let movie = EpisodeContext(animeID: AnimeID(rawValue: 7), title: "Movie", kind: "movie",
                               kinopubItemID: 42, season: 0, episode: 1)
    #expect(EpisodePlaybackNavigation.destination(from: movie, playing: nil, choices: choices,
                                                  direction: .next) == nil)
    #expect(EpisodePlaybackNavigation.destination(from: episode(100000), playing: nil, choices: choices,
                                                  direction: .next) == nil)
}
