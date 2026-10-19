import SwiftUI

struct EpisodeAutoplayView: View {
    @Bindable var model: EpisodeAutoplayModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Auto-play next episode", isOn: $model.isEnabled)
                .toggleStyle(.switch).controlSize(.small)
                .help("After an episode ends, offer the next available episode in this season with an 8-second countdown.")
            if let pending = model.pending {
                HStack {
                    Text("\(pending.destination.label) starts in \(model.remainingSeconds) s")
                        .font(.callout).monospacedDigit()
                        .accessibilityLabel("Next episode \(pending.destination.label) starts in \(model.remainingSeconds) seconds")
                    Button("Play Now", systemImage: "play.fill") { model.playNow() }
                        .buttonStyle(.glassProminent)
                    Button("Cancel") { model.cancel() }.buttonStyle(.glass)
                }
            }
        }
    }
}
