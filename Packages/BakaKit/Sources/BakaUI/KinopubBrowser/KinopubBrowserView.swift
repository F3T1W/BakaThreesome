import SwiftUI
import WebKit

struct KinopubBrowserView: View {
    @Bindable var model: KinopubBrowserModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Back", systemImage: "chevron.left") { model.webView.goBack() }
                    .labelStyle(.iconOnly)
                TextField("Kinopub website address", text: $model.address)
                    .textFieldStyle(.roundedBorder).onSubmit { model.navigate() }
                Button("Open") { model.navigate() }
                Button("Reload", systemImage: "arrow.clockwise") { model.webView.reload() }
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.glass).padding()
            Divider()
            KinopubWebView(webView: model.webView)
                .frame(minHeight: 220)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Media Sources").font(.headline)
                    Spacer()
                    Toggle("SVP", isOn: $model.useSVP)
                        .toggleStyle(.switch).controlSize(.small)
                        .fixedSize().disabled(model.isWorking)
                        .help("Applies when starting the next playback session.")
                    if model.isWorking || model.isPreparing { ProgressView().controlSize(.small) }
                    Button("Rescan", systemImage: "magnifyingglass") { model.scan() }
                    Button(model.isWorking || model.isPreparing ? "Cancel Playback" : "Stop mpv", systemImage: "stop.fill") { model.stop() }
                    Button("Clear Session", role: .destructive) { model.clearSession() }
                        .disabled(model.isWorking)
                }
                .buttonStyle(.glass)
                if !model.episodeChoices.isEmpty {
                    Picker("Episode", selection: Binding(get: { model.currentEpisodeNumber }, set: { model.chooseEpisode($0) })) {
                        Text("Choose an episode").tag(0)
                        ForEach(model.episodeChoices) { choice in
                            Text("Episode \(choice.destination.episode)" + (choice.title.isEmpty ? "" : " · \(choice.title)"))
                                .tag(choice.destination.episode)
                        }
                    }
                    .frame(maxWidth: 500).disabled(model.isWorking)
                }
                if let episode = model.currentEpisode {
                    Text("\(episode.title) · \(episode.label) · Local playback progress enabled")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Open this title from Watchlist or Catalog and select its linked season to save episode progress.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !model.playerStatus.isEmpty { Text(model.playerStatus).font(.caption).foregroundStyle(.secondary) }
                if let error = model.progressError {
                    Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
                Text(model.svpStatus).font(.caption).foregroundStyle(.secondary)
                Text(model.status).font(.caption).foregroundStyle(.secondary)
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.red)
                }
                if model.primaryManifest != nil {
                    HStack {
                        Button(model.savedEpisode.map { "Resume in mpv · " + PlaybackTimeText.format($0.position.seconds) }
                               ?? "Play Episode in mpv", systemImage: "play.fill") { model.playEpisode() }
                            .buttonStyle(.glassProminent)
                        if model.savedEpisode != nil {
                            Button("Play from Beginning") { model.playEpisode(fromBeginning: true) }.buttonStyle(.glass)
                        }
                    }
                    .disabled(model.isWorking)
                }
                if !model.candidates.isEmpty {
                    Picker("External audio", selection: $model.audioSourceID) {
                        Text("Use audio from the selected video").tag(Optional<UUID>.none)
                        ForEach(Array(model.candidates.enumerated()), id: \.element.id) { index, candidate in
                            Text("\(index + 1). \(candidate.displayName)").tag(Optional(candidate.id))
                        }
                    }
                    .disabled(model.isWorking)
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(Array(model.candidates.enumerated()), id: \.element.id) { index, candidate in
                                HStack {
                                    Text("\(index + 1). \(candidate.displayName)").lineLimit(1)
                                    Spacer()
                                    Button("Play in mpv", systemImage: "play.fill") { model.play(candidate) }
                                        .buttonStyle(.glassProminent).disabled(model.isWorking)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 110)
                }
            }
            .padding()
        }
        .task { model.loadIfNeeded() }
    }
}

private struct KinopubWebView: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
