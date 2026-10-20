import Catalog
import Foundation
import ShikimoriBridge
import Testing
import Tracking

@Test func decodesTheSharedDotNetWireContract() throws {
    let url = try #require(Bundle.module.url(forResource: "bridge-v1", withExtension: "json", subdirectory: "Fixtures"))
    let fixture = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    func decode<Value: Decodable>(_ name: String, as type: Value.Type) throws -> Value {
        let value = try #require(fixture[name])
        return try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: value))
    }
    let posters = try decode("posters", as: [AnimePoster].self)
    #expect(posters.map(\.animeID) == [1, 2, 3])
    #expect(posters[0].safeImageURL?.lastPathComponent == "main.webp")
    #expect(posters[1].imageURL == nil && posters[2].imageURL == nil)
    let catalog = try decode("catalog", as: [AnimeSummary].self)
    #expect(catalog.first?.communityScore == 8.25)
    let details = try decode("details", as: AnimeDetails.self)
    #expect(details.anime.id == 1 && details.rate?.animeID == 1)
    #expect(details.identity?.titles == ["Example", "Alternative Title"])
    let list = try decode("list", as: [AnimeListEntry].self)
    #expect(list.first?.rate.id == 7_000_000_000 && list.first?.rate.status == .onHold)
    #expect(try decode("rate", as: AnimeUserRate.self).episodes == 3)
    #expect(try decode("profile", as: ShikimoriProfile.self).nickname == "Example")
    #expect(try decode("tokens", as: ShikimoriTokens.self).accessToken == "synthetic-access")
    #expect(try decode("handshake", as: HandshakeResult.self).capabilities == ["handshake"])
    #expect(try decode("error", as: BridgeError.self).code == "unauthorized")
}
