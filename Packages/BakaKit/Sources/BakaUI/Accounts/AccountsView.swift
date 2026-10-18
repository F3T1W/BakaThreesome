import SwiftUI

struct AccountsView: View {
    @Bindable var shikimori: ShikimoriModel

    var body: some View {
        Form {
            ShikimoriAccountSection(model: shikimori)
            Section("Kinopub") {
                Text("Open Kinopub in the main sidebar and sign in directly on the website. Your browser session is saved separately from Shikimori.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await shikimori.restore() }
    }
}
