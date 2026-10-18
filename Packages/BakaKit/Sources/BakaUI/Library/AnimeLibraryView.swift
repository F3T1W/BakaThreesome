import Catalog
import ShikimoriBridge
import SwiftUI
import Tracking

struct AnimeLibraryView: View {
    let model: ShikimoriModel
    let isWatchlist: Bool
    @State private var query = ""
    @State private var submittedQuery = ""
    @State private var status: WatchStatus? = .watching
    @State private var page = 1
    @State private var reload = UUID()
    @State private var entries: [AnimeListEntry] = []
    @State private var results: [AnimeSummary] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedAnime: AnimeSummary?

    private var requestKey: String {
        "\(isWatchlist)-\(model.snapshot.isSignedIn)-\(submittedQuery)-\(status?.rawValue ?? "all")-\(page)-\(model.revision)-\(reload)"
    }
    private var count: Int { isWatchlist ? entries.count : results.count }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if isWatchlist {
                    Picker("List", selection: $status) {
                        Text("All Lists").tag(Optional<WatchStatus>.none)
                        ForEach(WatchStatus.allCases) { Text($0.title).tag(Optional($0)) }
                    }
                    .frame(maxWidth: 250)
                } else {
                    TextField("Search anime", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { search() }
                    Button("Search", systemImage: "magnifyingglass") { search() }
                        .buttonStyle(.glass)
                }
                Spacer()
                Button("Reload", systemImage: "arrow.clockwise") { reload = UUID() }
                    .labelStyle(.iconOnly).buttonStyle(.glass)
                    .disabled(isLoading)
            }
            .padding()
            Divider()
            if isWatchlist && !model.snapshot.isSignedIn {
                ContentUnavailableView {
                    Label("Connect Shikimori", systemImage: "person.crop.circle")
                } description: {
                    Text("Connect your account in Settings to view lists, track episodes, and rate anime.")
                } actions: {
                    SettingsLink { Text("Open Settings") }.buttonStyle(.glassProminent)
                }
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Could Not Load Anime", systemImage: "exclamationmark.triangle")
                } description: { Text(errorMessage) } actions: {
                    Button("Try Again") { reload = UUID() }.buttonStyle(.glass)
                }
            } else if isLoading && count == 0 {
                Spacer()
                ProgressView("Loading anime…")
                Spacer()
            } else if count == 0 {
                ContentUnavailableView(isWatchlist ? "No Anime in This List" : "No Results",
                                       systemImage: isWatchlist ? "bookmark" : "magnifyingglass",
                                       description: Text(isWatchlist ? "Find anime in Catalog and add it to your list." : "Try a different title."))
            } else {
                List {
                    if isWatchlist {
                        ForEach(entries) { entry in
                            animeRow(entry.anime, rate: entry.rate)
                        }
                    } else {
                        ForEach(results) { anime in animeRow(anime, rate: nil) }
                    }
                }
                .listStyle(.inset)
                .disabled(isLoading)
                .overlay(alignment: .topTrailing) {
                    if isLoading { ProgressView().controlSize(.small).padding() }
                }
            }
            if !isWatchlist || model.snapshot.isSignedIn {
                Divider()
                HStack {
                    Button("Previous", systemImage: "chevron.left") { page -= 1 }
                        .disabled(page == 1 || isLoading)
                    Spacer()
                    Text("Page \(page)").foregroundStyle(.secondary)
                    Spacer()
                    Button("Next", systemImage: "chevron.right") { page += 1 }
                        .disabled(count < (isWatchlist ? 50 : 30) || isLoading || page >= 1000)
                }
                .buttonStyle(.glass).padding()
            }
        }
        .task(id: requestKey) { await load() }
        .onChange(of: status) { page = 1 }
        .onChange(of: model.revision) { page = 1 }
        .sheet(item: $selectedAnime) { anime in
            AnimeTrackingSheet(anime: anime, model: model)
        }
    }

    private func animeRow(_ anime: AnimeSummary, rate: AnimeUserRate?) -> some View {
        Button { selectedAnime = anime } label: {
            HStack(spacing: 16) {
                Image(systemName: "tv").font(.title2).foregroundStyle(.secondary)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 5) {
                    Text(anime.title).font(.headline)
                    HStack {
                        Text(anime.kind.uppercased())
                        Text(anime.episodes > 0 ? "\(anime.episodes) episodes" : "Episode count unknown")
                        if let score = anime.communityScore {
                            Text("★ \(score, specifier: "%.2f")")
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let rate {
                    VStack(alignment: .trailing, spacing: 5) {
                        Text(rate.status.title)
                        Text("\(rate.episodes) watched · \(rate.score == 0 ? "Unrated" : "\(rate.score)/10")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(.vertical, 6).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func search() {
        submittedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        page = 1
        reload = UUID()
    }

    @MainActor
    private func load() async {
        let key = requestKey
        isLoading = true
        errorMessage = nil
        entries = []; results = []
        defer { if requestKey == key { isLoading = false } }
        guard !isWatchlist || model.snapshot.isSignedIn else { return }
        do {
            if isWatchlist {
                let value = try await model.list(status: status, page: page)
                try Task.checkCancellation()
                guard requestKey == key else { return }
                entries = value
            } else {
                let value = try await model.client.search(submittedQuery, page: page)
                try Task.checkCancellation()
                guard requestKey == key else { return }
                results = value
            }
        } catch is CancellationError {
        } catch {
            if !Task.isCancelled && requestKey == key { errorMessage = error.localizedDescription }
        }
    }
}
