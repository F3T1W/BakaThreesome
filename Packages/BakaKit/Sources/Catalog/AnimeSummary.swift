import Foundation

public struct AnimeSummary: Codable, Identifiable, Hashable, Sendable {
    public let id: Int64
    public let title: String
    public let episodes: Int
    public let kind: String
    public let communityScore: Double?
}
