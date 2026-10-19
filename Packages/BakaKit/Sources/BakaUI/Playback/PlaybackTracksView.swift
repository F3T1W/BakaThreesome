import Playback
import SwiftUI

struct PlaybackTracksView: View {
    let model: PlaybackTrackModel

    var body: some View {
        if model.isConnected {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    trackPicker("Audio", kind: .audio)
                    trackPicker("Subtitles", kind: .subtitle)
                    if model.isChanging { ProgressView().controlSize(.small) }
                    Button("Japanese + Russian", systemImage: "arrow.counterclockwise") {
                        model.restoreDefaults()
                    }
                    .labelStyle(.iconOnly)
                    .help("Prefer Japanese audio and Russian subtitles")
                }
                .disabled(model.isChanging)
                if let error = model.error {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func trackPicker(_ label: String, kind: PlaybackTrackKind) -> some View {
        Picker(label, selection: Binding(get: { model.selected(kind) }, set: { model.select($0, kind: kind) })) {
            Text("Off").tag(0)
            ForEach(model.available.filter { $0.kind == kind }) { track in
                let duplicates = model.available.filter { $0.kind == kind && $0.label == track.label }.count > 1
                Text(track.label + (duplicates ? " · Track \(track.id)" : "")).tag(track.id)
            }
        }
        .frame(maxWidth: 360)
    }
}
