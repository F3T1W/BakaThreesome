import Foundation
import ImageIO

struct PosterImageResponse: Sendable {
    let data: Data
    let status: Int
    let mimeType: String?
    let retryAfter: String?
}

protocol PosterImageTransport: Sendable {
    func fetch(_ url: URL) async throws -> PosterImageResponse
    func invalidate(_ url: URL) async
    func shutdown() async
}

extension PosterImageTransport {
    func invalidate(_ url: URL) async {}
    func shutdown() async {}
}

struct URLSessionPosterTransport: PosterImageTransport {
    let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 32 * 1024 * 1024, diskCapacity: 128 * 1024 * 1024,
                                           directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                                            .appendingPathComponent("BakaThreesome/Artwork"))
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 20
        session = URLSession(configuration: configuration)
    }

    func shutdown() async { session.invalidateAndCancel() }

    func invalidate(_ url: URL) async {
        session.configuration.urlCache?.removeCachedResponse(for: request(for: url))
    }

    private func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("BakaThreesome", forHTTPHeaderField: "User-Agent")
        return request
    }

    func fetch(_ url: URL) async throws -> PosterImageResponse {
        let (data, response) = try await session.data(for: request(for: url))
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return PosterImageResponse(data: data, status: response.statusCode, mimeType: response.mimeType,
                                   retryAfter: response.value(forHTTPHeaderField: "Retry-After"))
    }
}

/// Downloads are shared by URL. Queued work does not consume a URLSession timeout;
/// the last disappearing consumer cancels its download or removes its queue entry.
actor PosterImagePipeline {
    private struct Download {
        let task: Task<CGImage, Error>
        var consumers: Set<UUID>
    }
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }
    private let transport: any PosterImageTransport
    private let limit: Int
    private let sleep: @Sendable (Duration) async throws -> Void
    private let images = NSCache<NSURL, CGImage>()
    private var downloads: [URL: Download] = [:]
    private var active = 0
    private var waiters: [Waiter] = []
    private var closing = false

    init(transport: any PosterImageTransport = URLSessionPosterTransport(), limit: Int = 6,
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.transport = transport; self.limit = max(1, limit); self.sleep = sleep
        images.totalCostLimit = 64 * 1024 * 1024
    }

    func image(at url: URL) async throws -> CGImage {
        try Task.checkCancellation()
        guard !closing else { throw CancellationError() }
        if let image = images.object(forKey: url as NSURL) { return image }
        let consumer = UUID()
        let task: Task<CGImage, Error>
        if var download = downloads[url] {
            download.consumers.insert(consumer)
            downloads[url] = download
            task = download.task
        } else {
            task = Task { try await download(url) }
            downloads[url] = Download(task: task, consumers: [consumer])
        }
        defer { release(url, consumer: consumer) }
        return try await withTaskCancellationHandler {
            let value = try await task.value
            try Task.checkCancellation()
            return value
        } onCancel: {
            Task { await self.release(url, consumer: consumer) }
        }
    }

    func shutdown() async {
        closing = true
        let tasks = downloads.values.map(\.task)
        for task in tasks { task.cancel() }
        let queued = waiters
        waiters.removeAll()
        for waiter in queued { waiter.continuation.resume(throwing: CancellationError()) }
        await transport.shutdown()
        for task in tasks { _ = try? await task.value }
    }

    private func release(_ url: URL, consumer: UUID) {
        guard var download = downloads[url], download.consumers.remove(consumer) != nil else { return }
        if download.consumers.isEmpty {
            downloads[url] = nil
            download.task.cancel()
        } else { downloads[url] = download }
    }

    private func download(_ url: URL) async throws -> CGImage {
        for attempt in 0..<3 {
            try Task.checkCancellation()
            do {
                let image = try await attemptDownload(url)
                try Task.checkCancellation()
                images.setObject(image, forKey: url as NSURL, cost: image.bytesPerRow * image.height)
                return image
            } catch {
                try Task.checkCancellation()
                guard attempt < 2, let delay = retryDelay(error, attempt: attempt) else { throw error }
                // Release the network slot before backoff so one slow poster cannot monopolize it.
                try await sleep(delay)
            }
        }
        throw URLError(.cannotLoadFromNetwork)
    }

    private func attemptDownload(_ url: URL) async throws -> CGImage {
        try await acquire()
        defer { freeSlot() }
        try Task.checkCancellation()
        let response = try await transport.fetch(url)
        guard (200...299).contains(response.status) else {
            await transport.invalidate(url)
            throw PosterHTTPError(status: response.status, retryAfter: response.retryAfter)
        }
        guard !response.data.isEmpty, response.data.count <= 12 * 1024 * 1024 else {
            await transport.invalidate(url)
            throw URLError(.cannotDecodeContentData)
        }
        let data = response.data
        // ImageIO thumbnail decoding runs off the UI actor and does not retain a full-sized poster.
        let decoding = Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 640,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { throw URLError(.cannotDecodeContentData) }
            return image
        }
        do { return try await decoding.value }
        catch {
            await transport.invalidate(url)
            throw error
        }
    }

    private func acquire() async throws {
        try Task.checkCancellation()
        guard !closing else { throw CancellationError() }
        if active < limit { active += 1; return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters.append(Waiter(id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    private func freeSlot() {
        if !waiters.isEmpty { waiters.removeFirst().continuation.resume() }
        else { active -= 1 }
    }

    private func retryDelay(_ error: any Error, attempt: Int) -> Duration? {
        if let error = error as? PosterHTTPError {
            guard error.status == 408 || error.status == 429 || (500...599).contains(error.status) else { return nil }
            if let header = error.retryAfter {
                let seconds: Double?
                if let number = Double(header) { seconds = number }
                else {
                    let formatter = DateFormatter()
                    formatter.locale = Locale(identifier: "en_US_POSIX")
                    formatter.timeZone = TimeZone(secondsFromGMT: 0)
                    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                    seconds = formatter.date(from: header)?.timeIntervalSinceNow
                }
                if let seconds {
                    guard seconds.isFinite, seconds <= 60 else { return nil }
                    return .seconds(max(0, seconds))
                }
            }
        } else if let error = error as? URLError {
            guard [.timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost,
                   .cannotFindHost, .dnsLookupFailed, .resourceUnavailable].contains(error.code) else { return nil }
        } else { return nil }
        return .milliseconds((attempt == 0 ? 400 : 1200) + Int.random(in: 0...200))
    }
}

private struct PosterHTTPError: Error {
    let status: Int
    let retryAfter: String?
}
