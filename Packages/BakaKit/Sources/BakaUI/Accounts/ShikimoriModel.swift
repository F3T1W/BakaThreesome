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

    init() {
        let client = ShikimoriClient()
        self.client = client
        account = ShikimoriAccountService(client: client)
    }

    var credentials: ShikimoriCredentials? {
        try? ShikimoriCredentials(clientID: clientID, clientSecret: clientSecret)
    }

    func restore() async {
        guard !isBusy else { return }
        do { snapshot = try await account.restore() }
        catch { errorMessage = error.localizedDescription }
    }

    func signIn() {
        guard !isBusy, !isSaving, let credentials else { return }
        let code = authorizationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        run {
            try await self.account.signIn(code: code, credentials: credentials)
            self.clientSecret = ""
            self.authorizationCode = ""
        }
    }

    func signOut() {
        guard !isBusy, !isSaving else { return }
        run { try await self.account.signOut() }
    }

    func retrySession() {
        guard !isBusy, !isSaving else { return }
        run {
            let token = try await self.account.accessToken()
            _ = try await self.client.whoami(token)
        }
    }

    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        isBusy = true
        errorMessage = nil
        operation = Task {
            do { try await action() }
            catch { errorMessage = error.localizedDescription }
            snapshot = await account.snapshot()
            revision += 1
            isBusy = false
            operation = nil
        }
    }

    func token() async throws -> String {
        guard !isBusy else { throw ShikimoriError.notSignedIn }
        return try await account.accessToken()
    }

    func list(status: WatchStatus?, page: Int) async throws -> [AnimeListEntry] {
        let profile = try await account.identity()
        let token = try await token()
        return try await client.list(userID: profile.id, status: status, page: page, token: token)
    }

    func save(animeID: Int64, rateID: Int64?, status: WatchStatus, episodes: Int, score: Int) async throws -> AnimeUserRate {
        guard !isBusy, !isSaving else { throw ShikimoriError.invalidValues }
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
        guard !isBusy, !isSaving else { throw ShikimoriError.invalidValues }
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
