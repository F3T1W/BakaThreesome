import SwiftUI

struct ShikimoriAccountSection: View {
    @Bindable var model: ShikimoriModel

    var body: some View {
        Section("Shikimori") {
            LabeledContent("Account", value: accountLabel)
            if model.isBusy || model.isRestoring { ProgressView().controlSize(.small) }
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
            } else if model.restorationError != nil {
                Text("The saved session could not be read. Retry before connecting another account.")
                    .foregroundStyle(.secondary)
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
            if model.restorationError != nil {
                Button("Retry Restoring Session") { Task { await model.restore() } }
                    .buttonStyle(.glass)
            }
            if let error = model.restorationError ?? model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red).textSelection(.enabled)
                if !model.snapshot.isSignedIn {
                    Button("Forget Saved Session", role: .destructive) { model.signOut() }
                }
            }
        }
        .disabled(model.isBusy || model.isRestoring || model.isSaving)
    }

    private var accountLabel: String {
        if model.isRestoring { return "Restoring session…" }
        if model.restorationError != nil { return "Session unavailable" }
        return model.snapshot.profile?.nickname ?? (model.snapshot.isSignedIn ? "Connected" : "Not connected")
    }
}
