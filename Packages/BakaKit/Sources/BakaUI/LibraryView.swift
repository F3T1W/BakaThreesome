import Catalog
import SwiftUI
import Tracking

private enum LibrarySection: String, CaseIterable, Identifiable {
    case resume = "Continue Watching"
    case watchlist = "Watchlist"
    case catalog = "Catalog"
    case diagnostics = "Diagnostics"
    case kinopub = "Kinopub"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .resume: "play.circle"
        case .watchlist: "bookmark"
        case .catalog: "square.grid.2x2"
        case .diagnostics: "stethoscope"
        case .kinopub: "globe"
        }
    }
}

public struct LibraryView: View {
    @State private var selection: LibrarySection? = .resume
    @State private var matchingAnime: AnimeSummary?
    @State private var useSavedMatch = true
    private let services: ApplicationServices

    public init(services: ApplicationServices = ApplicationServices()) {
        self.services = services
    }

    public var body: some View {
        NavigationSplitView {
            List(LibrarySection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.symbol)
                    .tag(section)
            }
            .navigationTitle("BakaThreesome")
            .navigationSplitViewColumnWidth(min: 190, ideal: 220)
        } detail: {
            Group {
                switch selection ?? .resume {
                case .resume:
                    ContinueWatchingView(model: services.history,
                                         isPreparingPlayback: services.kinopubBrowser.isWorking || services.kinopubBrowser.isPreparing) { entry, fromBeginning in
                        services.kinopubBrowser.resume(entry, fromBeginning: fromBeginning)
                        selection = .kinopub
                    }
                case .watchlist:
                    AnimeLibraryView(model: services.shikimori, isWatchlist: true, onOpenKinopub: findKinopub).id(LibrarySection.watchlist)
                case .catalog:
                    AnimeLibraryView(model: services.shikimori, isWatchlist: false, onOpenKinopub: findKinopub).id(LibrarySection.catalog)
                case .kinopub:
                    KinopubBrowserView(model: services.kinopubBrowser)
                case .diagnostics:
                    DiagnosticsView(model: services.diagnostics)
                }
            }
            .navigationTitle((selection ?? .resume).rawValue)
            .toolbar {
                ToolbarItem {
                    SettingsLink {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
        }
        .frame(minWidth: 780, minHeight: 520)
        .task { await services.history.refresh(); await services.shikimori.restore() }
        .sheet(item: $matchingAnime) { anime in
            KinopubMatchSheet(anime: anime, client: services.shikimori.client, store: services.episodeMappings,
                              origin: services.kinopubBrowser.websiteOrigin, useSaved: useSavedMatch) { mapping in
                services.kinopubBrowser.openTitle(anime: anime, mapping: mapping)
                selection = .kinopub
            }
        }
    }

    private func findKinopub(_ anime: AnimeSummary, useSaved: Bool) {
        useSavedMatch = useSaved
        matchingAnime = anime
    }

}
