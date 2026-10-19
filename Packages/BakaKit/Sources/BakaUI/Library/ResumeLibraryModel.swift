import Foundation
import Observation
import Tracking

@MainActor
@Observable
final class ResumeLibraryModel {
    let store: any ResumeHistoryStore
    private(set) var entries: [ResumeEntry] = []
    private(set) var errorMessage: String?
    var activeEpisodeID: String?
    private var revision = 0

    init(store: any ResumeHistoryStore = SwiftDataResumeStore()) { self.store = store }

    func refresh() async {
        revision += 1
        let current = revision
        do {
            let values = try await store.entries()
            guard revision == current else { return }
            entries = values
            errorMessage = nil
        } catch {
            guard revision == current else { return }
            errorMessage = "Saved playback progress could not be read. Check local storage and try again."
        }
    }

    func remove(_ entry: ResumeEntry) async {
        guard activeEpisodeID != entry.id else { return }
        do { try await store.remove(id: entry.id); await refresh() }
        catch { errorMessage = "This saved episode could not be removed. Try again." }
    }

    func entry(for context: EpisodeContext?) -> ResumeEntry? {
        guard let context else { return nil }
        return entries.first { $0.id == context.id }
    }
}
