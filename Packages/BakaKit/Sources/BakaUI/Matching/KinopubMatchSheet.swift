import Catalog
import Kinopub
import Matching
import ShikimoriBridge
import SwiftUI

struct KinopubMatchSheet: View {
    @State private var model: KinopubMatchModel
    @State private var operation: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss
    private let useSaved: Bool
    private let onOpen: (EpisodeMapping) -> Void

    init(anime: AnimeSummary, client: ShikimoriClient, store: EpisodeMappingStore,
         origin: URL, useSaved: Bool, onOpen: @escaping (EpisodeMapping) -> Void) {
        _model = State(initialValue: KinopubMatchModel(anime: anime, client: client, store: store, origin: origin))
        self.useSaved = useSaved
        self.onOpen = onOpen
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Open in Kinopub").font(.title2.bold())
            Text(model.anime.title).font(.headline).textSelection(.enabled)
            if let identity = model.identity {
                Text("\(identity.year.map(String.init) ?? "Year unknown") · \(identity.kind.uppercased())")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if model.isWorking { ProgressView("Finding the matching title…") }
            if let selected = model.selected {
                Text(selected.title).font(.headline)
                if let year = selected.year { Text("Kinopub release year: \(String(year))").foregroundStyle(.secondary) }
                matchEvidence(for: selected)
                Text("Confirm that this is the same anime and select its season.").foregroundStyle(.secondary)
                Picker("Destination", selection: $model.season) {
                    Text("Title page").tag(0)
                    ForEach(selected.seasons, id: \.self) { Text("Season \($0)").tag($0) }
                }
                HStack {
                    Button("Back to Results") { model.clearSelection() }
                    Spacer()
                    Button("Save Match and Open", systemImage: "arrow.up.right") {
                        run { if let match = await model.confirm() { open(match) } }
                    }
                    .buttonStyle(.glassProminent)
                }
                .disabled(model.isWorking)
            } else if let result = model.result {
                DisclosureGroup("Searched titles · \(result.queries.count)") {
                    Text(result.queries.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                if !result.isComplete {
                    Label("Search results are incomplete. Open the website to inspect additional results.",
                          systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                }
                if result.candidates.isEmpty {
                    Text("No confirmed match found on Kinopub.").foregroundStyle(.secondary)
                } else {
                    Text("Choose the correct title. Different seasons or films may share a name.")
                        .foregroundStyle(.secondary)
                    List(result.candidates) { item in
                        Button {
                            run { await model.select(item) }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).font(.headline)
                                Text(item.titles.dropFirst().joined(separator: " · ")).font(.caption).lineLimit(2)
                                Text(item.year.map(String.init) ?? "Year unknown").font(.caption).foregroundStyle(.secondary)
                                matchEvidence(for: item)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(minHeight: 120, maxHeight: 220).disabled(model.isWorking)
                }
                DisclosureGroup("Alternative title or manual match") {
                    VStack(alignment: .leading, spacing: 10) {
                        Link("Find Alternative Titles on Google", destination: model.googleURL)
                        HStack {
                            TextField("Alternative title", text: $model.alternativeTitle)
                                .textFieldStyle(.roundedBorder)
                            Button("Search Again") { run { if let match = await model.find(useSaved: false, allowAutomatic: useSaved) { open(match) } } }
                        }
                        HStack {
                            TextField("Kinopub title URL", text: $model.manualAddress).textFieldStyle(.roundedBorder)
                            Button("Choose Page") { run { await model.selectManualAddress() } }
                        }
                        Text("A missing match does not prove that the title is absent from the catalog.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.top, 8).disabled(model.isWorking)
                }
            }
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).textSelection(.enabled)
            }
            HStack {
                Button("Close", role: .cancel) { operation?.cancel(); dismiss() }
                Spacer()
                if !model.isWorking {
                    Button("Retry Search") { run { if let match = await model.find(useSaved: false, allowAutomatic: useSaved) { open(match) } } }
                }
            }
            .buttonStyle(.glass)
        }
        .padding(24).frame(width: 580)
        .task {
            if let match = await model.find(useSaved: useSaved, allowAutomatic: useSaved) { open(match) }
        }
        .onDisappear { operation?.cancel(); model.close() }
    }

    private func matchEvidence(for item: KinopubTitle) -> some View {
        let assessment = model.assessment(for: item)
        return VStack(alignment: .leading, spacing: 4) {
            if !assessment.reasons.isEmpty {
                Text(assessment.reasons.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
            if !assessment.warnings.isEmpty {
                Label(assessment.warnings.joined(separator: " · "), systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).lineLimit(3)
                    .help(assessment.warnings.joined(separator: "\n"))
            }
        }
    }

    private func run(_ action: @escaping @MainActor () async -> Void) {
        guard operation == nil else { return }
        operation = Task {
            await action()
            operation = nil
        }
    }

    private func open(_ match: EpisodeMapping) {
        guard !Task.isCancelled else { return }
        onOpen(match)
        dismiss()
    }
}
