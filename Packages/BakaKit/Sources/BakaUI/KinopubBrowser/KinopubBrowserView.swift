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
                    if model.isWorking { ProgressView().controlSize(.small) }
                    Button("Rescan", systemImage: "magnifyingglass") { model.scan() }
                    Button("Stop mpv", systemImage: "stop.fill") { model.stop() }
                        .disabled(model.isWorking)
                    Button("Clear Session", role: .destructive) { model.clearSession() }
                        .disabled(model.isWorking)
                }
                .buttonStyle(.glass)
                Text(model.svpStatus).font(.caption).foregroundStyle(.secondary)
                Text(model.status).font(.caption).foregroundStyle(.secondary)
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.red)
                }
                if let manifest = model.candidates.first(where: { $0.isPrimaryManifest }) {
                    Button("Play Episode in mpv", systemImage: "play.fill") {
                        model.audioSourceID = nil
                        model.play(manifest)
                    }
                    .buttonStyle(.glassProminent).disabled(model.isWorking)
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
