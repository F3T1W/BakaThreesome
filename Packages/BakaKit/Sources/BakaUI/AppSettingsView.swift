import Accounts
import SwiftUI

public struct AppSettingsView: View {
    public init() {}

    public var body: some View {
        TabView {
            Tab("Accounts", systemImage: "person.crop.circle") {
                Form {
                    Section("Services") {
                        ForEach(ServiceAccount.allCases, id: \.self) { service in
                            LabeledContent(service.displayName, value: "Not connected")
                        }
                    }
                    Text("Sign-in will be available after the integrations have been verified.")
                        .foregroundStyle(.secondary)
                }
                .formStyle(.grouped)
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
        .frame(width: 560, height: 340)
    }
}
