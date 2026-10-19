import Foundation
import Playback

/// Counts the union of normally played timeline intervals during one player session.
/// Resume positions, seeks, repeated scenes and long observation gaps cannot create coverage.
public struct WatchedCoverage: Sendable {
    private struct Sample: Sendable {
        let snapshot: PlaybackSnapshot
        let instant: Double
    }
    private var previous: Sample?
    private var intervals: [ClosedRange<Double>] = []
    private var duration: Double?
    public private(set) var fraction: Double = 0
    public var isComplete: Bool { fraction >= 0.9 }

    public init() {}

    public mutating func observe(_ snapshot: PlaybackSnapshot, at instant: Double) {
        guard !snapshot.hasFailed, instant.isFinite, let total = snapshot.position.duration, total.isFinite, total > 0,
              snapshot.position.seconds.isFinite, (0...total).contains(snapshot.position.seconds) else {
            previous = nil
            return
        }
        if let duration, abs(total - duration) > 0.5 {
            intervals = []; fraction = 0; previous = nil
        }
        defer { previous = Sample(snapshot: snapshot, instant: instant) }
        duration = total
        guard let previous else { return }
        let before = previous.snapshot
        let elapsed = instant - previous.instant
        let distance = snapshot.position.seconds - before.position.seconds
        guard elapsed > 0, elapsed <= 6, distance > 0,
              !before.isPaused, !snapshot.isPaused, !before.isIdle, !snapshot.isIdle,
              !before.isSeeking, !snapshot.isSeeking, before.videoCodec != nil, snapshot.videoCodec != nil,
              before.speed.isFinite, (0.25...4).contains(before.speed), before.speed == snapshot.speed else { return }
        let expected = elapsed * before.speed
        guard abs(distance - expected) <= max(0.35, expected * 0.2) else { return }
        intervals.append(before.position.seconds...snapshot.position.seconds)
        let sorted = intervals.sorted { $0.lowerBound < $1.lowerBound }
        intervals = []
        for interval in sorted {
            if let last = intervals.last, interval.lowerBound <= last.upperBound {
                intervals[intervals.count - 1] = last.lowerBound...max(last.upperBound, interval.upperBound)
            } else { intervals.append(interval) }
        }
        fraction = min(1, intervals.reduce(0) { $0 + $1.upperBound - $1.lowerBound } / total)
    }
}
