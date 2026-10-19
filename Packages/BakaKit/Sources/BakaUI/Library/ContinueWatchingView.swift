import SwiftUI
import Tracking

struct ContinueWatchingView: View {
    let model: ResumeLibraryModel
    let artwork: AnimeArtworkModel
    let isPreparingPlayback: Bool
    let onResume: (ResumeEntry, Bool) -> Void

    private var animeIDs: [Int64] { model.entries.map { $0.context.animeID.rawValue } }

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
                AnimeGrid {
                    ForEach(model.entries) { entry in
                        VStack(alignment: .leading, spacing: 10) {
                            Button { onResume(entry, false) } label: {
                                AnimeThumbnail(animeID: entry.context.animeID.rawValue,
                                               title: entry.context.title, artwork: artwork) {
                                    Text("\(entry.context.label) · \(PlaybackTimeText.format(entry.position.seconds)) / \(PlaybackTimeText.format(entry.position.duration ?? 0))")
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Continue \(entry.context.title), \(entry.context.label)")
                            .disabled(model.activeEpisodeID == entry.id || isPreparingPlayback)
                            ProgressView(value: min(entry.position.seconds / (entry.position.duration ?? 1), 1))
                                .accessibilityLabel("Episode progress")
                            if model.activeEpisodeID == entry.id {
                                Label("Playing", systemImage: "play.fill").font(.callout).foregroundStyle(.secondary)
                            } else {
                                Button("Continue", systemImage: "play.fill") { onResume(entry, false) }
                                    .buttonStyle(.glassProminent).disabled(isPreparingPlayback)
                            }
                        }
                        .contextMenu {
                            Button("Reload Poster") { Task { await artwork.load([entry.context.animeID.rawValue], force: true) } }
                            Button("Continue") { onResume(entry, false) }.disabled(model.activeEpisodeID == entry.id || isPreparingPlayback)
                            Button("Play from Beginning") { onResume(entry, true) }.disabled(isPreparingPlayback)
                            Button("Remove from Continue Watching", role: .destructive) { Task { await model.remove(entry) } }
                                .disabled(model.activeEpisodeID == entry.id)
                        }
                    }
                }
                ArtworkNotice(artwork: artwork, animeIDs: animeIDs)
            }
        }
        .task { await model.refresh() }
        .task(id: animeIDs) { await artwork.load(animeIDs) }
    }
}
