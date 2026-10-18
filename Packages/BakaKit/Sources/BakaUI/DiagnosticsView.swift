import SwiftUI

struct DiagnosticsView: View {
    let model: DiagnosticsModel
    @State private var checkID = UUID()

    var body: some View {
        Form {
            Section("Environment") {
                LabeledContent("macOS", value: model.operatingSystemVersion)
                LabeledContent("mpv", value: model.environment.mpvURL?.path ?? "Not found in standard Homebrew locations")
                LabeledContent("SVP", value: model.environment.svpURL?.path ?? "Not found in standard locations")
            }
            Section("Player compatibility") {
                LabeledContent("Version", value: model.capabilities?.version ?? "Not checked")
                LabeledContent("VapourSynth", value: vapourSynthStatus)
                LabeledContent("Process and JSON IPC", value: model.ipcPassed ? "Verified" : "Not verified")
                HStack {
                    Button("Check Player", systemImage: "arrow.clockwise") {
                        checkID = UUID()
                    }
                    .buttonStyle(.glass)
                    .disabled(model.isChecking)
                    if model.isChecking {
                        ProgressView()
                            .controlSize(.small)
                        Text("Checking mpv…")
                            .foregroundStyle(.secondary)
                    }
                }
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
            Section("SVP") {
                LabeledContent("Frame interpolation", value: "Not verified")
                Text("The player check uses no media and a private IPC socket. SVP interpolation must be verified separately during video playback.")
                    .foregroundStyle(.secondary)
            }
            Section("Integrations") {
                LabeledContent("ShikimoriSharp", value: "Catalog and manual tracking connected")
                LabeledContent("Kinopub browser", value: "Website sign-in prototype")
                LabeledContent("JSON bridge", value: "Protocol v1 · catalog, accounts, tracking")
            }
        }
        .formStyle(.grouped)
        .task(id: checkID) {
            await model.refresh()
        }
    }

    private var vapourSynthStatus: String {
        guard let capabilities = model.capabilities else { return "Not checked" }
        return capabilities.hasVapourSynth ? "Available in this mpv build" : "Missing from this mpv build"
    }
}
