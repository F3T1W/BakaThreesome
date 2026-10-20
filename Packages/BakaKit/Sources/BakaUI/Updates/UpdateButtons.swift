import SwiftUI
import Updates

struct UpdateToolbarButton: View {
    let model: AppUpdateModel

    var body: some View {
        if let version = model.availableVersion {
            Button("Update to \(version)", systemImage: "arrow.down.circle") { model.checkForUpdates() }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .help("Update to \(version)…")
                .accessibilityIdentifier("app-update")
        }
    }
}

public struct CheckForUpdatesButton: View {
    private let model: AppUpdateModel

    public init(model: AppUpdateModel) { self.model = model }

    public var body: some View {
        Button("Check for Updates…") { model.checkForUpdates() }
            .disabled(!model.canCheckForUpdates && model.availableVersion == nil)
    }
}
