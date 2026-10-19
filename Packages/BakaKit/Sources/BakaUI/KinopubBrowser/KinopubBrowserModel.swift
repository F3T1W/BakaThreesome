import Catalog
import Foundation
import Kinopub
import Matching
import Observation
import Playback
import Tracking
import WebKit

struct BrowserEpisodeChoice: Identifiable {
    let destination: KinopubEpisode
    let title: String
    var id: String { destination.id }
}

@MainActor
@Observable
final class KinopubBrowserModel: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate {
    var useSVP: Bool { get { playback.useSVP } set { playback.useSVP = newValue } }
    var svpStatus: String { playback.svpStatus }
    var playerStatus: String { playback.status }
    var progressError: String? { playback.progressError }
    private(set) var isWorking = false
    private(set) var isPreparing = false
    private(set) var websiteOrigin = URL(string: "https://gxux.pkr.ovh")!
    var audioSourceID: UUID?
    var address = "https://gxux.pkr.ovh"
    private(set) var candidates: [BrowserMediaCandidate] = []
    private(set) var episodeChoices: [BrowserEpisodeChoice] = []
    private(set) var status = "Sign in on the website, open an episode, and start its web player to discover media."
    private(set) var errorMessage: String?
    @ObservationIgnored private(set) var webView: WKWebView!
    @ObservationIgnored private let history: ResumeLibraryModel
    @ObservationIgnored private let playback: MPVPlaybackModel
    @ObservationIgnored private var allowedHost = "gxux.pkr.ovh"
    private var linkedTitle: EpisodeContext?
    private var finishedURL: URL?
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var operationID = UUID()
    @ObservationIgnored private var preparationID = UUID()
    @ObservationIgnored private var preparing: Task<Void, Never>?
    @ObservationIgnored private var pendingResume: (context: EpisodeContext, seconds: Double)?
    @ObservationIgnored private var isStopping = false
    @ObservationIgnored private var hasLoaded = false

    init(history: ResumeLibraryModel, playback: MPVPlaybackModel) {
        self.history = history; self.playback = playback
        super.init()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = KinopubWebsiteSession.dataStore()
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        let controller = configuration.userContentController
        controller.add(WeakMediaHandler(self), contentWorld: .defaultClient, name: "bakaMedia")
        controller.add(WeakMediaHandler(self), contentWorld: .defaultClient, name: "bakaEpisodes")
        for name in ["MediaDiscovery", "EpisodeDiscovery"] {
            if let path = Bundle.module.url(forResource: name, withExtension: "js"),
               let script = try? String(contentsOf: path, encoding: .utf8) {
                controller.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd,
                                                      forMainFrameOnly: name == "EpisodeDiscovery", in: .defaultClient))
            }
        }
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self; webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
    }

    var currentEpisode: EpisodeContext? {
        guard let title = linkedTitle, let page = finishedURL, page == webView.url else { return nil }
        let context: EpisodeContext
        if let episode = KinopubEpisode(url: page), episode.itemID == title.kinopubItemID, episode.season == title.season {
            guard let selected = title.selectingEpisode(itemID: episode.itemID, season: episode.season, episode: episode.episode) else { return nil }
            context = selected
        } else if title.kind == "movie", title.season == 0,
                  page.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "item/view/\(title.kinopubItemID)" {
            context = title
        } else { return nil }
        return context.isValid ? context : nil
    }

    var currentEpisodeNumber: Int { finishedURL.flatMap(KinopubEpisode.init(url:))?.episode ?? 0 }

    var savedEpisode: ResumeEntry? { history.entry(for: currentEpisode) }
    var primaryManifest: BrowserMediaCandidate? {
        guard let page = finishedURL, page == webView.url else { return nil }
        return candidates.first { $0.isPrimaryManifest && $0.isMainFrame && $0.source == "Video" && $0.pageURL == page }
    }

    func loadIfNeeded() { if !hasLoaded { navigate() } }

    func navigate() {
        cancelPreparation()
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", let host = url.host, url.user == nil, url.password == nil else {
            errorMessage = "Enter an HTTPS website address without embedded credentials."
            return
        }
        var origin = URLComponents()
        origin.scheme = "https"; origin.host = host; origin.port = url.port
        guard let base = origin.url else { return }
        websiteOrigin = base; allowedHost = host.lowercased()
        loadPage(url)
    }

    private func loadPage(_ url: URL) {
        hasLoaded = true; finishedURL = nil
        errorMessage = nil; candidates = []; episodeChoices = []; audioSourceID = nil
        address = url.absoluteString
        webView.load(URLRequest(url: url))
    }

    func openTitle(anime: AnimeSummary, mapping: EpisodeMapping) {
        guard mapping.animeID.rawValue == anime.id else { return }
        cancelPreparation()
        linkedTitle = EpisodeContext(animeID: mapping.animeID, title: anime.title, kind: anime.kind,
                                     kinopubItemID: mapping.kinopubItemID, season: mapping.season, episode: 1)
        let suffix = mapping.season > 0 ? "/s\(mapping.season)e1" : ""
        loadPage(websiteOrigin.appendingPathComponent("item/view/\(mapping.kinopubItemID)" + suffix))
    }

    func chooseEpisode(_ number: Int) {
        guard let choice = episodeChoices.first(where: { $0.destination.episode == number }) else { return }
        cancelPreparation()
        loadPage(choice.destination.url(on: websiteOrigin))
    }

    func resume(_ entry: ResumeEntry, fromBeginning: Bool = false) {
        guard entry.isValid, operation == nil else { return }
        hasLoaded = true
        cancelPreparation()
        run {
            await self.playback.stop()
            try Task.checkCancellation()
            self.linkedTitle = entry.context
            let context = entry.context
            let suffix = context.season > 0 ? "/s\(context.season)e\(context.episode)" : ""
            self.loadPage(self.websiteOrigin.appendingPathComponent("item/view/\(context.kinopubItemID)" + suffix))
            self.pendingResume = (context, fromBeginning ? 0 : entry.position.seconds)
            self.isPreparing = true
        }
    }

    func scan() {
        errorMessage = nil; candidates = []; audioSourceID = nil
        webView.evaluateJavaScript("window.__bakaScanMedia?.(); window.__bakaScanEpisodes?.()", in: nil, in: .defaultClient) { _ in }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "bakaEpisodes" { receiveEpisodes(message); return }
        guard message.name == "bakaMedia", let value = message.body as? [String: String],
              let address = value["address"], let page = value["pageAddress"], let source = value["source"],
              let candidate = BrowserMediaCandidate(address: address, pageAddress: page, source: source,
                                                    isMainFrame: message.frameInfo.isMainFrame),
              isAllowed(webView.url), candidates.count < 100 else { return }
        if candidate.isMainFrame, candidate.pageURL != webView.url { return }
        if let index = candidates.firstIndex(where: { $0.url == candidate.url && $0.pageURL == candidate.pageURL }) {
            if candidate.source == "Video",
               candidates[index].source == "Resource" || (candidate.isMainFrame && !candidates[index].isMainFrame) {
                candidates[index] = candidate
            }
        } else { candidates.append(candidate) }
        tryPendingResume()
    }

    private func receiveEpisodes(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let value = message.body as? [String: Any],
              let address = value["pageAddress"] as? String, let page = URL(string: address),
              page == finishedURL, page == webView.url, isAllowed(page),
              let current = KinopubEpisode(url: page),
              let values = value["episodes"] as? [[String: String]], values.count <= 2000 else { return }
        var seen: Set<String> = []
        episodeChoices = values.compactMap { value in
            guard let address = value["address"], let url = URL(string: address), isAllowed(url),
                  let destination = KinopubEpisode(url: url), destination.itemID == current.itemID,
                  destination.season == current.season, seen.insert(destination.id).inserted else { return nil }
            return BrowserEpisodeChoice(destination: destination, title: value["title"] ?? "")
        }.sorted { $0.destination.episode < $1.destination.episode }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        let url = navigationAction.request.url
        if navigationAction.targetFrame?.isMainFrame == false {
            return url?.scheme == "https" || url?.absoluteString == "about:blank" ? .allow : .cancel
        }
        if let pendingResume, !matchesPending(url, context: pendingResume.context) { cancelPreparation() }
        guard isAllowed(url) else {
            errorMessage = "Navigation to another site was blocked. Enter its trusted HTTPS address above if this is your Kinopub mirror."
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        finishedURL = nil
        candidates = []; episodeChoices = []
        audioSourceID = nil
        errorMessage = nil
        status = "Loading website…"
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishedURL = webView.url
        scan()
        preparePendingResume()
        // Keep query strings and signed addresses out of native UI state.
        if let url = webView.url, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            parts.query = nil; parts.fragment = nil
            address = parts.url?.absoluteString ?? address
        }
        if pendingResume != nil { status = "Refreshing the episode stream for playback…"; return }
        status = candidates.isEmpty
            ? "Open an episode and start its web player. Media sources will appear below."
            : "Found \(candidates.count) media source(s)."
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { cancelPreparation(); errorMessage = "The website could not be loaded. Check its address and your connection." }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        cancelPreparation()
        errorMessage = "The website stopped loading. Try reloading the page."
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if isAllowed(navigationAction.request.url) { webView.load(navigationAction.request) }
        return nil
    }

    func playEpisode(fromBeginning: Bool = false) {
        guard let manifest = primaryManifest else { return }
        let context = currentEpisode
        let seconds = fromBeginning ? 0 : (history.entry(for: context)?.position.seconds ?? 0)
        audioSourceID = nil
        cancelPreparation()
        play(manifest, context: context, seconds: seconds)
    }

    /// Individual sources remain a diagnostic path; only the current main-frame player manifest records progress.
    func play(_ candidate: BrowserMediaCandidate) { cancelPreparation(); play(candidate, context: nil, seconds: 0) }

    private func play(_ candidate: BrowserMediaCandidate, context: EpisodeContext?, seconds: Double) {
        guard operation == nil else { return }
        let requested = ContinuousClock.now
        let audioURL = candidates.first(where: { $0.id == audioSourceID })?.url
        status = "Preparing mpv playback…"
        run {
            let userAgent = try await self.webView.evaluateJavaScript(
                "(() => { document.querySelectorAll('video,audio').forEach(media => media.pause()); return navigator.userAgent; })()"
            ) as? String
            try Task.checkCancellation()
            let source = try PlaybackSource(url: candidate.url, referrer: candidate.referrerOrigin,
                                            userAgent: userAgent, audioURL: audioURL, origin: candidate.referrerOrigin,
                                            startSeconds: seconds)
            try await self.playback.start(source: source, episode: context, requestedAt: requested)
            self.status = context == nil ? "Playback is not linked to an episode." : "Local episode progress is saved automatically."
        }
    }

    private func tryPendingResume() {
        guard let pending = pendingResume, operation == nil, currentEpisode?.id == pending.context.id,
              let manifest = primaryManifest else { return }
        pendingResume = nil; preparing?.cancel(); preparing = nil; isPreparing = false
        audioSourceID = nil
        play(manifest, context: pending.context, seconds: pending.seconds)
    }

    private func matchesPending(_ url: URL?, context: EpisodeContext) -> Bool {
        guard let url, isAllowed(url) else { return false }
        if context.season == 0 { return url.path == "/item/view/\(context.kinopubItemID)" }
        return KinopubEpisode(url: url) == KinopubEpisode(itemID: context.kinopubItemID, season: context.season, episode: context.episode)
    }

    private func preparePendingResume() {
        guard pendingResume != nil else { return }
        preparing?.cancel()
        let id = UUID(); preparationID = id
        preparing = Task {
            defer { if preparationID == id { isPreparing = false } }
            guard let url = Bundle.module.url(forResource: "PrepareEpisode", withExtension: "js"),
                  let script = try? String(contentsOf: url, encoding: .utf8) else { return }
            var requested = false
            for _ in 0..<20 {
                if Task.isCancelled || pendingResume == nil || preparationID != id { return }
                if let response = try? await webView.callAsyncJavaScript(script, arguments: ["requested": requested],
                                                                        in: nil, contentWorld: .defaultClient) as? String,
                   response == "requested" { requested = true }
                guard !Task.isCancelled, preparationID == id else { return }
                tryPendingResume()
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            }
            if pendingResume != nil {
                status = "Start the web player to refresh its stream. The selected episode will then open in mpv at the requested position."
            }
        }
    }

    private func cancelPreparation() {
        preparationID = UUID()
        pendingResume = nil; preparing?.cancel(); preparing = nil; isPreparing = false
    }

    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        guard operation == nil else { return }
        let id = UUID(); operationID = id; isWorking = true
        errorMessage = nil
        operation = Task {
            defer { if operationID == id { operation = nil; isWorking = false } }
            do { try await action() }
            catch is CancellationError { status = "Playback cancelled." }
            catch let error as PlaybackError { errorMessage = error.errorDescription }
            catch let error as ResumeStartError { errorMessage = error.errorDescription }
            catch { errorMessage = "The browser could not prepare this episode. Reopen it and try again." }
        }
    }

    func stop() {
        guard !isStopping else { return }
        cancelPreparation()
        let previous = operation
        previous?.cancel()
        let id = UUID(); operationID = id; isStopping = true; isWorking = true
        operation = Task {
            defer { isStopping = false; if operationID == id { operation = nil; isWorking = false } }
            await previous?.value
            await playback.stop()
            status = "Playback stopped."
        }
    }

    func clearSession() {
        guard operation == nil else { return }
        cancelPreparation()
        run {
            self.webView.stopLoading()
            await self.playback.stop()
            self.candidates = []; self.episodeChoices = []; self.finishedURL = nil
            self.audioSourceID = nil; self.linkedTitle = nil
            await self.webView.configuration.websiteDataStore.removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
            self.status = "Browser session cleared. Sign in again on the website."
            self.loadPage(self.websiteOrigin)
        }
    }

    func shutdown() async {
        cancelPreparation()
        operation?.cancel()
        await operation?.value
        await playback.stop()
        webView.stopLoading()
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
