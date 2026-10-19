import AppKit
import Foundation
import Observation
import OSLog
import Playback
import Tracking

@MainActor
@Observable
final class MPVPlaybackModel {
    var useSVP = UserDefaults.standard.object(forKey: "playback.useSVP") as? Bool ?? true {
        didSet { UserDefaults.standard.set(useSVP, forKey: "playback.useSVP") }
    }
    private(set) var isWorking = false
    private(set) var status = ""
    private(set) var svpStatus = "SVP: Off"
    private(set) var progressError: String?
    let tracks = PlaybackTrackModel()
    let opening = OpeningSkipModel()
    var onPlaybackSnapshot: (@MainActor (PlaybackSnapshot, EpisodeContext?, UUID) -> Void)?
    var onPlaybackStopped: (@MainActor () -> Void)?
    var onStreamFailure: (@MainActor (EpisodeContext, Double) -> Void)?
    private let progress: ProgressSyncModel
    private let history: ResumeLibraryModel
    @ObservationIgnored private let capabilityCache = MPVCapabilityCache()
    @ObservationIgnored private var warmup: Task<Void, Never>?
    @ObservationIgnored private var engine: MPVPlaybackEngine?
    @ObservationIgnored private var recorder: ResumeRecorder?
    private(set) var activeEpisode: EpisodeContext?
    @ObservationIgnored private var lastPosition: Double = 0
    @ObservationIgnored private var monitor: Task<Void, Never>?

    init(history: ResumeLibraryModel, progress: ProgressSyncModel) {
        self.history = history; self.progress = progress
        opening.onSeek = { [weak progress] in progress?.interruptPlayback() }
    }

    func start(source: PlaybackSource, episode: EpisodeContext?, requestedAt: ContinuousClock.Instant? = nil) async throws {
        guard !isWorking else { throw PlaybackError.alreadyRunning }
        isWorking = true
        defer { isWorking = false }
        let requested = requestedAt ?? ContinuousClock.now
        await stop()
        let source = try source.preferringTracks(tracks.preferences)
        status = "Starting mpv…"
        progressError = nil
        var phase = "starting the player"
        do {
            try Task.checkCancellation()
            let environment = PlaybackEnvironment.discover()
            guard let executable = environment.mpvURL else { throw PlaybackError.playerNotFound }
            try Task.checkCancellation()
            let player = MPVPlaybackEngine(executable: executable, enableSVP: useSVP)
            engine = player
            svpStatus = useSVP ? "SVP: Waiting for video…" : "SVP: Off"
            async let preparation: Void = prepareSVP(environment, enabled: useSVP)
            try await player.start()
            let playerReady = ContinuousClock.now
            let launchSeconds = requested.duration(to: playerReady).secondsValue
            status = String(format: "mpv started in %.2f s. Loading the episode…", launchSeconds)
            Logger(subsystem: "dev.bakathreesome", category: "PlaybackStartup")
                .notice("Player IPC ready in \(launchSeconds, privacy: .public) seconds")
            phase = "loading the media stream"
            var activeSource = source
            do { try await player.load(activeSource) }
            catch PlaybackError.commandRejected where source.needsCompatibilityFallback {
                try Task.checkCancellation()
                activeSource = try source.conservativeStartup()
                try await player.load(activeSource)
            }
            phase = "preparing SVP"
            try await preparation
            phase = "waiting for video and audio"
            status = "The stream is loaded. Waiting for video, audio and player filters…"
            let mediaReady = ContinuousClock.now
            var retriedProbe = !activeSource.needsCompatibilityFallback
            var deadline = ContinuousClock.now.advanced(by: .seconds(20))
            while true {
                try Task.checkCancellation()
                let state = try await player.snapshot(until: deadline)
                if state.hasFailed { throw PlaybackError.mediaFailed }
                if let start = source.startSeconds, start > 0,
                   let duration = state.position.duration, start >= duration - 1 {
                    throw ResumeStartError.positionOutsideMedia
                }
                if !retriedProbe, mediaReady.duration(to: .now) >= .seconds(2),
                   state.videoCodec == nil || (episode != nil && state.audioCodec == nil) {
                    // Preserve compatibility with HLS manifests that omit usable codec information.
                    retriedProbe = true
                    activeSource = try source.conservativeStartup()
                    try await player.load(activeSource)
                    deadline = ContinuousClock.now.advanced(by: .seconds(20))
                    continue
                }
                if !state.isIdle, state.videoCodec != nil || state.audioCodec != nil {
                    if episode != nil, state.videoCodec == nil {
                        // A linked episode must wait for video, even if audio becomes ready first.
                    } else if activeSource.needsCompatibilityFallback && episode != nil && state.audioCodec == nil {
                        // Give optimized startup a short audio readiness window before the compatibility retry.
                    } else if source.audioURL != nil, state.audioCodec == nil {
                        // Separate audio can arrive after the video track.
                    } else {
                        if let episode, episode.isValid, state.videoCodec != nil {
                            activeEpisode = episode
                            lastPosition = source.startSeconds ?? 0
                            await progress.begin(episode)
                            recorder = ResumeRecorder(context: episode, store: history.store)
                            history.activeEpisodeID = episode.id
                        }
                        status = state.videoCodec != nil && state.audioCodec != nil
                            ? "mpv is playing video and audio."
                            : (state.videoCodec != nil ? "mpv is playing video only." : "mpv is playing audio only.")
                        if let episode, recorder != nil { status += " \(episode.title) · \(episode.label)" }
                        else { status += " Playback progress is not linked to a Shikimori episode." }
                        let total = requested.duration(to: .now).secondsValue
                        let process = requested.duration(to: playerReady).secondsValue
                        let media = playerReady.duration(to: mediaReady).secondsValue
                        status += String(format: " Ready in %.2f s.", total)
                        Logger(subsystem: "dev.bakathreesome", category: "PlaybackStartup")
                            .notice("Startup seconds: player=\(process, privacy: .public), media=\(media, privacy: .public), ready=\(total, privacy: .public), compatibilityRetry=\(retriedProbe && source.needsCompatibilityFallback, privacy: .public)")
                        await capture(state)
                        await opening.connect(player: player, chapters: player)
                        opening.observe(state)
                        await tracks.connect(player)
                        startMonitoring(player)
                        return
                    }
                }
                guard ContinuousClock.now < deadline else { throw PlaybackError.timedOut }
                try await Task.sleep(for: .milliseconds(250))
            }
        } catch {
            await stop()
            status = "Playback did not start while \(phase)."
            Logger(subsystem: "dev.bakathreesome", category: "PlaybackStartup")
                .notice("Startup failed while \(phase, privacy: .public)")
            throw error
        }
    }

    func hasEnded(_ context: EpisodeContext) async -> Bool {
        guard let player = engine, activeEpisode?.id == context.id,
              let snapshot = try? await player.snapshot(), !Task.isCancelled,
              engine === player, activeEpisode?.id == context.id else { return false }
        return snapshot.hasEnded && !snapshot.hasFailed
    }

    func warmUp() {
        guard warmup == nil, let executable = PlaybackEnvironment.discover().mpvURL else { return }
        warmup = Task { _ = try? await capabilityCache.inspect(executable) }
    }

    func shutdown() async {
        await stop()
        await capabilityCache.shutdown()
        await warmup?.value
    }

    private func prepareSVP(_ environment: PlaybackEnvironment, enabled: Bool) async throws {
        guard enabled else { return }
        guard let svp = environment.svpURL, let executable = environment.mpvURL,
              try await capabilityCache.inspect(executable).hasVapourSynth else {
            throw PlaybackError.svpUnavailable
        }
        try Task.checkCancellation()
        let resolved = svp.resolvingSymlinksInPath()
        if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleURL?.resolvingSymlinksInPath() == resolved }) {
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        do { _ = try await NSWorkspace.shared.openApplication(at: svp, configuration: configuration) }
        catch { throw PlaybackError.svpUnavailable }
    }

    func stop() async {
        onPlaybackStopped?()
        opening.disconnect()
        tracks.disconnect()
        monitor?.cancel()
        await monitor?.value
        monitor = nil
        if let engine, let state = try? await engine.snapshot() { await capture(state, force: true) }
        await flush()
        await engine?.stop()
        engine = nil; recorder = nil; activeEpisode = nil
        await progress.begin(nil)
        history.activeEpisodeID = nil
        svpStatus = "SVP: Off"
        if !status.isEmpty { status = "Playback stopped." }
    }

    private func capture(_ state: PlaybackSnapshot, force: Bool = false) async {
        if !state.hasFailed, !state.hasEnded, !state.isIdle, !state.isSeeking, state.videoCodec != nil,
           state.position.seconds.isFinite, state.position.seconds > 0,
           state.position.duration.map({ state.position.seconds <= $0 }) ?? true {
            lastPosition = state.position.seconds
        }
        guard !state.hasFailed else { return }
        await progress.capture(state)
        guard let recorder else { return }
        do {
            if try await recorder.capture(state, force: force) { await history.refresh() }
            progressError = nil
        } catch {
            progressError = "Playback progress could not be saved. The app will retry; check local storage."
        }
    }

    private func flush() async {
        guard let recorder else { return }
        do {
            if try await recorder.flush() { await history.refresh() }
        } catch {
            progressError = "The latest playback position could not be saved."
        }
    }

    private func startMonitoring(_ player: MPVPlaybackEngine) {
        let sessionID = UUID()
        monitor = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    let snapshot = try await player.snapshot(until: ContinuousClock.now.advanced(by: .seconds(15)))
                    try Task.checkCancellation()
                    if snapshot.hasFailed { throw PlaybackError.mediaFailed }
                    self?.opening.observe(snapshot)
                    await self?.capture(snapshot)
                    try Task.checkCancellation()
                    if let self { self.onPlaybackSnapshot?(snapshot, self.activeEpisode, sessionID) }
                    await self?.tracks.refresh()
                    do {
                        let state = try await player.interpolationStatus()
                        switch state {
                        case .disabled: self?.svpStatus = "SVP: Off"
                        case .waiting: self?.svpStatus = "SVP: Waiting for interpolation. Check SVP Manager if this persists."
                        case .connected: self?.svpStatus = "SVP: Filter connected; waiting for frame rate confirmation…"
                        case .interpolating(let source, let output):
                            self?.svpStatus = String(format: "SVP: Active · %.2f → %.2f fps", source, output)
                        }
                    } catch {
                        try Task.checkCancellation()
                        self?.svpStatus = "SVP: Status unavailable"
                    }
                    try await Task.sleep(for: .seconds(2))
                }
            } catch is CancellationError {
            } catch {
                self?.onPlaybackStopped?()
                let episode = self?.activeEpisode
                let seconds = self?.lastPosition ?? 0
                let streamFailed = (error as? PlaybackError).map(PlaybackRecoveryPoint.canRetry) ?? false
                // A stream failure and an externally closed window both preserve the last good sample.
                self?.opening.disconnect()
                self?.tracks.disconnect()
                await self?.flush()
                await player.stop()
                self?.engine = nil; self?.recorder = nil; self?.activeEpisode = nil
                await self?.progress.begin(nil)
                self?.history.activeEpisodeID = nil
                self?.svpStatus = "SVP: Off"
                self?.status = streamFailed
                    ? "Playback was interrupted. Retry playback at the last known position."
                    : "Player closed. The last sampled position was saved if storage was available."
                if streamFailed, let episode { self?.onStreamFailure?(episode, seconds) }
            }
        }
    }
}

enum ResumeStartError: Error, LocalizedError {
    case positionOutsideMedia
    var errorDescription: String? {
        "The saved position is outside this version of the episode. Choose Play from Beginning; the saved entry was kept."
    }
}

private extension Duration {
    var secondsValue: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
