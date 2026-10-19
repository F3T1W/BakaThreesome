import AppKit
import SwiftUI

struct AnimePosterView: View {
    let animeID: Int64
    let artwork: AnimeArtworkModel
    @State private var image: NSImage?
    @State private var loadedURL: URL?
    @State private var isLoading = false

    var body: some View {
        let url = artwork.url(for: animeID)
        Color.secondary.opacity(0.08)
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay {
                if let image, loadedURL == url {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "photo").font(.largeTitle.weight(.ultraLight))
                        if isLoading { ProgressView().controlSize(.small) }
                        else { Text("No artwork").font(.caption) }
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)
            .task(id: "\(url?.absoluteString ?? "none"):\(artwork.revision)") {
                guard let url else { image = nil; loadedURL = nil; isLoading = false; return }
                guard loadedURL != url || image == nil else { return }
                image = nil; loadedURL = nil; isLoading = true
                defer { if !Task.isCancelled { isLoading = false } }
                do {
                    let result = try await artwork.image(at: url)
                    try Task.checkCancellation()
                    image = result; loadedURL = url
                } catch { }
            }
    }
}

struct AnimeThumbnail<Detail: View>: View {
    let animeID: Int64
    let title: String
    let artwork: AnimeArtworkModel
    @ViewBuilder let detail: () -> Detail

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AnimePosterView(animeID: animeID, artwork: artwork)
            Text(title)
                .font(.headline)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(title)
            detail()
        }
        .contentShape(Rectangle())
    }
}

struct AnimeGrid<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 22, alignment: .top)],
                      alignment: .leading, spacing: 26, content: content)
                .padding(20)
        }
    }
}

struct ArtworkNotice: View {
    let artwork: AnimeArtworkModel
    let animeIDs: [Int64]
    var body: some View {
        if let error = artwork.errorMessage {
            HStack {
                Label(error, systemImage: "photo.badge.exclamationmark")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Reload Posters") { Task { await artwork.load(animeIDs, force: true) } }
                    .buttonStyle(.glass).controlSize(.small)
            }
            .padding(.horizontal).padding(.vertical, 8)
        }
    }
}
