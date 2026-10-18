import SwiftUI

struct ShikimoriAccountSection: View {
    @Bindable var model: ShikimoriModel

    var body: some View {
        Section("Shikimori") {
            LabeledContent("Account", value: model.snapshot.profile?.nickname
                           ?? (model.snapshot.isSignedIn ? "Connected" : "Not connected"))
            if model.isBusy { ProgressView().controlSize(.small) }
            if model.snapshot.isSignedIn {
                HStack {
                    Button("Check Session") { model.retrySession() }
                        .buttonStyle(.glass)
                    Button("Sign Out", role: .destructive) { model.signOut() }
                }
                if !model.snapshot.isPersisted {
                    Text("The session is only in memory. Check Session retries saving it to Keychain.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Register an application named BakaThreesome with the user_rates scope and the redirect URI below.")
                    .foregroundStyle(.secondary)
                Text("urn:ietf:wg:oauth:2.0:oob")
                    .font(.caption.monospaced()).textSelection(.enabled)
                Link("Register Application", destination: URL(string: "https://shikimori.io/oauth/applications")!)
                TextField("Client ID", text: $model.clientID).autocorrectionDisabled()
                SecureField("Client secret", text: $model.clientSecret)
                if let credentials = model.credentials {
                    Link("Authorize in Browser", destination: credentials.authorizationURL)
                        .buttonStyle(.glass)
                    SecureField("Authorization code from Shikimori", text: $model.authorizationCode)
                    Button("Connect Shikimori") { model.signIn() }
                        .buttonStyle(.glassProminent)
                        .disabled(model.authorizationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Text("Credentials and tokens are stored in macOS Keychain. Sign Out removes the local session; revoke access on Shikimori separately if needed.")
                    .foregroundStyle(.secondary)
            }
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red).textSelection(.enabled)
                if !model.snapshot.isSignedIn {
                    Button("Forget Saved Session", role: .destructive) { model.signOut() }
                }
            }
        }
        .disabled(model.isBusy || model.isSaving)
    }
}
