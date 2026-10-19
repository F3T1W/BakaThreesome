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

    func run(url: URL, webView: WKWebView, origin: URL, userAgent: String?) async -> String {
        var report: [String] = []
        do {
            let browser = try await browserSample(url: url, webView: webView)
            report.append("Browser master: \(browser.summary)")
            do {
                let native = try await nativeSample(url: url, origin: origin, userAgent: userAgent)
                report.append("Native master: \(native.summary)")
            } catch { report.append("Native master: \(failure(error))") }
            guard browser.isPlaylist else { return report.joined(separator: "\n") }
            let lines = browser.body.split(whereSeparator: \.isNewline)
            report.append("Master: \(lines.filter { $0.hasPrefix("#EXT-X-STREAM-INF:") }.count) variants, \(lines.filter { $0.contains("TYPE=AUDIO") }.count) audio tracks, \(lines.filter { $0.contains("TYPE=SUBTITLES") }.count) subtitle tracks")
            let children = playlistChildren(browser.body, base: browser.url)
            for (index, child) in children.prefix(2).enumerated() {
                try Task.checkCancellation()
                let label = "Track \(index + 1)"
                do {
                    let native = try await nativeSample(url: child, origin: origin, userAgent: userAgent)
                    report.append("Native \(label): \(native.summary)")
                } catch { report.append("Native \(label): \(failure(error))") }
                do {
                    let track = try await browserSample(url: child, webView: webView)
                    report.append("Browser \(label): \(track.summary)")
                    if track.isPlaylist, let segment = playlistChildren(track.body, base: track.url).first {
                        do {
                            let sample = try await nativeSample(url: segment, origin: origin, userAgent: userAgent, segment: true)
                            report.append("Native \(label) segment: \(sample.summary)")
                        } catch { report.append("Native \(label) segment: \(failure(error))") }
                    }
                } catch { report.append("Browser \(label): \(failure(error))") }
            }
            if !Task.isCancelled {
                report.append(await playerSample(url: url, origin: origin, userAgent: userAgent))
            }

        } catch { report.append("Browser master: \(failure(error))") }
        return report.joined(separator: "\n")
    }

    private func playerSample(url: URL, origin: URL, userAgent: String?) async -> String {
        guard let executable = PlaybackEnvironment.discover().mpvURL else { return "mpv: not found" }
        let engine = MPVPlaybackEngine(executable: executable, headless: true, networkDiagnostics: true)
        var result = "mpv: failed"
        do {
            try await engine.start()
            try await engine.setPaused(true)
            let source = try PlaybackSource(url: url, referrer: origin, userAgent: userAgent, origin: origin)
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
            result = "mpv: loaded, video=\(state.videoCodec != nil), audio=\(state.audioCodec != nil), \(String(format: "%.2f", elapsed(start))) s"
        } catch is CancellationError { result = Task.isCancelled ? "mpv: cancelled" : "mpv: media-open deadline reached" }
        catch { result = "mpv: media open failed" }
        let notes = await engine.networkDiagnostics()
        await engine.stop()
        return (["mpv application defaults:", result] + notes).joined(separator: "\n")
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
                  !values.contains(url) else { continue }
            if line.hasPrefix("#EXT-X-MEDIA:") { audio.append(url) }
            else { values.append(url) }
        }
        return Array(values.prefix(1)) + Array(audio.prefix(1)) + Array(values.dropFirst())
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
