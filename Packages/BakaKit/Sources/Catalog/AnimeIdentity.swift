import Foundation

public struct AnimeIdentity: Codable, Sendable {
    public let id: Int64
    public let titles: [String]
    public let year: Int?
    public let kind: String

    public init(id: Int64, titles: [String], year: Int?, kind: String) {
        self.id = id
        self.titles = titles
        self.year = year
        self.kind = kind
    }
}
