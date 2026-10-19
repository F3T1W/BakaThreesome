import Foundation
import Playback
import WebKit

/// Fetch only small samples; signed addresses and response bodies remain in memory.
@MainActor
struct StreamDiagnosticProbe {
    private struct Sample {
        let url: URL
        let status: Int
        let body: String
        let seconds: Double
        var isPlaylist: Bool { body.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#EXTM3U") }
        var summary: String { "HTTP \(status), \(isPlaylist ? "HLS" : "data"), \(String(format: "%.2f", seconds)) s" }
    }

    func run(url: URL, webView: WKWebView, origin: URL, userAgent: String?,
             startSeconds: Double = 0, preferences: PlaybackTrackPreferences = .originalWithRussianSubtitles,
             onProgress: @MainActor (String) -> Void = { _ in }) async -> String {
        var report: [String] = []
        var browser: Sample?
        var native: Sample?
        do {
            browser = try await browserSample(url: url, webView: webView)
            if let browser { report.append("Browser master: \(browser.summary)") }
        } catch { report.append("Browser master: \(failure(error))") }
        onProgress(report.joined(separator: "\n"))
        if Task.isCancelled { return report.joined(separator: "\n") }
        do {
            native = try await nativeSample(url: url, origin: origin, userAgent: userAgent)
            if let native { report.append("Native master: \(native.summary)") }
        } catch { report.append("Native master: \(failure(error))") }
        if let master = [native, browser].compactMap({ $0 }).first(where: \.isPlaylist) {
            let lines = master.body.split(whereSeparator: \.isNewline)
            report.append("Master: \(lines.filter { $0.hasPrefix("#EXT-X-STREAM-INF:") }.count) variants, \(lines.filter { $0.contains("TYPE=AUDIO") }.count) audio tracks, \(lines.filter { $0.contains("TYPE=SUBTITLES") }.count) subtitle tracks")
            let tags = Set(lines.filter { $0.hasPrefix("#EXT") }.map { String($0.prefix(while: { $0 != ":" })) }
                .filter { $0.range(of: "^#EXT[A-Z0-9-]{1,36}$", options: .regularExpression) != nil }).sorted()
            report.insert("Master tags: " + tags.joined(separator: ", "), at: 0)
            let children = Array(playlistChildren(master.body, base: master.url).prefix(24))
            for offset in stride(from: 0, to: children.count, by: 4) {
                if Task.isCancelled { break }
                let batch = Array(children.enumerated().dropFirst(offset).prefix(4))
                let results = await withTaskGroup(of: (Int, String).self) { group in
                    for (index, child) in batch {
                        group.addTask {
                            let report = await self.renditionSample(url: child, label: "Rendition \(index + 1)",
                                                                   origin: origin, userAgent: userAgent, seconds: startSeconds)
                            return (index, report)
                        }
                    }
                    var values: [(Int, String)] = []
                    for await result in group { values.append(result) }
                    return values.sorted { $0.0 < $1.0 }.map(\.1)
                }
                report.append(contentsOf: results)
                onProgress(report.joined(separator: "\n"))
            }
        }
        if !Task.isCancelled {
            for mode in [HLSStartupMode.selectedProgram] {
                if Task.isCancelled { break }
                onProgress((["Checking mpv startup=\(mode.rawValue)…"] + report).joined(separator: "\n"))
                report.insert(await playerSample(url: url, origin: origin, userAgent: userAgent,
                                                 startSeconds: startSeconds, preferences: preferences, mode: mode), at: 0)
                onProgress(report.joined(separator: "\n"))
            }
        }
        return report.joined(separator: "\n")
    }

    private func renditionSample(url: URL, label: String, origin: URL, userAgent: String?, seconds: Double) async -> String {
        do {
            let sample = try await nativeSample(url: url, origin: origin, userAgent: userAgent)
            var report = ["Native \(label): \(sample.summary)"]
            if sample.isPlaylist, let segment = Self.segment(at: seconds, in: sample.body, base: sample.url), !Task.isCancelled {
                do {
                    let result = try await nativeSample(url: segment, origin: origin, userAgent: userAgent, segment: true)
                    report.append("Native \(label) resume segment: \(result.summary)")
                } catch { report.append("Native \(label) resume segment: \(failure(error))") }
            }
            return report.joined(separator: "\n")
        } catch { return "Native \(label): \(failure(error))" }
    }

    static func segment(at seconds: Double, in body: String, base: URL) -> URL? {
        guard seconds.isFinite, seconds >= 0 else { return nil }
        var elapsed = 0.0
        var duration: Double?
        for raw in body.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#EXTINF:") {
                duration = Double(line.dropFirst(8).split(separator: ",").first ?? "")
            } else if !line.hasPrefix("#"), !line.isEmpty, let length = duration, length.isFinite, length > 0 {
                if seconds < elapsed + length {
                    guard let url = URL(string: line, relativeTo: base)?.absoluteURL,
                          url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else { return nil }
                    return url
                }
                elapsed += length
                duration = nil
            }
        }
        return nil
    }

    private func playerSample(url: URL, origin: URL, userAgent: String?, startSeconds: Double,
                              preferences: PlaybackTrackPreferences, mode: HLSStartupMode) async -> String {
        guard let executable = PlaybackEnvironment.discover().mpvURL else { return "mpv: not found" }
        let engine = MPVPlaybackEngine(executable: executable, headless: true, networkDiagnostics: true)
        var result = "mpv: failed"
        do {
            try await engine.start()
            try await engine.setPaused(true)
            let source = try PlaybackSource(url: url, referrer: origin, userAgent: userAgent, origin: origin,
                                            startSeconds: startSeconds, trackPreferences: preferences, hlsStartupMode: mode)
            let start = ContinuousClock.now
            let loading = Task { try await engine.load(source) }
            let deadline = Task {
                do { try await Task.sleep(for: .seconds(35)) } catch { return }
                loading.cancel()
            }
            defer { deadline.cancel() }
            try await withTaskCancellationHandler {
                try await loading.value
            } onCancel: { loading.cancel() }
            let state = try await engine.snapshot()
            let tracks = try await engine.tracks()
            let audio = tracks.first { $0.kind == .audio && $0.isSelected }
            let subtitle = tracks.first { $0.kind == .subtitle && $0.isSelected }
            result = "mpv: loaded, video=\(state.videoCodec != nil), audio=\(state.audioCodec != nil), \(String(format: "%.2f", elapsed(start))) s"
            result += "\nSelected audio=\(language(audio)), subtitles=\(language(subtitle)); position=\(String(format: "%.2f", state.position.seconds)) s"
        } catch is CancellationError { result = Task.isCancelled ? "mpv: cancelled" : "mpv: media-open deadline reached" }
        catch { result = "mpv: media open failed" }
        let notes = await engine.networkDiagnostics()
        await engine.stop()
        return (["mpv startup=\(mode.rawValue) · requested start \(String(format: "%.2f", startSeconds)) s:", result] + notes).joined(separator: "\n")
    }

    private func language(_ track: PlaybackTrack?) -> String {
        guard let value = track?.language,
              value.range(of: "^[a-zA-Z]{2,3}$", options: .regularExpression) != nil else { return "none/unknown" }
        return value.lowercased()
    }

    private func browserSample(url: URL, webView: WKWebView) async throws -> Sample {
        let start = ContinuousClock.now
        let script = """
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), 10000);
        try {
            const response = await fetch(address, { credentials: 'same-origin', cache: 'no-store', signal: controller.signal });
            const reader = response.body.getReader();
            let size = 0, chunks = [];
            while (size < 65536) {
                const {done, value} = await reader.read();
                if (done) break;
                const chunk = value.slice(0, 65536 - size);
                chunks.push(chunk); size += chunk.length;
            }
            await reader.cancel();
            const bytes = new Uint8Array(size); let offset = 0;
            for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
            return { status: response.status, address: response.url, body: new TextDecoder().decode(bytes) };
        } finally { clearTimeout(timer); }
        """
        guard let result = try await webView.callAsyncJavaScript(script, arguments: ["address": url.absoluteString],
                                                                 in: nil, contentWorld: .defaultClient) as? [String: Any],
              let status = result["status"] as? Int, let address = result["address"] as? String,
              let finalURL = URL(string: address), let body = result["body"] as? String else { throw URLError(.badServerResponse) }
        return Sample(url: finalURL, status: status, body: body, seconds: elapsed(start))
    }

    private func nativeSample(url: URL, origin: URL, userAgent: String?, segment: Bool = false) async throws -> Sample {
        guard url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else { throw URLError(.unsupportedURL) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 12
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.setValue(origin.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue(origin.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")), forHTTPHeaderField: "Origin")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if segment { request.setValue("bytes=0-4095", forHTTPHeaderField: "Range") }
        let start = ContinuousClock.now
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count >= (segment ? 4096 : 65536) { break }
        }
        return Sample(url: http.url ?? url, status: http.statusCode,
                      body: segment ? "" : String(decoding: data, as: UTF8.self), seconds: elapsed(start))
    }

    private func playlistChildren(_ body: String, base: URL) -> [URL] {
        var values: [URL] = []
        var audio: [URL] = []
        for raw in body.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let address: String
            if line.hasPrefix("#EXT-X-MEDIA:"), line.contains("TYPE=AUDIO"),
               let range = line.range(of: "URI=\"") {
                address = String(line[range.upperBound...].prefix(while: { $0 != "\"" }))
            } else if !line.hasPrefix("#"), !line.isEmpty { address = line }
            else { continue }
            guard let url = URL(string: address, relativeTo: base)?.absoluteURL,
                  url.scheme == "https", url.host != nil, url.user == nil, url.password == nil,
                  !values.contains(url), !audio.contains(url) else { continue }
            if line.hasPrefix("#EXT-X-MEDIA:") { audio.append(url) }
            else { values.append(url) }
        }
        return values + audio
    }

    private func elapsed(_ start: ContinuousClock.Instant) -> Double {
        let value = start.duration(to: .now).components
        return Double(value.seconds) + Double(value.attoseconds) / 1e18
    }

    private func failure(_ error: Error) -> String {
        if error is CancellationError { return "cancelled" }
        if let error = error as? URLError { return "network error \(error.code.rawValue)" }
        return "request failed"
    }
}
