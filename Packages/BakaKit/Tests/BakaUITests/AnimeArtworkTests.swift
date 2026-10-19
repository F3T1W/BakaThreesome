@testable import BakaUI
import Foundation
import ShikimoriBridge
import Testing

@MainActor
@Test func posterMetadataIsSharedAcrossGridsAndMissingArtworkIsCached() async throws {
    let transport = PosterTransport()
    let model = AnimeArtworkModel(client: ShikimoriClient(transport: transport))
    async let first: Void = model.load([1, 2, 1])
    async let second: Void = model.load([2, 1])
    _ = await (first, second)
    #expect(await transport.batches == [[1, 2]])
    #expect(model.url(for: 1)?.absoluteString == "https://example.com/poster.webp")
    #expect(model.url(for: 2) == nil)
    #expect(model.state(for: 2) == .missing)
    await model.load([1, 2])
    #expect(await transport.batches.count == 1)
    await model.load([1, 2], force: true)
    #expect(await transport.batches.count == 2)
    await model.shutdown()
}

@MainActor
@Test func metadataUsesBatchesOfAtMostFiftyAndFailedRequestsCanBeRetried() async throws {
    let transport = PosterTransport()
    let model = AnimeArtworkModel(client: ShikimoriClient(transport: transport))
    await model.load(Array(1...101))
    #expect(await transport.batches.map(\.count).sorted() == [1, 50, 50])
    await transport.fail()
    await model.load([200])
    #expect(model.errorMessage(for: [200]) != nil)
    #expect(model.state(for: 200) == .failed)
    await transport.recover()
    await model.load([200])
    #expect(model.errorMessage(for: [200]) == nil)
    #expect(model.url(for: 200) != nil)
    await model.shutdown()
}

private actor PosterTransport: BridgeTransport {
    private(set) var batches: [[Int64]] = []
    private var failing = false
    func fail() { failing = true }
    func recover() { failing = false }
    func exchange(_ data: Data, cancelSafe: Bool) async throws -> Data {
        let request = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let id = try #require(request["id"] as? String)
        #expect(request["method"] as? String == "catalog.posters")
        #expect(cancelSafe)
        let parameters = try #require(request["parameters"] as? [String: Any])
        let ids = try #require(parameters["animeIDs"] as? [Int64])
        batches.append(ids)
        try await Task.sleep(for: .milliseconds(10))
        if failing { throw URLError(.notConnectedToInternet) }
        let values: [[String: Any]] = ids.map { id in
            ["animeID": id, "imageURL": id == 2 ? NSNull() : "https://example.com/poster.webp"]
        }
        return try JSONSerialization.data(withJSONObject: ["version": 1, "id": id, "result": values])
    }
    func shutdown() async {}
}

@MainActor
@Test func failedImageIsNotMissingArtworkAndReloadRetriesTheSameURL() async throws {
    let transport = try StubPosterImageTransport()
    let url = URL(string: "https://example.com/poster.webp")!
    await transport.setSteps([.timeout, .timeout, .timeout], for: url)
    let pipeline = PosterImagePipeline(transport: transport, sleep: { _ in })
    let model = AnimeArtworkModel(client: ShikimoriClient(transport: PosterTransport()), pipeline: pipeline)
    await model.load([1])
    let firstToken = model.retryToken(for: 1)
    await #expect(throws: (any Error).self) { try await model.image(at: url) }
    #expect(model.state(for: 1) == .available(url))
    #expect(model.errorMessage(for: [1]) != nil)
    #expect(model.errorMessage(for: [2]) == nil)
    await model.load([1], force: true)
    #expect(model.retryToken(for: 1) > firstToken)
    _ = try await model.image(at: url)
    #expect(model.errorMessage(for: [1]) == nil)
    #expect(await transport.count(for: url) == 4)
    await model.shutdown()
}
