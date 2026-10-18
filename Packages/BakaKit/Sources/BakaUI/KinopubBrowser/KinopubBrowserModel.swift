import AppKit
import Foundation
import Kinopub
import Observation
import Playback
import WebKit

@MainActor
@Observable
final class KinopubBrowserModel: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate {
    var useSVP = UserDefaults.standard.object(forKey: "playback.useSVP") as? Bool ?? true {
        didSet { UserDefaults.standard.set(useSVP, forKey: "playback.useSVP") }
    }
    private(set) var websiteOrigin = URL(string: "https://gxux.pkr.ovh")!
    private(set) var svpStatus = "SVP: Off"
    var audioSourceID: UUID?
    var address = "https://gxux.pkr.ovh"
    private(set) var candidates: [BrowserMediaCandidate] = []
    private(set) var isWorking = false
    private(set) var status = "Sign in on the website, open an episode, and start its web player to discover media."
    private(set) var errorMessage: String?
    @ObservationIgnored private(set) var webView: WKWebView!
    @ObservationIgnored private var allowedHost = "gxux.pkr.ovh"
    @ObservationIgnored private var player: MPVPlaybackEngine?
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var monitor: Task<Void, Never>?
    @ObservationIgnored private var hasLoaded = false

    override init() {
        super.init()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = KinopubWebsiteSession.dataStore()
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        let controller = configuration.userContentController
        controller.add(WeakMediaHandler(self), contentWorld: .defaultClient, name: "bakaMedia")
        if let path = Bundle.module.url(forResource: "MediaDiscovery", withExtension: "js"),
           let script = try? String(contentsOf: path, encoding: .utf8) {
            controller.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd,
                                                  forMainFrameOnly: false, in: .defaultClient))
        }
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
    }

    func loadIfNeeded() {
        if !hasLoaded { navigate() }
    }

    func navigate() {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", let host = url.host, url.user == nil, url.password == nil else {
            errorMessage = "Enter an HTTPS website address without embedded credentials."
            return
        }
        var origin = URLComponents()
        origin.scheme = "https"; origin.host = host; origin.port = url.port
        guard let base = origin.url else { return }
        websiteOrigin = base
        allowedHost = host.lowercased()
        hasLoaded = true
        errorMessage = nil
        candidates = []
        audioSourceID = nil
        webView.load(URLRequest(url: url))
    }

    func openTitle(itemID: Int64, season: Int) {
        guard itemID > 0, (0...999).contains(season) else { return }
        let suffix = season > 0 ? "/s\(season)e1" : ""
        address = websiteOrigin.appendingPathComponent("item/view/\(itemID)" + suffix).absoluteString
        navigate()
    }

    func scan() {
        errorMessage = nil
        candidates = []
        audioSourceID = nil
        webView.evaluateJavaScript("window.__bakaScanMedia?.()", in: nil, in: .defaultClient) { _ in }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "bakaMedia", let value = message.body as? [String: String],
              let address = value["address"], let page = value["pageAddress"], let source = value["source"],
              let candidate = BrowserMediaCandidate(address: address, pageAddress: page, source: source),
              isAllowed(webView.url), candidates.count < 100 else { return }
        if let index = candidates.firstIndex(where: { $0.url == candidate.url }) {
            if candidate.source == "Video", candidates[index].source == "Resource" { candidates[index] = candidate }
            return
        }
        candidates.append(candidate)
        if player == nil && operation == nil {
            status = "Found \(candidates.count) media source(s). Select the source for the episode you opened."
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        let url = navigationAction.request.url
        if navigationAction.targetFrame?.isMainFrame == false {
            return url?.scheme == "https" || url?.absoluteString == "about:blank" ? .allow : .cancel
        }
        guard isAllowed(url) else {
            errorMessage = "Navigation to another site was blocked. Enter its trusted HTTPS address above if this is your Kinopub mirror."
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        candidates = []
        audioSourceID = nil
        errorMessage = nil
        status = "Loading website…"
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Keep query strings and signed addresses out of native UI state.
        if let url = webView.url, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            parts.query = nil; parts.fragment = nil
            address = parts.url?.absoluteString ?? address
        }
        status = candidates.isEmpty
            ? "Open an episode and start its web player. Media sources will appear below."
            : "Found \(candidates.count) media source(s)."
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { errorMessage = "The website could not be loaded. Check its address and your connection." }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        errorMessage = "The website stopped loading. Try reloading the page."
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if isAllowed(navigationAction.request.url) { webView.load(navigationAction.request) }
        return nil
    }

    func play(_ candidate: BrowserMediaCandidate) {
        guard operation == nil else { return }
        isWorking = true
        errorMessage = nil
        status = "Starting mpv…"
        let audioURL = candidates.first(where: { $0.id == audioSourceID })?.url
        operation = Task {
            defer { isWorking = false; operation = nil }
            do {
                monitor?.cancel()
                await monitor?.value
                let environment = PlaybackEnvironment.discover()
                guard let executable = environment.mpvURL else { throw PlaybackError.playerNotFound }
                let enableSVP = useSVP
                if enableSVP {
                    guard let svp = environment.svpURL,
                          try await MPVCapabilityProbe(executable: executable).inspect().hasVapourSynth else {
                        throw PlaybackError.svpUnavailable
                    }
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.activates = false
                    do {
                        _ = try await NSWorkspace.shared.openApplication(at: svp, configuration: configuration)
                    } catch {
                        throw PlaybackError.svpUnavailable
                    }
                }
                await player?.stop()
                svpStatus = enableSVP ? "SVP: Waiting for video…" : "SVP: Off"
                let engine = MPVPlaybackEngine(executable: executable, enableSVP: enableSVP)
                player = engine
                let userAgent = try await webView.evaluateJavaScript("navigator.userAgent") as? String
                let source = try PlaybackSource(url: candidate.url, referrer: candidate.referrerOrigin,
                                                userAgent: userAgent, audioURL: audioURL, origin: candidate.referrerOrigin)
                try await engine.start()
                try await engine.load(source)
                startMonitoring(engine)
                let deadline = ContinuousClock.now.advanced(by: .seconds(20))
                while ContinuousClock.now < deadline {
                    let snapshot = try await engine.snapshot()
                    if !snapshot.isIdle && (snapshot.position.duration != nil || snapshot.position.seconds > 0) {
                        if snapshot.videoCodec != nil && snapshot.audioCodec != nil {
                            status = "mpv is playing video and audio. Automatic Shikimori progress tracking is not connected yet."
                            return
                        }
                        if audioURL == nil, snapshot.videoCodec != nil || snapshot.audioCodec != nil {
                            status = snapshot.videoCodec != nil
                                ? "mpv is playing video only. Select its external audio source if the website uses separate tracks."
                                : "mpv is playing audio only. Choose the video source and use this source as external audio."
                            return
                        }
                    }
                    try await Task.sleep(for: .milliseconds(250))
                }
                throw PlaybackError.timedOut
            } catch {
                monitor?.cancel()
                await monitor?.value
                svpStatus = "SVP: Off"
                await player?.stop()
                player = nil
                status = "Playback did not start."
                if let error = error as? PlaybackError { errorMessage = error.errorDescription }
                else { errorMessage = "The browser could not prepare this media source. Reopen the episode and try again." }
            }
        }
    }

    func stop() {
        guard operation == nil else { return }
        isWorking = true
        operation = Task {
            monitor?.cancel()
            await monitor?.value
            svpStatus = "SVP: Off"
            await player?.stop()
            player = nil
            status = "Playback stopped."
            isWorking = false
            operation = nil
        }
    }

    func clearSession() {
        guard operation == nil else { return }
        isWorking = true
        operation = Task {
            webView.stopLoading()
            monitor?.cancel()
            await monitor?.value
            svpStatus = "SVP: Off"
            await player?.stop()
            player = nil
            candidates = []
            audioSourceID = nil
            await webView.configuration.websiteDataStore.removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
            status = "Browser session cleared. Sign in again on the website."
            errorMessage = nil
            isWorking = false
            operation = nil
            if let url = URL(string: "https://" + allowedHost) { webView.load(URLRequest(url: url)) }
        }
    }

    func shutdown() async {
        operation?.cancel()
        await operation?.value
        monitor?.cancel()
        await monitor?.value
        await player?.stop()
        player = nil
        webView.stopLoading()
    }

    private func startMonitoring(_ engine: MPVPlaybackEngine) {
        monitor = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    let state = try await engine.interpolationStatus()
                    switch state {
                    case .disabled: self?.svpStatus = "SVP: Off"
                    case .waiting: self?.svpStatus = "SVP: Waiting for interpolation. Check SVP Manager if this persists."
                    case .connected: self?.svpStatus = "SVP: Filter connected; waiting for frame rate confirmation…"
                    case .interpolating(let source, let output):
                        self?.svpStatus = String(format: "SVP: Active · %.2f → %.2f fps", source, output)
                    }
                    try await Task.sleep(for: .seconds(2))
                }
            } catch is CancellationError {
            } catch {
                self?.svpStatus = "SVP: Player unavailable"
            }
        }
    }

    private func isAllowed(_ url: URL?) -> Bool {
        guard let url, url.scheme == "https", url.user == nil, url.password == nil, let host = url.host?.lowercased() else { return false }
        return host == allowedHost || host.hasSuffix("." + allowedHost)
    }
}

@MainActor
private final class WeakMediaHandler: NSObject, WKScriptMessageHandler {
    weak var target: KinopubBrowserModel?
    init(_ target: KinopubBrowserModel) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
