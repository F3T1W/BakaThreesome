import Accounts
import Catalog
import Foundation
import Observation
import ShikimoriBridge
import Tracking

@MainActor
@Observable
final class ShikimoriModel: EpisodeProgressClient {
    let client: ShikimoriClient
    private let account: ShikimoriAccountService
    private(set) var snapshot = ShikimoriAccountSnapshot.signedOut
    private(set) var isRestoring = false
    private(set) var restorationError: String?
    private(set) var isBusy = false
    private(set) var isSaving = false
    private(set) var revision = 0
    var errorMessage: String?
    var clientID = ""
    var clientSecret = ""
    var authorizationCode = ""
    private var operation: Task<Void, Never>?
    private var progressTask: Task<ProgressDecision, Error>?
    private var saveTask: Task<AnimeUserRate, Error>?

    init(client: ShikimoriClient = ShikimoriClient(), store: any CredentialStore = KeychainCredentialStore()) {
        self.client = client
        account = ShikimoriAccountService(client: client, store: store)
    }

    var credentials: ShikimoriCredentials? {
        try? ShikimoriCredentials(clientID: clientID, clientSecret: clientSecret)
    }

    func restore() async {
        guard !isBusy, !isRestoring else { return }
        isRestoring = true
        restorationError = nil
        defer { isRestoring = false }
        do { snapshot = try await account.restore() }
        catch { restorationError = error.localizedDescription }
    }

    func signIn() {
        guard !isBusy, !isRestoring, !isSaving, let credentials else { return }
        let code = authorizationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        run {
            try await self.account.signIn(code: code, credentials: credentials)
            self.clientSecret = ""
            self.authorizationCode = ""
        }
    }

    func signOut() {
        guard !isBusy, !isRestoring, !isSaving else { return }
        run { try await self.account.signOut() }
    }

    func retrySession() {
        guard !isBusy, !isRestoring, !isSaving else { return }
        run {
            _ = try await self.account.checkSession()
        }
    }

    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        isBusy = true
        errorMessage = nil
        operation = Task {
            do {
                try await action()
                restorationError = nil
            }
            catch { errorMessage = error.localizedDescription }
            snapshot = await account.snapshot()
            revision += 1
            isBusy = false
            operation = nil
        }
    }

    func details(_ animeID: Int64) async throws -> AnimeDetails {
        guard !isBusy, !isRestoring else { throw ShikimoriError.notSignedIn }
        return try await account.details(animeID)
    }

    func list(status: WatchStatus?, page: Int) async throws -> [AnimeListEntry] {
        guard !isBusy, !isRestoring else { throw ShikimoriError.notSignedIn }
        return try await account.list(status: status, page: page)
    }

    func save(animeID: Int64, rateID: Int64?, status: WatchStatus, episodes: Int, score: Int) async throws -> AnimeUserRate {
        guard !isBusy, !isRestoring, !isSaving else { throw ShikimoriError.invalidValues }
        isSaving = true
        let task = Task {
            let profile = try await account.identity()
            let token = try await account.accessToken()
            return try await client.save(animeID: animeID, rateID: rateID, userID: profile.id,
                                         status: status, episodes: episodes, score: score, token: token)
        }
        saveTask = task
        defer { saveTask = nil; isSaving = false }
        let result = try await task.value
        revision += 1
        snapshot = await account.snapshot()
        return result
    }

    func advance(_ episode: WatchedEpisode) async throws -> ProgressDecision {
        guard !isBusy, !isRestoring, !isSaving else { throw ShikimoriError.invalidValues }
        isSaving = true
        let task = Task {
            let profile = try await account.identity()
            guard profile.id == episode.userID else { throw ShikimoriError.notSignedIn }
            let token = try await account.accessToken()
            return try await client.advanceProgress(episode, token: token)
        }
        progressTask = task
        defer { progressTask = nil; isSaving = false }
        let result = try await task.value
        if result == .advance { revision += 1 }
        snapshot = await account.snapshot()
        return result
    }

    func shutdown() async {
        await operation?.value
        _ = try? await saveTask?.value
        _ = try? await progressTask?.value
        await account.finishPendingRefresh()
        await client.shutdown()
    }
}
