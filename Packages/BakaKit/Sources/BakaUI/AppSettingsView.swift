import SwiftUI

public struct AppSettingsView: View {
    private let services: ApplicationServices

    public init(services: ApplicationServices) {
        self.services = services
    }

    public var body: some View {
        TabView {
            Tab("Accounts", systemImage: "person.crop.circle") {
                AccountsView(shikimori: services.shikimori)
            }

            Tab("Progress", systemImage: "checkmark.circle") {
                ProgressSettingsView(model: services.progress)
            }

            Tab("About", systemImage: "info.circle") {
                VStack(spacing: 16) {
                    Text("BakaThreesome")
                        .font(.title2.bold())
                    Text("A native anime streaming client")
                        .foregroundStyle(.secondary)
                    HStack(spacing: 0) {
                        Text("Shikimori integration is based on ")
                        Link(
                            "ShikimoriSharp · JustRoxy",
                            destination: URL(string: "https://github.com/JustRoxy/ShikimoriSharp")!
                        )
                    }
                }
                .padding(32)
            }
        }
        .frame(width: 640, height: 500)
    }
}
