import Foundation
import Observation
import Playback
import Tracking

@MainActor
@Observable
final class ProgressSyncModel {
    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: "tracking.automaticProgress")
            coverage.interrupt()
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
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let coverageStore: WatchedCoverageStore
    @ObservationIgnored private var coverageEpisode: WatchedEpisode?
    @ObservationIgnored private var savedCoverage: WatchedCoverageState?
    @ObservationIgnored private var coverageCheckpoint = ContinuousClock.now
    @ObservationIgnored private var coverageRevision = UUID()
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var context: EpisodeContext?
    @ObservationIgnored private var coverage = WatchedCoverage()
    @ObservationIgnored private var sessionKey: String?
    @ObservationIgnored private var submitted = false
    @ObservationIgnored private var closing = false
    @ObservationIgnored private let clockOrigin = ContinuousClock.now

    init(shikimori: ShikimoriModel, store: ProgressJournal = ProgressJournal(),
         coverageStore: WatchedCoverageStore = WatchedCoverageStore(), defaults: UserDefaults = .standard) {
        self.shikimori = shikimori; self.store = store; self.coverageStore = coverageStore
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: "tracking.automaticProgress")
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
            await checkpointCoverage(force: true)
            try await store.confirm(EpisodeNumbering(userID: userID, context: context, shikimoriEpisode: number))
            resetCoverage()
            await refresh()
            message = "Numbering saved for this title, Kinopub item and season. Future episodes use the same offset."
        } catch { message = "Numbering could not be saved. Check local storage and try again." }
    }

    func begin(_ context: EpisodeContext?) async {
        await checkpointCoverage(force: true)
        self.context = context
        resetCoverage()
    }

    func interruptPlayback() { coverage.interrupt() }

    private func resetCoverage() {
        coverageRevision = UUID()
        coverage = WatchedCoverage(); sessionKey = nil; submitted = false
        coverageEpisode = nil; savedCoverage = nil
    }

    private func checkpointCoverage(force: Bool = false) async {
        guard let episode = coverageEpisode, let state = coverage.state, state != savedCoverage,
              force || coverageCheckpoint.duration(to: .now) >= .seconds(5) else { return }
        let revision = coverageRevision
        do {
            try await coverageStore.save(WatchedCoverageRecord(episode: episode, state: state))
            guard revision == coverageRevision else { return }
            savedCoverage = state; coverageCheckpoint = .now
        } catch { message = "Watched segments could not be saved. The app will retry; check local storage." }
    }

    func capture(_ snapshot: PlaybackSnapshot, at instant: Double? = nil) async {
        guard isEnabled, isLoaded, let context, let number = number(for: context),
              let userID = shikimori.snapshot.profile?.id else {
            await checkpointCoverage(force: true)
            coverage.interrupt()
            return
        }
        let key = "\(userID):\(context.id):\(number)"
        if key != sessionKey {
            await checkpointCoverage(force: true)
            let revision = UUID(); coverageRevision = revision
            let episode = WatchedEpisode(userID: userID, context: context, number: number)
            do {
                let state = try await coverageStore.state(for: episode)
                guard revision == coverageRevision, self.context?.id == context.id,
                      isEnabled, shikimori.snapshot.profile?.id == userID, self.number(for: context) == number else { return }
                coverage = WatchedCoverage(restoring: state)
                savedCoverage = state; coverageEpisode = episode; coverageCheckpoint = .now
                submitted = false; sessionKey = key
            } catch {
                message = "Saved watched segments could not be read. Existing data was kept; check local storage."
                return
            }
        }
        let elapsed = clockOrigin.duration(to: .now).components
        coverage.observe(snapshot, at: instant ?? (Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18))
        await checkpointCoverage(force: coverage.isComplete || snapshot.isPaused || snapshot.hasEnded)
        guard isEnabled, self.context?.id == context.id, shikimori.snapshot.profile?.id == userID,
              self.number(for: context) == number, coverage.isComplete, !submitted else { return }
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
        await checkpointCoverage(force: true)
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
