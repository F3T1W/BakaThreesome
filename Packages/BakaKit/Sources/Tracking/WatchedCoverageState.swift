import Foundation

public struct WatchedCoverageState: Codable, Equatable, Sendable {
    public let duration: Double
    public let intervals: [ClosedRange<Double>]
    public init(duration: Double, intervals: [ClosedRange<Double>]) {
        self.duration = duration; self.intervals = intervals
    }
    public var isValid: Bool {
        guard duration.isFinite, duration > 0, intervals.count <= 10000 else { return false }
        var end: Double = -1
        for range in intervals {
            guard range.lowerBound.isFinite, range.upperBound.isFinite, range.lowerBound >= 0,
                  range.lowerBound > end, range.upperBound > range.lowerBound, range.upperBound <= duration else { return false }
            end = range.upperBound
        }
        return true
    }

    public func merging(_ newer: WatchedCoverageState) -> WatchedCoverageState {
        guard abs(duration - newer.duration) <= 0.5 else { return newer }
        var merged: [ClosedRange<Double>] = []
        for range in (intervals + newer.intervals).sorted(by: { $0.lowerBound < $1.lowerBound }) {
            let end = min(newer.duration, range.upperBound)
            guard end > range.lowerBound else { continue }
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, end)
            } else { merged.append(range.lowerBound...end) }
        }
        return WatchedCoverageState(duration: newer.duration, intervals: merged)
    }
}

public struct WatchedCoverageRecord: Codable, Sendable {
    public let episode: WatchedEpisode
    public let state: WatchedCoverageState
    public let updatedAt: Date
    public var id: String { "\(episode.userID):\(episode.context.id):\(episode.number)" }
    public var isValid: Bool { episode.isValid && state.isValid && updatedAt.timeIntervalSince1970.isFinite }
    public init(episode: WatchedEpisode, state: WatchedCoverageState, updatedAt: Date = .now) {
        self.episode = episode; self.state = state; self.updatedAt = updatedAt
    }
}
