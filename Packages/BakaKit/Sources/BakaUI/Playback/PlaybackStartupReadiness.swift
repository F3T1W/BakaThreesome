import Playback

enum PlaybackStartupReadiness {
    static func canBegin(_ state: PlaybackSnapshot, source: PlaybackSource, linkedEpisode: Bool) -> Bool {
        guard !state.isIdle, state.videoCodec != nil || state.audioCodec != nil else { return false }
        // Linked episodes require video; optimized HLS also waits for audio before its compatibility retry.
        if linkedEpisode, state.videoCodec == nil { return false }
        if linkedEpisode, source.needsCompatibilityFallback, state.audioCodec == nil { return false }
        // An explicitly separate audio source may become ready after the video.
        if source.audioURL != nil, state.audioCodec == nil { return false }
        return true
    }
}
