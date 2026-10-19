import AppKit
import Catalog
import Foundation
import ImageIO
import Observation
import ShikimoriBridge

@MainActor
@Observable
final class AnimeArtworkModel {
    private struct CachedPoster {
        let url: URL?
        let expires: Date
    }
    private(set) var revision = 0
    private(set) var errorMessage: String?
    @ObservationIgnored private let client: ShikimoriClient
    @ObservationIgnored private var posters: [Int64: CachedPoster] = [:]
    @ObservationIgnored private var requests: [Int64: Task<Void, Never>] = [:]
    @ObservationIgnored private var batches: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private let images = NSCache<NSURL, NSImage>()
    @ObservationIgnored private var downloads: [URL: Task<NSImage, Error>] = [:]
    @ObservationIgnored private let session: URLSession

    init(client: ShikimoriClient) {
        self.client = client
        images.totalCostLimit = 64 * 1024 * 1024
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 32 * 1024 * 1024, diskCapacity: 128 * 1024 * 1024,
                                           directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                                            .appendingPathComponent("BakaThreesome/Artwork"))
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 25
        session = URLSession(configuration: configuration)
    }

    func url(for animeID: Int64) -> URL? {
        _ = revision
        return posters[animeID]?.url
    }

    func load(_ animeIDs: [Int64], force: Bool = false) async {
        let ids = Set(animeIDs.filter { $0 > 0 }).sorted()
        let missing = ids.filter { id in
            requests[id] == nil && (force || posters[id] == nil || posters[id]!.expires < .now)
        }
        for start in stride(from: 0, to: missing.count, by: 50) {
            let batch = Array(missing[start..<min(start + 50, missing.count)])
            let key = UUID()
            let task = Task {
                defer {
                    for id in batch { requests[id] = nil }
                    batches[key] = nil
                }
                do {
                    let values = try await client.posters(batch)
                    try Task.checkCancellation()
                    for value in values {
                        posters[value.animeID] = CachedPoster(url: value.safeImageURL,
                                                             expires: .now.addingTimeInterval(value.safeImageURL == nil ? 300 : 3600))
                    }
                    errorMessage = nil
                    revision += 1
                } catch {
                    if !Task.isCancelled { errorMessage = "Some posters could not be loaded. Titles and playback are still available." }
                }
            }
            batches[key] = task
            for id in batch { requests[id] = task }
        }
        // Shared loads finish even if a single grid disappears; other windows may need them.
        for task in ids.compactMap({ requests[$0] }) { await task.value }
    }

    func image(at url: URL) async throws -> NSImage {
        if let image = images.object(forKey: url as NSURL) { return image }
        if let download = downloads[url] { return try await download.value }
        let task = Task {
            var request = URLRequest(url: url)
            request.setValue("BakaThreesome", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode),
                  response.mimeType?.hasPrefix("image/") == true, data.count <= 12 * 1024 * 1024,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 640
                  ] as CFDictionary) else {
                throw URLError(.cannotDecodeContentData)
            }
            try Task.checkCancellation()
            let image = NSImage(cgImage: thumbnail, size: .zero)
            images.setObject(image, forKey: url as NSURL, cost: thumbnail.bytesPerRow * thumbnail.height)
            return image
        }
        downloads[url] = task
        defer { downloads[url] = nil }
        return try await task.value
    }

    func shutdown() async {
        for task in batches.values { task.cancel() }
        for task in downloads.values { task.cancel() }
        session.invalidateAndCancel()
        for task in Array(batches.values) { await task.value }
        for task in Array(downloads.values) { _ = try? await task.value }
    }
}
