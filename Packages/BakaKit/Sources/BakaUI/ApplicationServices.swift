import Foundation
import Matching
import Observation
import Playback

@MainActor
public final class ApplicationServices {
    let diagnostics = DiagnosticsModel()
    let shikimori = ShikimoriModel()
    let kinopubBrowser = KinopubBrowserModel()
    let episodeMappings = EpisodeMappingStore()

    public init() {}

    public func shutdown() async {
        await kinopubBrowser.shutdown()
        await shikimori.shutdown()
        await diagnostics.shutdown()
    }
}

@MainActor
@Observable
final class DiagnosticsModel {
    private(set) var environment = PlaybackEnvironment.discover()
    private(set) var capabilities: PlayerCapabilities?
    private(set) var isChecking = false
    private(set) var ipcPassed = false
    private(set) var errorMessage: String?
    private var checkTask: Task<Void, Never>?

    var operatingSystemVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    func refresh() async {
        guard checkTask == nil else { return }
        let task = Task { await performCheck() }
        checkTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        checkTask = nil
    }

    func shutdown() async {
        checkTask?.cancel()
        await checkTask?.value
    }

    private func performCheck() async {
        isChecking = true
        capabilities = nil
        ipcPassed = false
        errorMessage = nil
        environment = PlaybackEnvironment.discover()
        defer { isChecking = false }
        do {
            guard let executable = environment.mpvURL else { throw PlaybackError.playerNotFound }
            let detected = try await MPVCapabilityProbe(executable: executable).inspect()
            try Task.checkCancellation()
            capabilities = detected
            let engine = MPVPlaybackEngine(executable: executable, headless: true)
            try await PlayerIPCCheck().run(using: engine)
            try Task.checkCancellation()
            ipcPassed = true
        } catch is CancellationError {
            // Navigation and application shutdown cancel checks without showing an error.
        } catch let error as PlaybackError {
            if !Task.isCancelled { errorMessage = error.errorDescription }
        } catch {
            if !Task.isCancelled {
                errorMessage = "The player check could not be completed. Try again after checking your installation."
            }
        }
    }
}
