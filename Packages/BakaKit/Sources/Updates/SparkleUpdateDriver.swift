import Foundation
import Sparkle

/// Sparkle owns signature verification, replacement, recovery and relaunch.
@MainActor
final class SparkleUpdateDriver: NSObject, UpdateDriver, SPUUpdaterDelegate, @MainActor SPUStandardUserDriverDelegate {
    var onChange: (@MainActor (UpdateEvent) -> Void)?
    private var controller: SPUStandardUpdaterController?
    private var checkObservation: NSKeyValueObservation?

    func start() -> Bool {
        // Package tests and previews are not application bundles and must not start an updater.
        guard Bundle.main.bundleURL.pathExtension == "app",
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              (try? UpdateConfiguration(publicKey: key)) != nil,
              Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String == UpdateConfiguration.feedURL.absoluteString
        else { return false }

        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        self.controller = controller
        checkObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.onChange?(.canCheck(self.controller?.updater.canCheckForUpdates ?? false))
            }
        }
        controller.startUpdater()
        return true
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    public var supportsGentleScheduledUpdateReminders: Bool { true }

    public func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    public func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        if !handleShowingUpdate { onChange?(.available(update.displayVersionString)) }
    }

    public func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        onChange?(.dismissed)
    }

    public func standardUserDriverWillFinishUpdateSession() {
        onChange?(.dismissed)
    }
}
