import Foundation
import WebKit

@MainActor
public enum KinopubWebsiteSession {
    public static func dataStore() -> WKWebsiteDataStore {
        WKWebsiteDataStore(forIdentifier: UUID(uuidString: "B6F18F2D-5753-42FA-9C66-A11A6DA94720")!)
    }
}

/// Searches the user's signed-in website without exporting cookies or altering the visible browser.
@MainActor
public final class KinopubWebsiteCatalog: NSObject, KinopubCatalog, WKNavigationDelegate {
    private struct Failure: Decodable { let error: String? }
    private var origin: URL?
    private var webView: WKWebView?
    private var pending: CheckedContinuation<Void, Error>?
    private var timeout: Task<Void, Never>?
    private var isBusy = false
    private var loaded = false

    public override init() { super.init() }

    public func configure(origin: URL) throws {
        guard !isBusy, origin.scheme == "https", origin.host != nil,
              origin.user == nil, origin.password == nil else { throw KinopubSearchError.busy }
        guard self.origin != origin else { return }
        self.origin = origin
        loaded = false
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = KinopubWebsiteSession.dataStore()
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        webView?.stopLoading()
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView?.navigationDelegate = self
    }

    public func search(_ query: String) async throws -> KinopubSearchResults {
        try await perform(mode: "search", arguments: ["query": query])
    }

    public func details(_ item: KinopubTitle) async throws -> KinopubTitle {
        struct Result: Decodable { let item: KinopubTitle }
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(item))
        let result: Result = try await perform(mode: "details", arguments: ["item": encoded])
        return result.item
    }

    static func readerScript() throws -> String {
        guard let url = Bundle.module.url(forResource: "CatalogReader", withExtension: "js") else {
            throw KinopubSearchError.unsupportedPage
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func perform<Result: Decodable>(mode: String, arguments: [String: Any]) async throws -> Result {
        guard !isBusy else { throw KinopubSearchError.busy }
        guard let webView, let origin else { throw KinopubSearchError.unavailable }
        isBusy = true
        defer { isBusy = false }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            if !loaded { try await load(origin, in: webView) }
            try Task.checkCancellation()
            let script = try Self.readerScript()
            var values = arguments
            values["mode"] = mode
            let result: Any?
            do {
                result = try await webView.callAsyncJavaScript(
                    script, arguments: values,
                    in: nil, contentWorld: .defaultClient
                )
            } catch {
                try Task.checkCancellation()
                throw KinopubSearchError.unavailable
            }
            try Task.checkCancellation()
            guard let json = result as? String, let data = json.data(using: .utf8) else {
                throw KinopubSearchError.unsupportedPage
            }
            if let error = try JSONDecoder().decode(Failure.self, from: data).error {
                switch error {
                case "signInRequired":
                    loaded = false
                    throw KinopubSearchError.signInRequired
                case "unsupported": throw KinopubSearchError.unsupportedPage
                default: throw KinopubSearchError.unavailable
                }
            }
            do { return try JSONDecoder().decode(Result.self, from: data) }
            catch { throw KinopubSearchError.unsupportedPage }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }

    private func load(_ url: URL, in webView: WKWebView) async throws {
        try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            webView.load(URLRequest(url: url))
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(20)) }
                catch { return }
                self?.finish(.failure(KinopubSearchError.unavailable))
                webView.stopLoading()
            }
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        timeout?.cancel()
        timeout = nil
        let continuation = pending
        pending = nil
        continuation?.resume(with: result)
    }

    private func cancel() {
        webView?.evaluateJavaScript("window.__bakaCatalogAbort?.abort()", in: nil, in: .defaultClient) { _ in }
        webView?.stopLoading()
        finish(.failure(CancellationError()))
    }

    public func shutdown() { cancel(); webView = nil; loaded = false }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded = true
        finish(.success(()))
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(KinopubSearchError.unavailable))
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(KinopubSearchError.unavailable))
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url, let origin,
              url.scheme == origin.scheme, url.host == origin.host, url.port == origin.port,
              url.user == nil, url.password == nil else { return .cancel }
        return .allow
    }
}
