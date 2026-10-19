import SwiftUI
import Tracking

struct ContinueWatchingView: View {
    let model: ResumeLibraryModel
    let isPreparingPlayback: Bool
    let onResume: (ResumeEntry, Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Saved episode positions stay on this Mac.").foregroundStyle(.secondary)
                Spacer()
                Button("Reload", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                    .labelStyle(.iconOnly).buttonStyle(.glass)
            }
            .padding()
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).padding()
            }
            if model.entries.isEmpty {
                ContentUnavailableView("Nothing to Continue", systemImage: "play.circle", description:
                    Text("Open a title from Watchlist or Catalog, choose an episode, and play it in mpv. Its position will be saved here."))
            } else {
                List(model.entries) { entry in
                    HStack(spacing: 20) {
                        Image(systemName: "play.rectangle").font(.title2).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(entry.context.title).font(.headline)
                            Text("\(entry.context.label) · \(PlaybackTimeText.format(entry.position.seconds)) / \(PlaybackTimeText.format(entry.position.duration ?? 0))")
                                .font(.caption).foregroundStyle(.secondary)
                            ProgressView(value: min(entry.position.seconds / (entry.position.duration ?? 1), 1))
                                .frame(maxWidth: 360)
                        }
                        Spacer()
                        if model.activeEpisodeID == entry.id {
                            Label("Playing", systemImage: "play.fill").foregroundStyle(.secondary)
                        } else {
                            Button("Continue", systemImage: "play.fill") { onResume(entry, false) }
                                .buttonStyle(.glassProminent).disabled(isPreparingPlayback)
                        }
                    }
                    .padding(.vertical, 8)
                    .contextMenu {
                        Button("Continue") { onResume(entry, false) }.disabled(model.activeEpisodeID == entry.id || isPreparingPlayback)
                        Button("Play from Beginning") { onResume(entry, true) }.disabled(isPreparingPlayback)
                        Button("Remove from Continue Watching", role: .destructive) { Task { await model.remove(entry) } }
                            .disabled(model.activeEpisodeID == entry.id)
                    }
                }
                .listStyle(.inset)
            }
        }
        .task { await model.refresh() }
    }
}
