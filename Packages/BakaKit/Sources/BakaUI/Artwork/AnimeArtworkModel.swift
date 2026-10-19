import AppKit
import Catalog
import Foundation
import Observation
import ShikimoriBridge

enum AnimePosterState: Equatable {
    case loading, available(URL), missing, failed
}

@MainActor
@Observable
final class AnimeArtworkModel {
    private struct CachedPoster {
        let url: URL?
        let expires: Date
    }
    private(set) var revision = 0
    @ObservationIgnored private let client: ShikimoriClient
    @ObservationIgnored private var posters: [Int64: CachedPoster] = [:]
    @ObservationIgnored private var requests: [Int64: Task<Void, Never>] = [:]
    @ObservationIgnored private var batches: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private let pipeline: PosterImagePipeline
    @ObservationIgnored private var metadataFailures: Set<Int64> = []
    @ObservationIgnored private var imageFailures: Set<URL> = []
    @ObservationIgnored private var retries: [Int64: Int] = [:]

    init(client: ShikimoriClient, pipeline: PosterImagePipeline = PosterImagePipeline()) {
        self.client = client; self.pipeline = pipeline
    }

    func errorMessage(for animeIDs: [Int64]) -> String? {
        _ = revision
        let failed = animeIDs.contains { id in
            metadataFailures.contains(id) || posters[id]?.url.map { imageFailures.contains($0) } == true
        }
        return failed ? "Some posters could not be loaded. Retry the failed images; titles and playback are still available." : nil
    }

    func state(for animeID: Int64) -> AnimePosterState {
        _ = revision
        if let poster = posters[animeID] {
            return poster.url.map(AnimePosterState.available) ?? .missing
        }
        return metadataFailures.contains(animeID) ? .failed : .loading
    }

    func retryToken(for animeID: Int64) -> Int {
        _ = revision
        return retries[animeID, default: 0]
    }

    func url(for animeID: Int64) -> URL? {
        _ = revision
        return posters[animeID]?.url
    }

    func load(_ animeIDs: [Int64], force: Bool = false) async {
        let ids = Set(animeIDs.filter { $0 > 0 }).sorted()
        if force {
            for id in ids {
                retries[id, default: 0] += 1
                if let url = posters[id]?.url { imageFailures.remove(url) }
            }
            revision += 1
        }
        let missing = ids.filter { id in
            requests[id] == nil && (force || posters[id] == nil || posters[id]!.expires < .now)
        }
        for start in stride(from: 0, to: missing.count, by: 50) {
            let batch = Array(missing[start..<min(start + 50, missing.count)])
            let key = UUID()
            metadataFailures.subtract(batch)
            let task = Task {
                defer {
                    for id in batch { requests[id] = nil }
                    batches[key] = nil
                    revision += 1
                }
                do {
                    let values = try await loadMetadata(batch)
                    try Task.checkCancellation()
                    for value in values {
                        posters[value.animeID] = CachedPoster(url: value.safeImageURL,
                                                             expires: .now.addingTimeInterval(value.safeImageURL == nil ? 300 : 3600))
                    }
                    metadataFailures.subtract(batch)
                    revision += 1
                } catch {
                    if !Task.isCancelled { metadataFailures.formUnion(batch) }
                }
            }
            batches[key] = task
            for id in batch { requests[id] = task }
        }
        if !missing.isEmpty { revision += 1 }
        // Shared loads finish even if a single grid disappears; other windows may need them.
        for task in ids.compactMap({ requests[$0] }) { await task.value }
    }

    func image(at url: URL) async throws -> NSImage {
        do {
            let image = try await pipeline.image(at: url)
            try Task.checkCancellation()
            if imageFailures.remove(url) != nil { revision += 1 }
            return NSImage(cgImage: image, size: .zero)
        } catch {
            if !Task.isCancelled, !(error is CancellationError) {
                imageFailures.insert(url); revision += 1
            }
            throw error
        }
    }

    func shutdown() async {
        let tasks = Array(batches.values)
        for task in tasks { task.cancel() }
        await pipeline.shutdown()
        for task in tasks { await task.value }
    }

    private func loadMetadata(_ ids: [Int64]) async throws -> [AnimePoster] {
        for attempt in 0..<3 {
            do { return try await client.posters(ids) }
            catch {
                try Task.checkCancellation()
                let retryable: Bool
                if let error = error as? ShikimoriError {
                    retryable = error == .timeout || error == .serviceUnavailable
                } else if let error = error as? URLError {
                    retryable = [.timedOut, .networkConnectionLost, .notConnectedToInternet].contains(error.code)
                } else { retryable = false }
                guard retryable, attempt < 2 else { throw error }
                try await Task.sleep(for: .milliseconds(attempt == 0 ? 400 : 1200))
            }
        }
        throw URLError(.cannotLoadFromNetwork)
    }
}
