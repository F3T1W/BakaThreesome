@testable import BakaUI
import Foundation
import ImageIO
import Testing

@Test func posterDownloadsOverlapButRespectTheLimitAndDeduplicateURLs() async throws {
    let transport = try StubPosterImageTransport()
    let pipeline = PosterImagePipeline(transport: transport, limit: 2)
    try await withThrowingTaskGroup(of: Void.self) { group in
        for index in Array(0..<8) + [0, 1] {
            group.addTask {
                let image = try await pipeline.image(at: posterURL(index))
                #expect(image.width == 2 && image.height == 2)
            }
        }
        try await group.waitForAll()
    }
    #expect(await transport.maximumActive == 2)
    #expect(await transport.totalCalls == 8)
    _ = try await pipeline.image(at: posterURL(0))
    #expect(await transport.totalCalls == 8)
    await pipeline.shutdown()
}

@Test func timeoutsAndTemporaryHTTPFailuresRetryWithoutCachingTheFailure() async throws {
    let transport = try StubPosterImageTransport()
    await transport.setSteps([.timeout, .http(503, "0"), .image], for: posterURL(1))
    let waits = RetryWaits()
    let pipeline = PosterImagePipeline(transport: transport, sleep: { await waits.record($0) })
    _ = try await pipeline.image(at: posterURL(1))
    #expect(await transport.count(for: posterURL(1)) == 3)
    #expect(await waits.values.count == 2)
    _ = try await pipeline.image(at: posterURL(1))
    #expect(await transport.count(for: posterURL(1)) == 3)
    await pipeline.shutdown()
}

@Test func rateLimitsRespectRetryAfterAndPermanentErrorsDoNotRetry() async throws {
    let transport = try StubPosterImageTransport()
    await transport.setSteps([.http(429, "2"), .image], for: posterURL(1))
    await transport.setSteps([.http(404, nil)], for: posterURL(2))
    await transport.setSteps([.invalidImage], for: posterURL(3))
    let waits = RetryWaits()
    let pipeline = PosterImagePipeline(transport: transport, sleep: { await waits.record($0) })
    _ = try await pipeline.image(at: posterURL(1))
    #expect(await waits.values == [.seconds(2)])
    await #expect(throws: (any Error).self) { try await pipeline.image(at: posterURL(2)) }
    await #expect(throws: (any Error).self) { try await pipeline.image(at: posterURL(3)) }
    #expect(await transport.count(for: posterURL(2)) == 1)
    #expect(await transport.count(for: posterURL(3)) == 1)
    #expect(await transport.invalidations(for: posterURL(2)) == 1)
    #expect(await transport.invalidations(for: posterURL(3)) == 1)
    await transport.setSteps([.image], for: posterURL(2))
    _ = try await pipeline.image(at: posterURL(2))
    #expect(await transport.count(for: posterURL(2)) == 2)
    await pipeline.shutdown()
}

@Test func validImageBytesWorkWhenTheCDNUsesAGenericContentType() async throws {
    let transport = try StubPosterImageTransport()
    await transport.setSteps([.binaryImage], for: posterURL(1))
    let pipeline = PosterImagePipeline(transport: transport)
    let image = try await pipeline.image(at: posterURL(1))
    #expect(image.width == 2)
    #expect(await transport.count(for: posterURL(1)) == 1)
    await pipeline.shutdown()
}

@Test func cancellingTheLastConsumerFreesItsNetworkSlot() async throws {
    let transport = try StubPosterImageTransport()
    await transport.setSteps([.slow], for: posterURL(1))
    let pipeline = PosterImagePipeline(transport: transport, limit: 1)
    let first = Task { try await pipeline.image(at: posterURL(1)) }
    try await transport.waitForCall(posterURL(1))
    let queued = Task { try await pipeline.image(at: posterURL(2)) }
    queued.cancel()
    first.cancel()
    await #expect(throws: CancellationError.self) { try await first.value }
    await #expect(throws: CancellationError.self) { try await queued.value }
    _ = try await pipeline.image(at: posterURL(3))
    #expect(await transport.count(for: posterURL(2)) == 0)
    #expect(await transport.maximumActive == 1)
    await pipeline.shutdown()
}

private func posterURL(_ number: Int) -> URL { URL(string: "https://example.com/poster-\(number).png")! }

private actor RetryWaits {
    private(set) var values: [Duration] = []
    func record(_ value: Duration) { values.append(value) }
}

actor StubPosterImageTransport: PosterImageTransport {
    enum Step: Sendable {
        case image, binaryImage, timeout, http(Int, String?), invalidImage, slow
    }
    private let data: Data
    private var steps: [URL: [Step]] = [:]
    private var counts: [URL: Int] = [:]
    private var invalidated: [URL: Int] = [:]
    private var active = 0
    private(set) var maximumActive = 0
    var totalCalls: Int { counts.values.reduce(0, +) }

    init() throws {
        let context = try #require(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                                            space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        data = output as Data
    }

    func setSteps(_ values: [Step], for url: URL) { steps[url] = values }
    func count(for url: URL) -> Int { counts[url, default: 0] }
    func invalidate(_ url: URL) { invalidated[url, default: 0] += 1 }
    func invalidations(for url: URL) -> Int { invalidated[url, default: 0] }
    func waitForCall(_ url: URL) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while counts[url, default: 0] == 0 {
            guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    func fetch(_ url: URL) async throws -> PosterImageResponse {
        counts[url, default: 0] += 1
        active += 1; maximumActive = max(maximumActive, active)
        defer { active -= 1 }
        var remaining = steps[url, default: [.image]]
        let step = remaining.isEmpty ? Step.image : remaining.removeFirst()
        steps[url] = remaining
        try await Task.sleep(for: .milliseconds(30))
        switch step {
        case .image: return PosterImageResponse(data: data, status: 200, mimeType: "image/png", retryAfter: nil)
        case .binaryImage: return PosterImageResponse(data: data, status: 200, mimeType: "application/octet-stream", retryAfter: nil)
        case .timeout: throw URLError(.timedOut)
        case .http(let status, let header): return PosterImageResponse(data: Data(), status: status, mimeType: nil, retryAfter: header)
        case .invalidImage: return PosterImageResponse(data: Data("broken".utf8), status: 200, mimeType: "image/png", retryAfter: nil)
        case .slow:
            try await Task.sleep(for: .seconds(30))
            return PosterImageResponse(data: data, status: 200, mimeType: "image/png", retryAfter: nil)
        }
    }
}
