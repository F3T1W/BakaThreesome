import Foundation
import Observation
import Playback
import Tracking

@MainActor
@Observable
final class ProgressSyncModel {
    var isEnabled = UserDefaults.standard.bool(forKey: "tracking.automaticProgress") {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "tracking.automaticProgress")
            coverage = WatchedCoverage()
            if isEnabled { retry() }
        }
    }
    private(set) var journal = ProgressJournalSnapshot()
    private(set) var isSyncing = false
    private(set) var isLoaded = false
    private(set) var message: String?
    let shikimori: ShikimoriModel
    @ObservationIgnored private let delivery: ProgressDelivery
    @ObservationIgnored private let store: ProgressJournal
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var context: EpisodeContext?
    @ObservationIgnored private var coverage = WatchedCoverage()
    @ObservationIgnored private var sessionKey: String?
    @ObservationIgnored private var submitted = false
    @ObservationIgnored private var closing = false
    @ObservationIgnored private let clockOrigin = ContinuousClock.now

    init(shikimori: ShikimoriModel, store: ProgressJournal = ProgressJournal()) {
        self.shikimori = shikimori; self.store = store
        delivery = ProgressDelivery(journal: store, client: shikimori)
    }

    var pending: [WatchedEpisode] {
        journal.pending.filter { $0.userID == shikimori.snapshot.profile?.id }
            .sorted { $0.number < $1.number }
    }
    var otherAccountCount: Int { journal.pending.count - pending.count }

    func start() async {
        await refresh()
        guard retryTask == nil, !closing else { return }
        retryTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.retry()
                do { try await Task.sleep(for: .seconds(60)) }
                catch { return }
            }
        }
    }

    func number(for context: EpisodeContext) -> Int? {
        guard let userID = shikimori.snapshot.profile?.id else { return nil }
        return journal.numbering.lazy.compactMap { $0.episode(for: context, userID: userID) }.first
    }

    func confirm(_ context: EpisodeContext, number: Int) async {
        guard let userID = shikimori.snapshot.profile?.id, !isSyncing else { return }
        do {
            try await store.confirm(EpisodeNumbering(userID: userID, context: context, shikimoriEpisode: number))
            coverage = WatchedCoverage(); sessionKey = nil; submitted = false
            await refresh()
            message = "Numbering saved for this title, Kinopub item and season. Future episodes use the same offset."
        } catch { message = "Numbering could not be saved. Check local storage and try again." }
    }

    func begin(_ context: EpisodeContext?) {
        self.context = context
        coverage = WatchedCoverage(); sessionKey = nil; submitted = false
    }

    func capture(_ snapshot: PlaybackSnapshot) async {
        guard isEnabled, isLoaded, let context, let number = number(for: context),
              let userID = shikimori.snapshot.profile?.id else {
            coverage = WatchedCoverage(); sessionKey = nil
            return
        }
        let key = "\(userID):\(context.id):\(number)"
        if key != sessionKey {
            coverage = WatchedCoverage(); submitted = false; sessionKey = key
        }
        let elapsed = clockOrigin.duration(to: .now).components
        coverage.observe(snapshot, at: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
        guard coverage.isComplete, !submitted else { return }
        do {
            try await store.enqueue(WatchedEpisode(userID: userID, context: context, number: number))
            submitted = true
            await refresh()
            message = "Episode \(number) was watched and queued for Shikimori."
            retry()
        } catch { message = "The watched episode could not be queued. The app will retry while playback is active." }
    }

    func retry() {
        guard isEnabled, isLoaded, !closing, syncTask == nil, !pending.isEmpty,
              !shikimori.isBusy, !shikimori.isSaving else { return }
        isSyncing = true
        syncTask = Task {
            defer { isSyncing = false; syncTask = nil }
            let entries = pending
            var waiting: String?
            for entry in entries {
                guard isEnabled, !closing, shikimori.snapshot.profile?.id == entry.userID else { break }
                do {
                    switch try await delivery.deliver(entry, for: entry.userID) {
                    case .advance, .alreadyApplied:
                        await refresh()
                    case .waiting(let reason):
                        waiting = waiting ?? reason
                    }
                } catch {
                    waiting = "Progress is saved locally. Shikimori could not be updated; retry after checking your session or connection."
                    break
                }
            }
            message = waiting ?? (pending.isEmpty ? "Shikimori progress is up to date." : "Automatic progress is paused.")
        }
    }

    func discard(_ entry: WatchedEpisode) async {
        guard !isSyncing else { return }
        do { try await store.remove(id: entry.id); await refresh() }
        catch { message = "The pending update could not be removed. Check local storage." }
    }

    func shutdown() async {
        closing = true
        retryTask?.cancel()
        await retryTask?.value
        await syncTask?.value
    }

    private func refresh() async {
        do { journal = try await store.snapshot(); isLoaded = true }
        catch {
            isLoaded = false
            message = "Automatic progress storage could not be read. Existing data was kept; check local storage."
        }
    }
}
