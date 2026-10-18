import Foundation

public struct BrowserMediaCandidate: Identifiable, Sendable {
    public let id = UUID()
    public let url: URL
    public let pageURL: URL
    public let source: String

    public init?(address: String, pageAddress: String, source: String) {
        guard address.utf8.count <= 16384, pageAddress.utf8.count <= 16384,
              let url = URL(string: address), let page = URL(string: pageAddress),
              url.scheme?.lowercased() == "https", url.host != nil,
              page.scheme?.lowercased() == "https", page.host != nil,
              url.user == nil, url.password == nil, page.user == nil, page.password == nil,
              ["Video", "Link", "Resource"].contains(source)
        else { return nil }
        self.url = url
        pageURL = page
        self.source = source
    }

    public var isPrimaryManifest: Bool {
        url.host == pageURL.host && url.path.hasPrefix("/manifest/") && url.pathExtension == "m3u8"
    }

    public var displayName: String {
        let format = url.pathExtension.isEmpty ? "STREAM" : url.pathExtension.uppercased()
        return "\(isPrimaryManifest ? "Player manifest" : format) · \(url.host ?? "Unknown host") · \(source)"
    }

    /// Match the browser's usual cross-origin referrer policy without forwarding query tokens.
    public var referrerOrigin: URL? {
        guard var parts = URLComponents(url: pageURL, resolvingAgainstBaseURL: false) else { return nil }
        parts.path = "/"
        parts.query = nil
        parts.fragment = nil
        return parts.url
    }
}
