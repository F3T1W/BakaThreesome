import Foundation
@testable import Kinopub
import Testing
import WebKit

@Suite(.enabled(if: ProcessInfo.processInfo.environment["BAKA_WEBKIT_INTEGRATION"] == "1"))
@MainActor
struct CatalogReaderTests {
    @Test func realDOMReaderGroupsAliasesFollowsPaginationAndDiscoversSeasons() async throws {
        let page = CatalogTestPage()
        try await page.load()
        let searchHTML = """
        <div><article><a href="/item/view/10"><img></a><h3><a href="/item/view/10">Blue Sky</a></h3>
        <a href="/item/view/10">Sky of Blue</a><span>2017</span></article>
        <article><a href="/item/view/11">Blue Sky 2</a><span>2019</span></article></div>
        <ul class="pagination"><li class="next"><a href="?query=Blue%20Sky&amp;page=2">Next</a></li></ul>
        """
        let nextHTML = "<article><a href='/item/view/12'>Blue Sky: The Movie</a><span>2020</span></article>"
        let result = try await page.read(mode: "search", pages: [searchHTML, nextHTML])
        let decoded = try JSONDecoder().decode(KinopubSearchResults.self, from: Data(result.utf8))
        #expect(decoded.isComplete)
        #expect(decoded.items.count == 3)
        #expect(decoded.items.first?.titles == ["Blue Sky", "Sky of Blue"])
        #expect(decoded.items.first?.year == 2017)
        let detailHTML = """
        <h1>Blue Sky</h1><a href='/item/view/10/s1e1'>First season</a>
        <select><option value='/item/view/10/s2e1'>Second season</option></select>
        <a href='/item/view/11/s3e1'>Unrelated title</a>
        """
        let detail = try await page.read(mode: "details", pages: [detailHTML])
        struct Envelope: Decodable { let item: KinopubTitle }
        #expect(try JSONDecoder().decode(Envelope.self, from: Data(detail.utf8)).item.seasons == [1, 2])
    }

    @Test func explicitSchemaFormatIsReadWithoutGuessingFromMissingSeasons() async throws {
        let page = CatalogTestPage()
        try await page.load()
        struct Envelope: Decodable { let item: KinopubTitle }
        let movie = try await page.read(mode: "details", pages: ["""
        <h1>Blue Sky</h1><script type="application/ld+json">{"@type":"Movie","url":"/item/view/10"}</script>
        """])
        #expect(try JSONDecoder().decode(Envelope.self, from: Data(movie.utf8)).item.format == .movie)
        let unknown = try await page.read(mode: "details", pages: ["<h1>Blue Sky</h1>"])
        #expect(try JSONDecoder().decode(Envelope.self, from: Data(unknown.utf8)).item.format == nil)
        let unrelated = try await page.read(mode: "details", pages: ["""
        <h1>Blue Sky</h1><script type="application/ld+json">{"@type":"Movie","url":"/item/view/99"}</script>
        """])
        #expect(try JSONDecoder().decode(Envelope.self, from: Data(unrelated.utf8)).item.format == nil)
    }

    @Test func loginAndUnexpectedRedirectAreErrorsRatherThanNotFound() async throws {
        let page = CatalogTestPage()
        try await page.load()
        let login = try await page.read(mode: "search", pages: ["<input type='password'>"])
        #expect(login.contains("signInRequired"))
        let redirected = try await page.read(mode: "search", pages: ["<h1>Other</h1>"], responseOrigin: "https://other.example")
        #expect(redirected.contains("unsupported"))
    }
}

@MainActor
private final class CatalogTestPage: NSObject, WKNavigationDelegate {
    private let view: WKWebView
    private var pending: CheckedContinuation<Void, Error>?
    private var timeout: Task<Void, Never>?
    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        view = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        view.navigationDelegate = self
    }
    func load() async throws {
        try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            view.loadHTMLString("<form action='/item/search' method='get'><input name='query'></form>",
                                baseURL: URL(string: "https://mirror.example"))
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                self?.pending?.resume(throwing: KinopubSearchError.unavailable)
                self?.pending = nil
            }
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        timeout?.cancel()
        pending?.resume()
        pending = nil
    }
    func read(mode: String, pages: [String], responseOrigin: String = "https://mirror.example") async throws -> String {
        let setup = """
        let call = 0;
        const fetch = async (url) => ({
            ok: true, url: responseOrigin + url.pathname + url.search,
            text: async () => pages[call++]
        });
        """
        let script = setup + (try KinopubWebsiteCatalog.readerScript())
        let result = try await view.callAsyncJavaScript(script, arguments: [
            "mode": mode, "query": "Blue Sky", "pages": pages, "responseOrigin": responseOrigin,
            "item": ["id": 10, "titles": ["Sky of Blue"], "year": 2017, "seasons": []] as [String: Any]
        ], in: nil, contentWorld: .defaultClient)
        return try #require(result as? String)
    }
}
