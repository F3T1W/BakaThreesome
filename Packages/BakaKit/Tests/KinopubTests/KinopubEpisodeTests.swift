import Foundation
import Kinopub
import Testing

@Test func episodeAddressesUseExplicitItemSeasonAndEpisodeWithoutPersistingTokens() throws {
    let url = try #require(URL(string: "https://mirror.example/item/view/10/s2e12?token=synthetic"))
    let episode = try #require(KinopubEpisode(url: url))
    #expect(episode.itemID == 10 && episode.season == 2 && episode.episode == 12)
    #expect(episode.url(on: URL(string: "https://new-mirror.example")!).absoluteString == "https://new-mirror.example/item/view/10/s2e12")
    for path in ["/item/view/10", "/item/view/10/s2", "/item/view/10/s0e1", "/item/view/10/s2e0", "/item/view/10/s2e12/extra"] {
        #expect(KinopubEpisode(url: URL(string: "https://mirror.example" + path)!) == nil)
    }
    #expect(KinopubEpisode(url: URL(string: "https://user:secret@mirror.example/item/view/10/s1e1")!) == nil)
}
