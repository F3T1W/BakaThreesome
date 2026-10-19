import Catalog
import Foundation
import ShikimoriBridge
import Testing
import Tracking

@Test func uncertainProgressWriteIsReconciledBeforeRetryAndNeverIncrementedTwice() async throws {
    let transport = ProgressTransport()
    let client = ShikimoriClient(transport: transport)
    let context = EpisodeContext(animeID: AnimeID(rawValue: 1), title: "Example", kind: "tv",
                                 kinopubItemID: 10, season: 1, episode: 4)
    let episode = WatchedEpisode(userID: 42, context: context, number: 4)
    await #expect(throws: ShikimoriError.invalidResponse) {
        try await client.advanceProgress(episode, token: "synthetic-access")
    }
    #expect(try await client.advanceProgress(episode, token: "synthetic-access") == .alreadyApplied)
    #expect(await transport.writes == 1)
    #expect(await transport.writeProtected)
    #expect(await transport.sentKeys == Set(["animeID", "rateID", "episodes", "accessToken"]))
    let later = WatchedEpisode(userID: 42, context: context, number: 7)
    if case .waiting = try await client.advanceProgress(later, token: "synthetic-access") {} else {
        Issue.record("A gap in watched episodes was accepted")
    }
    #expect(await transport.writes == 1)
}

private actor ProgressTransport: BridgeTransport {
    private var episodes = 3
    private(set) var writes = 0
    private(set) var writeProtected = false
    private(set) var sentKeys: Set<String> = []
    func exchange(_ data: Data, cancelSafe: Bool) async throws -> Data {
        let request = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let id = try #require(request["id"] as? String)
        let method = try #require(request["method"] as? String)
        if method == "watchlist.progress" {
            let parameters = try #require(request["parameters"] as? [String: Any])
            sentKeys = Set(parameters.keys)
            writeProtected = !cancelSafe
            episodes = try #require(parameters["episodes"] as? Int)
            writes += 1
            // The server applied the absolute update, but its response was lost.
            return Data("invalid response".utf8)
        }
        #expect(method == "anime.details")
        return try JSONSerialization.data(withJSONObject: [
            "version": 1, "id": id, "result": [
                "anime": ["id": 1, "title": "Example", "episodes": 12, "kind": "tv"],
                "rate": ["id": 7_000_000_000, "animeID": 1, "status": "watching", "episodes": episodes, "score": 8]
            ]
        ])
    }
    func shutdown() async {}
}
