import AppKit
import Foundation
import Observation
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
    private let history: ResumeLibraryModel
    @ObservationIgnored private var engine: MPVPlaybackEngine?
    @ObservationIgnored private var recorder: ResumeRecorder?
    @ObservationIgnored private var monitor: Task<Void, Never>?

    init(history: ResumeLibraryModel) { self.history = history }

    func start(source: PlaybackSource, episode: EpisodeContext?) async throws {
        guard !isWorking else { throw PlaybackError.alreadyRunning }
        isWorking = true
        defer { isWorking = false }
        await stop()
        status = "Starting mpv…"
        progressError = nil
        do {
            try Task.checkCancellation()
            let environment = PlaybackEnvironment.discover()
            guard let executable = environment.mpvURL else { throw PlaybackError.playerNotFound }
            if useSVP {
                guard let svp = environment.svpURL,
                      try await MPVCapabilityProbe(executable: executable).inspect().hasVapourSynth else {
                    throw PlaybackError.svpUnavailable
                }
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                do { _ = try await NSWorkspace.shared.openApplication(at: svp, configuration: configuration) }
                catch { throw PlaybackError.svpUnavailable }
            }
            try Task.checkCancellation()
            let player = MPVPlaybackEngine(executable: executable, enableSVP: useSVP)
            engine = player
            svpStatus = useSVP ? "SVP: Waiting for video…" : "SVP: Off"
            try await player.start()
            try await player.load(source)
            let deadline = ContinuousClock.now.advanced(by: .seconds(20))
            while true {
                try Task.checkCancellation()
                let state = try await player.snapshot()
                if let start = source.startSeconds, start > 0,
                   let duration = state.position.duration, start >= duration - 1 {
                    throw ResumeStartError.positionOutsideMedia
                }
                if !state.isIdle, state.videoCodec != nil || state.audioCodec != nil {
                    if episode != nil, state.videoCodec == nil {
                        // A linked episode must wait for video, even if audio becomes ready first.
                    } else if source.audioURL != nil, state.audioCodec == nil {
                        // Separate audio can arrive after the video track.
                    } else {
                        if let episode, episode.isValid, state.videoCodec != nil {
                            recorder = ResumeRecorder(context: episode, store: history.store)
                            history.activeEpisodeID = episode.id
                        }
                        status = state.videoCodec != nil && state.audioCodec != nil
                            ? "mpv is playing video and audio."
                            : (state.videoCodec != nil ? "mpv is playing video only." : "mpv is playing audio only.")
                        if let episode, recorder != nil { status += " \(episode.title) · \(episode.label)" }
                        else { status += " Playback progress is not linked to a Shikimori episode." }
                        await capture(state)
                        startMonitoring(player)
                        return
                    }
                }
                guard ContinuousClock.now < deadline else { throw PlaybackError.timedOut }
                try await Task.sleep(for: .milliseconds(250))
            }
        } catch {
            await stop()
            status = "Playback did not start."
            throw error
        }
    }

    func stop() async {
        monitor?.cancel()
        await monitor?.value
        monitor = nil
        if let engine, let state = try? await engine.snapshot() { await capture(state, force: true) }
        await flush()
        await engine?.stop()
        engine = nil; recorder = nil
        history.activeEpisodeID = nil
        svpStatus = "SVP: Off"
        if !status.isEmpty { status = "Playback stopped." }
    }

    private func capture(_ state: PlaybackSnapshot, force: Bool = false) async {
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
        monitor = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    let snapshot = try await player.snapshot()
                    try Task.checkCancellation()
                    await self?.capture(snapshot)
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
                // The player window may be closed externally. Preserve the last sampled position.
                await self?.flush()
                await player.stop()
                self?.engine = nil; self?.recorder = nil
                self?.history.activeEpisodeID = nil
                self?.svpStatus = "SVP: Off"
                self?.status = "Player closed. The last sampled position was saved if storage was available."
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
