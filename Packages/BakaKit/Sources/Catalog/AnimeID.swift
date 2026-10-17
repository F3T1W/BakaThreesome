public struct AnimeID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: Int64

    public init(rawValue: Int64) {
        self.rawValue = rawValue
    }
}
