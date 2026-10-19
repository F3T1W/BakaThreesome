import Foundation

public protocol PlaybackEngine: Sendable {
    func start() async throws
    func load(_ source: PlaybackSource) async throws
    func setPaused(_ paused: Bool) async throws
    func seek(to seconds: Double) async throws
    func snapshot() async throws -> PlaybackSnapshot
    func stop() async
}

public struct PlaybackSnapshot: Sendable {
    public let hasEnded: Bool
    public init(isPaused: Bool, isIdle: Bool, position: PlaybackPosition,
                videoCodec: String? = nil, audioCodec: String? = nil, hasEnded: Bool = false,
                speed: Double = 1, isSeeking: Bool = false) {
        self.isPaused = isPaused; self.isIdle = isIdle; self.position = position
        self.videoCodec = videoCodec; self.audioCodec = audioCodec; self.hasEnded = hasEnded
        self.speed = speed; self.isSeeking = isSeeking
    }
    public let speed: Double
    public let isSeeking: Bool
    public let isPaused: Bool
    public let isIdle: Bool
    public let position: PlaybackPosition
    public let videoCodec: String?
    public let audioCodec: String?
}

public enum PlaybackError: Error, LocalizedError, Equatable {
    case playerNotFound
    case launchFailed
    case probeFailed
    case timedOut
    case alreadyRunning
    case notRunning
    case exitedBeforeReady
    case connectionUnavailable
    case disconnected
    case invalidResponse
    case commandRejected
    case propertyUnavailable
    case invalidMediaURL
    case invalidSeek
    case svpUnavailable
    case svpRegistrationFailed

    public var errorDescription: String? {
        switch self {
        case .playerNotFound: "mpv was not found. Install mpv or check its executable location."
        case .launchFailed: "mpv could not be launched. Check the executable and its dependencies."
        case .probeFailed: "mpv did not complete the compatibility check."
        case .timedOut: "mpv did not respond within the time limit."
        case .alreadyRunning: "A player session is already active."
        case .notRunning: "The player session is not running."
        case .exitedBeforeReady: "mpv exited before its IPC connection was ready."
        case .connectionUnavailable: "The player IPC connection is not available."
        case .disconnected: "The player IPC connection was closed."
        case .invalidResponse: "mpv returned an unexpected IPC response."
        case .commandRejected: "mpv could not complete the requested command."
        case .propertyUnavailable: "The requested player property is not available."
        case .invalidMediaURL: "Use a local file or an HTTP or HTTPS media URL."
        case .svpUnavailable: "SVP requires the installed SVP Manager and an mpv build with VapourSynth. Disable SVP to play without interpolation."
        case .svpRegistrationFailed: "SVP socket registration failed. Check the ownership and permissions of /tmp/mpvSockets, or disable SVP."
        case .invalidSeek: "The playback position must be a finite, nonnegative number."
        }
    }
}

public extension PlaybackEngine {
    func load(_ url: URL) async throws {
        try await load(PlaybackSource(url: url))
    }
}
