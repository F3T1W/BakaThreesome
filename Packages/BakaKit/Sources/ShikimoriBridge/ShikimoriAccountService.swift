import Accounts
import Foundation

public struct ShikimoriAccountSnapshot: Sendable {
    public let profile: ShikimoriProfile?
    public let isSignedIn: Bool
    public let isPersisted: Bool
    public static let signedOut = ShikimoriAccountSnapshot(profile: nil, isSignedIn: false, isPersisted: true)
}

private struct StoredAccount: Codable, Sendable {
    let credentials: ShikimoriCredentials
    let tokens: ShikimoriTokens
    var profile: ShikimoriProfile?
}

public actor ShikimoriAccountService {
    private let client: ShikimoriClient
    private let store: any CredentialStore
    private var account: StoredAccount?
    private var loaded = false
    private var dirty = false
    private var busy = false
    private var generation = 0
    private var refresh: (id: UUID, task: Task<String, Error>)?

    public init(client: ShikimoriClient, store: any CredentialStore = KeychainCredentialStore()) {
        self.client = client
        self.store = store
    }

    public func snapshot() -> ShikimoriAccountSnapshot {
        ShikimoriAccountSnapshot(profile: account?.profile, isSignedIn: account != nil, isPersisted: !dirty)
    }

    public func restore() async throws -> ShikimoriAccountSnapshot {
        guard !busy else { throw ShikimoriError.invalidValues }
        if !loaded {
            do {
                let originalGeneration = generation
                let data = try await store.read(.shikimoriSession)
                let saved = try data.map { try JSONDecoder().decode(StoredAccount.self, from: $0) }
                if let saved {
                    guard !saved.credentials.clientID.isEmpty, !saved.credentials.clientSecret.isEmpty,
                          !saved.tokens.accessToken.isEmpty, !saved.tokens.refreshToken.isEmpty,
                          saved.tokens.expiresAt.isFinite else { throw ShikimoriError.storageFailed }
                }
                guard !busy, generation == originalGeneration else { return snapshot() }
                if !loaded { account = saved; loaded = true }
            } catch { throw ShikimoriError.storageFailed }
        }
        return snapshot()
    }

    public func signIn(code: String, credentials: ShikimoriCredentials) async throws {
        guard !busy, refresh == nil else { throw ShikimoriError.invalidValues }
        busy = true
        generation += 1
        loaded = true
        defer { busy = false }
        let tokens = try await client.exchange(code: code, credentials: credentials)
        account = StoredAccount(credentials: credentials, tokens: tokens)
        loaded = true
        dirty = true
        try await persist()
        let profile = try await client.whoami(tokens.accessToken)
        account?.profile = profile
        dirty = true
        try await persist()
    }

    public func accessToken(forceRefresh: Bool = false) async throws -> String {
        _ = try await restore()
        guard !busy, account != nil else { throw ShikimoriError.notSignedIn }
        let flight: (id: UUID, task: Task<String, Error>)
        if let refresh { flight = refresh }
        else {
            flight = (UUID(), Task { try await tokenOperation(force: forceRefresh) })
            refresh = flight
        }
        do {
            let token = try await flight.task.value
            if refresh?.id == flight.id { refresh = nil }
            return token
        } catch {
            if refresh?.id == flight.id { refresh = nil }
            throw error
        }
    }

    public func identity() async throws -> ShikimoriProfile {
        let token = try await accessToken()
        if let profile = account?.profile { return profile }
        let originalGeneration = generation
        let profile = try await client.whoami(token)
        guard !busy, generation == originalGeneration, account != nil else { throw ShikimoriError.notSignedIn }
        account?.profile = profile
        dirty = true
        try await persist()
        return profile
    }

    public func signOut() async throws {
        guard !busy else { throw ShikimoriError.invalidValues }
        busy = true
        generation += 1
        defer { busy = false }
        if let refresh { _ = try? await refresh.task.value }
        do { try await store.delete(.shikimoriSession) }
        catch { throw ShikimoriError.storageFailed }
        account = nil
        loaded = true
        dirty = false
        refresh = nil
    }

    public func finishPendingRefresh() async {
        if let refresh { _ = try? await refresh.task.value }
    }

    private func tokenOperation(force: Bool) async throws -> String {
        if dirty { try await persist() }
        guard let current = account else { throw ShikimoriError.notSignedIn }
        if !force, current.tokens.expiresAt > Date().timeIntervalSince1970 + 60 { return current.tokens.accessToken }
        let tokens = try await client.refresh(token: current.tokens.refreshToken, credentials: current.credentials)
        account = StoredAccount(credentials: current.credentials, tokens: tokens, profile: current.profile)
        dirty = true
        try await persist()
        return tokens.accessToken
    }

    private func persist() async throws {
        guard let account else { return }
        do {
            try await store.write(JSONEncoder().encode(account), for: .shikimoriSession)
            dirty = false
        } catch {
            dirty = true
            throw ShikimoriError.storageFailed
        }
    }
}
