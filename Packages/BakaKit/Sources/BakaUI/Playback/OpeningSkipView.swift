import SwiftUI

struct OpeningSkipView: View {
    @Bindable var model: OpeningSkipModel
    var body: some View {
        if model.hasMarkers {
            HStack {
                Toggle("Show Skip Opening", isOn: $model.isEnabled)
                    .toggleStyle(.switch).controlSize(.small).fixedSize()
                if model.isEnabled, model.segment != nil {
                    Button("Skip Opening", systemImage: "forward.end.fill") { model.skip() }
                        .buttonStyle(.glassProminent).disabled(!model.canSkip)
                }
                if let error = model.error { Text(error).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}
