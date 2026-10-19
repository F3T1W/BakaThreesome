import Catalog
import ShikimoriBridge
import SwiftUI
import Tracking

struct AnimeTrackingSheet: View {
    let anime: AnimeSummary
    let model: ShikimoriModel
    @Environment(\.dismiss) private var dismiss
    @State private var status: WatchStatus = .planned
    @State private var episodes = 0
    @State private var score = 0
    @State private var rateID: Int64?
    @State private var loaded = false
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(anime.title).font(.title2.bold()).textSelection(.enabled)
            if model.snapshot.isSignedIn {
                if isLoading { ProgressView("Loading your progress…") }
                if loaded {
                    Form {
                        Picker("List", selection: $status) {
                            ForEach(WatchStatus.allCases) { Text($0.title).tag($0) }
                        }
                        Stepper(value: $episodes, in: 0...max(anime.episodes, episodes, 10000)) {
                            HStack {
                                Text("Watched episodes")
                                TextField("Episodes", value: $episodes, format: .number.grouping(.never))
                                    .multilineTextAlignment(.trailing).frame(width: 90)
                            }
                        }
                        Picker("Your rating", selection: $score) {
                            Text("Unrated").tag(0)
                            ForEach(1...10, id: \.self) { Text("\($0)/10").tag($0) }
                        }
                    }
                    .disabled(isSaving)
                }
            } else {
                Text("Connect Shikimori in Settings to add this anime to your lists and track progress.")
                    .foregroundStyle(.secondary)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red).textSelection(.enabled)
                if !loaded && !isLoading {
                    Button("Reload Progress") { Task { await load() } }
                }
            }
            HStack {
                Button("Close", role: .cancel) { dismiss() }.disabled(isSaving)
                Spacer()
                if model.snapshot.isSignedIn {
                    Button(rateID == nil ? "Add to List" : "Save Changes") { Task { await save() } }
                        .buttonStyle(.glassProminent)
                        .disabled(!loaded || isSaving || model.isBusy || model.isSaving || episodes < 0 || episodes > 100000)
                } else {
                    SettingsLink { Text("Open Settings") }.buttonStyle(.glass)
                }
            }
        }
        .padding(24).frame(width: 480)
        .interactiveDismissDisabled(isSaving)
        .task(id: model.snapshot.isSignedIn) { await load() }
    }

    @MainActor
    private func load() async {
        loaded = false
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        guard model.snapshot.isSignedIn else { return }
        do {
            let detail = try await model.details(anime.id)
            try Task.checkCancellation()
            rateID = detail.rate?.id
            status = detail.rate?.status ?? .planned
            episodes = detail.rate?.episodes ?? 0
            score = detail.rate?.score ?? 0
            loaded = true
        } catch is CancellationError {
        } catch { if !Task.isCancelled { errorMessage = error.localizedDescription } }
    }

    @MainActor
    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            _ = try await model.save(animeID: anime.id, rateID: rateID, status: status, episodes: episodes, score: score)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            // A timed-out write may have reached Shikimori. Reload before another attempt.
            loaded = false
        }
    }
}
