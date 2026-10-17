import Foundation
import SwiftUI

struct DiagnosticsView: View {
    private var operatingSystemVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private var mpvPath: String? {
        ["/opt/homebrew/bin/mpv", "/usr/local/bin/mpv"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private var svpPath: String? {
        ["/Applications/SVP 4 Mac.app", "/Applications/SVP.app"]
            .first { FileManager.default.fileExists(atPath: $0) }
    }

    var body: some View {
        Form {
            Section("Environment") {
                LabeledContent("macOS", value: operatingSystemVersion)
                LabeledContent("mpv", value: mpvPath ?? "Not found in standard Homebrew locations")
                LabeledContent("SVP", value: svpPath ?? "Not found in standard locations")
            }
            Section("Integrations") {
                LabeledContent("ShikimoriSharp", value: "Integration not implemented yet")
                LabeledContent("Kinopub", value: "Integration not implemented yet")
                LabeledContent("JSON bridge", value: "Protocol v1 · handshake")
            }
            Section {
                Text("Finding mpv and SVP does not confirm compatibility or active frame interpolation.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
