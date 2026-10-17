import SwiftUI

private enum LibrarySection: String, CaseIterable, Identifiable {
    case resume = "Continue Watching"
    case watchlist = "Watchlist"
    case catalog = "Catalog"
    case diagnostics = "Diagnostics"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .resume: "play.circle"
        case .watchlist: "bookmark"
        case .catalog: "square.grid.2x2"
        case .diagnostics: "stethoscope"
        }
    }
}

public struct LibraryView: View {
    @State private var selection: LibrarySection? = .resume

    public init() {}

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
                    ContentUnavailableView(
                        "Continue Watching",
                        systemImage: "play.circle",
                        description: Text("Episodes you have started watching will appear here.")
                    )
                case .watchlist:
                    accountRequiredView(
                        title: "Watchlist", symbol: "bookmark",
                        message: "Shikimori watchlist integration is planned for a future update."
                    )
                case .catalog:
                    accountRequiredView(
                        title: "Catalog", symbol: "square.grid.2x2",
                        message: "Search will be available after ShikimoriSharp is connected."
                    )
                case .diagnostics:
                    DiagnosticsView()
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
    }

    private func accountRequiredView(title: String, symbol: String, message: String) -> some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(message))
    }
}
