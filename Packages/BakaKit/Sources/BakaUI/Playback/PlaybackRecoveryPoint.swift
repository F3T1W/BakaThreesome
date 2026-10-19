import Foundation
import Playback
import Tracking

/// A retry stores episode identity and position, never the expiring media URL.
struct PlaybackRecoveryPoint {
    let context: EpisodeContext
    let origin: URL
    let seconds: Double

    var pageURL: URL {
        let suffix = context.season > 0 ? "/s\(context.season)e\(context.episode)" : ""
        return origin.appendingPathComponent("item/view/\(context.kinopubItemID)" + suffix)
    }

    var isValid: Bool {
        context.isValid && seconds.isFinite && seconds >= 0 && origin.scheme == "https"
            && origin.host != nil && origin.user == nil && origin.password == nil
            && origin.query == nil && origin.fragment == nil && (origin.path.isEmpty || origin.path == "/")
    }

    static func canRetry(_ error: PlaybackError) -> Bool {
        switch error {
        case .commandRejected, .timedOut, .mediaFailed: true
        default: false
        }
    }
}
