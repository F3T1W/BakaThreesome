public struct PlaybackPosition: Codable, Equatable, Sendable {
    public let seconds: Double
    public let duration: Double?

    public init(seconds: Double, duration: Double?) {
        self.seconds = seconds
        self.duration = duration
    }
}
