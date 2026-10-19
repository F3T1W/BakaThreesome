import Foundation

public struct KinopubEpisode: Codable, Hashable, Identifiable, Sendable {
    public let itemID: Int64
    public let season: Int
    public let episode: Int
    public var id: String { "\(itemID):\(season):\(episode)" }

    public init?(itemID: Int64, season: Int, episode: Int) {
        guard itemID > 0, (1...999).contains(season), (1...100000).contains(episode) else { return nil }
        self.itemID = itemID; self.season = season; self.episode = episode
    }

    public init?(url: URL) {
        guard url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else { return nil }
        let parts = url.path.split(separator: "/")
        guard parts.count == 4, parts[0] == "item", parts[1] == "view", let item = Int64(parts[2]),
              let separator = parts[3].firstIndex(of: "e"), parts[3].first == "s",
              let season = Int(parts[3][parts[3].index(after: parts[3].startIndex)..<separator]),
              let episode = Int(parts[3][parts[3].index(after: separator)...]) else { return nil }
        self.init(itemID: item, season: season, episode: episode)
    }

    public func url(on origin: URL) -> URL {
        origin.appendingPathComponent("item/view/\(itemID)/s\(season)e\(episode)")
    }
}
