import Foundation

public enum KinopubFormat: String, Codable, Sendable { case movie, series }

public struct KinopubTitle: Codable, Identifiable, Hashable, Sendable {
    public let id: Int64
    public let titles: [String]
    public let year: Int?
    public let seasons: [Int]
    public let format: KinopubFormat?

    public init(id: Int64, titles: [String], year: Int?, seasons: [Int] = [], format: KinopubFormat? = nil) {
        self.id = id
        self.titles = titles
        self.year = year
        self.seasons = seasons
        self.format = format
    }

    public var title: String { titles.first ?? "Untitled" }
}

public struct KinopubSearchResults: Codable, Sendable {
    public let items: [KinopubTitle]
    public let isComplete: Bool
    public init(items: [KinopubTitle], isComplete: Bool) {
        self.items = items
        self.isComplete = isComplete
    }
}

public protocol KinopubCatalog: Sendable {
    func search(_ query: String) async throws -> KinopubSearchResults
    func details(_ item: KinopubTitle) async throws -> KinopubTitle
}

public enum KinopubSearchError: Error, LocalizedError {
    case signInRequired, unavailable, unsupportedPage, busy
    public var errorDescription: String? {
        switch self {
        case .signInRequired: "Sign in on the Kinopub website in the sidebar, then try again."
        case .unavailable: "Kinopub search could not be loaded. Check the website and try again."
        case .unsupportedPage: "This mirror's search page could not be read. Open Kinopub to search manually."
        case .busy: "Another Kinopub search is still running."
        }
    }
}
