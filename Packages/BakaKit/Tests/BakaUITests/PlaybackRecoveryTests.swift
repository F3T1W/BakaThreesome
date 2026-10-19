@testable import BakaUI
import Catalog
import Foundation
import Playback
import Testing
import Tracking

@Test func recoveryReopensTheExactEpisodeWithoutRetainingAStreamAddress() {
    let context = EpisodeContext(animeID: AnimeID(rawValue: 1), title: "Example", kind: "tv",
                                 kinopubItemID: 123, season: 2, episode: 7)
    let point = PlaybackRecoveryPoint(context: context, origin: URL(string: "https://example.com")!, seconds: 123.5)
    #expect(point.isValid)
    #expect(point.pageURL.absoluteString == "https://example.com/item/view/123/s2e7")
    #expect(point.seconds == 123.5)
    let movie = EpisodeContext(animeID: AnimeID(rawValue: 2), title: "Movie", kind: "movie",
                               kinopubItemID: 456, season: 0, episode: 1)
    let beginning = PlaybackRecoveryPoint(context: movie, origin: point.origin, seconds: 0)
    #expect(beginning.isValid)
    #expect(beginning.pageURL.absoluteString == "https://example.com/item/view/456")
    #expect(!PlaybackRecoveryPoint(context: context, origin: point.origin, seconds: .nan).isValid)
    #expect(!PlaybackRecoveryPoint(context: context, origin: URL(string: "https://example.com/?token=synthetic")!, seconds: 0).isValid)
    #expect(!PlaybackRecoveryPoint(context: context, origin: URL(string: "https://user:password@example.com")!, seconds: 0).isValid)
}

@Test func onlyMediaFailuresOfferStreamRefresh() {
    for error: PlaybackError in [.timedOut, .commandRejected, .mediaFailed] {
        #expect(PlaybackRecoveryPoint.canRetry(error))
    }
    for error: PlaybackError in [.disconnected, .notRunning, .playerNotFound, .svpUnavailable,
                                 .svpRegistrationFailed, .invalidMediaURL, .invalidSeek] {
        #expect(!PlaybackRecoveryPoint.canRetry(error))
    }
}
