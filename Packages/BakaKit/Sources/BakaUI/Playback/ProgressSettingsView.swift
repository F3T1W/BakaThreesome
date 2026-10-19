import SwiftUI
import Tracking

struct ProgressSettingsView: View {
    @Bindable var model: ProgressSyncModel
    var body: some View {
        Form {
            Section("Shikimori progress") {
                Toggle("Automatically sync watched episodes", isOn: $model.isEnabled)
                Text("Watch at least 90% of an episode across playback sessions. Watched segments are saved locally for this account and confirmed episode mapping. Seeking and replaying the same scenes do not count. Confirm episode numbering in Kinopub before playback.")
                    .foregroundStyle(.secondary)
                Text("Only the next episode of a title in Watching is updated. Ratings and list statuses stay as you set them. Rewatching is managed manually.")
                    .foregroundStyle(.secondary)
                if model.shikimori.snapshot.profile == nil {
                    Text("Connect Shikimori in Accounts to use automatic progress.").foregroundStyle(.secondary)
                }
                if let message = model.message { Text(message).font(.callout).foregroundStyle(.secondary) }
            }
            Section("Pending updates · \(model.pending.count)") {
                HStack {
                    Button("Retry Now") { model.retry() }
                        .buttonStyle(.glass)
                        .disabled(!model.isEnabled || model.isSyncing || model.pending.isEmpty)
                    if model.isSyncing { ProgressView().controlSize(.small) }
                }
                ForEach(model.pending) { entry in
                    HStack {
                        Text("\(entry.context.title) · Shikimori episode \(entry.number)")
                        Spacer()
                        Button("Discard", role: .destructive) { Task { await model.discard(entry) } }
                            .disabled(model.isSyncing)
                    }
                }
                if model.otherAccountCount > 0 {
                    Text("\(model.otherAccountCount) pending updates belong to another account and will wait for that account to sign in.")
                        .foregroundStyle(.secondary)
                }
                Text("Updates retry every minute while the app is open and automatic sync is enabled. Discard an update before correcting a mistaken episode association.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await model.start() }
    }
}

struct EpisodeNumberingView: View {
    let model: ProgressSyncModel
    let context: EpisodeContext
    @State private var number = 1
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let confirmed = model.number(for: context) {
                Text("Shikimori episode \(confirmed) · Numbering confirmed")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Stepper("Shikimori episode", value: $number, in: 1...100000)
                    .fixedSize()
                TextField("Episode number", value: $number, format: .number.grouping(.never))
                    .frame(width: 65)
                Button("Confirm Numbering") {
                    isSaving = true
                    Task { await model.confirm(context, number: number); isSaving = false }
                }
                .buttonStyle(.glass)
                .disabled(isSaving || model.isSyncing || !(1...100000).contains(number))
                Spacer()
            }
            Text("Map this Kinopub episode to its Shikimori number. The same offset applies to this linked season; watch the next episode in Watching to sync it.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { number = model.number(for: context) ?? context.episode }
    }
}
