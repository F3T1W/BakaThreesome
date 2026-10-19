import Accounts
import Foundation
import ShikimoriBridge
import Testing
import Tracking

@Test func serializesNumericIDsAndProtectsWritesFromNavigationCancellation() async throws {
    let transport = FakeShikimoriTransport()
    let client = ShikimoriClient(transport: transport)
    let result = try await client.save(animeID: 1, rateID: 7_000_000_000, userID: 42,
                                       status: .onHold, episodes: 3, score: 8, token: "synthetic-access")
    #expect(result.id == 7_000_000_000 && result.status == .onHold)
    #expect(await transport.lastWriteWasProtected)
    #expect(await transport.lastRateID == 7_000_000_000)
}

@Test func rejectsMismatchedResponseIDsAndSanitizesServerErrors() async throws {
    let transport = FakeShikimoriTransport()
    let client = ShikimoriClient(transport: transport)
    await transport.setReply(.wrongID)
    await #expect(throws: ShikimoriError.invalidResponse) { try await client.search("test", page: 1) }
    await transport.setReply(.unauthorized)
    await #expect(throws: ShikimoriError.unauthorized) { try await client.search("test", page: 1) }
}

@Test func rotationIsSharedAndFailedStorageRetriesTheSamePair() async throws {
    let transport = FakeShikimoriTransport(expired: true, pauseRefresh: true)
    let store = MemoryShikimoriStore()
    let service = ShikimoriAccountService(client: ShikimoriClient(transport: transport), store: store)
    try await service.signIn(code: "synthetic-code", credentials: credentials())
    await store.failNextWrite()
    let first = Task { try await service.accessToken() }
    await transport.waitForRefresh()
    let second = Task { try await service.accessToken() }
    await transport.resumeRefresh()
    await #expect(throws: ShikimoriError.storageFailed) { try await first.value }
    // Whether the second caller joins before or after the failed write, it cannot rotate twice.
    _ = try? await second.value
    #expect(try await service.accessToken() == "rotated-access")
    #expect(await transport.refreshCount == 1)
    #expect(await service.snapshot().isPersisted)
    let restored = ShikimoriAccountService(client: ShikimoriClient(transport: transport), store: store)
    #expect(try await restored.accessToken() == "rotated-access")
    #expect(await transport.refreshCount == 1)
}

@Test func signOutWaitsForRotationAndDeletesTheRotatedSession() async throws {
    let transport = FakeShikimoriTransport(expired: true, pauseRefresh: true)
    let store = MemoryShikimoriStore()
    let service = ShikimoriAccountService(client: ShikimoriClient(transport: transport), store: store)
    try await service.signIn(code: "synthetic-code", credentials: credentials())
    let refresh = Task { try await service.accessToken() }
    await transport.waitForRefresh()
    let logout = Task { try await service.signOut() }
    await transport.resumeRefresh()
    _ = try? await refresh.value
    try await logout.value
    #expect(await store.data == nil)
    #expect(await service.snapshot().isSignedIn == false)
    await #expect(throws: ShikimoriError.notSignedIn) { try await service.accessToken() }
}

@Test func corruptSavedSessionsCanBeForgotten() async throws {
    let store = MemoryShikimoriStore(data: Data("invalid".utf8))
    let service = ShikimoriAccountService(client: ShikimoriClient(transport: FakeShikimoriTransport()), store: store)
    await #expect(throws: ShikimoriError.storageFailed) { try await service.restore() }
    try await service.signOut()
    #expect(await store.data == nil)
}

@Test func rejectedAccessTokenIsRenewedOnceAndPersistsAcrossRelaunch() async throws {
    let transport = FakeShikimoriTransport()
    let store = MemoryShikimoriStore()
    let client = ShikimoriClient(transport: transport)
    let service = ShikimoriAccountService(client: client, store: store)
    try await service.signIn(code: "synthetic-code", credentials: credentials())
    let restored = ShikimoriAccountService(client: client, store: store)
    #expect(try await restored.restore().profile?.id == 42)
    await transport.setReply(.rejectOriginalToken)
    #expect(try await restored.list(status: .watching, page: 1).isEmpty)
    #expect(await transport.refreshCount == 1)
    #expect(try await restored.checkSession().id == 42)
    // A late rejection of the old token must reuse the already rotated pair.
    #expect(try await restored.accessToken(rejecting: "synthetic-access") == "rotated-access")
    let relaunched = ShikimoriAccountService(client: client, store: store)
    #expect(try await relaunched.accessToken() == "rotated-access")
    #expect(await transport.refreshCount == 1)
}

@Test func concurrentRejectedReadsShareRotation() async throws {
    let transport = FakeShikimoriTransport(pauseRefresh: true)
    let service = ShikimoriAccountService(client: ShikimoriClient(transport: transport), store: MemoryShikimoriStore())
    try await service.signIn(code: "synthetic-code", credentials: credentials())
    await transport.setReply(.rejectOriginalToken)
    let first = Task { try await service.checkSession() }
    await transport.waitForRefresh()
    let second = Task { try await service.checkSession() }
    await transport.resumeRefresh()
    #expect(try await first.value.id == 42)
    #expect(try await second.value.id == 42)
    #expect(await transport.refreshCount == 1)
}

@Test func repeatedRejectionStopsAfterOneRenewalWithoutDeletingSession() async throws {
    let transport = FakeShikimoriTransport()
    let store = MemoryShikimoriStore()
    let service = ShikimoriAccountService(client: ShikimoriClient(transport: transport), store: store)
    try await service.signIn(code: "synthetic-code", credentials: credentials())
    await transport.setReply(.rejectReads)
    await #expect(throws: ShikimoriError.unauthorized) { try await service.checkSession() }
    #expect(await transport.refreshCount == 1)
    #expect(await service.snapshot().isSignedIn)
    #expect(await store.data != nil)
    await transport.setReply(.normal)
    #expect(try await service.checkSession().id == 42)
}

@Test func unavailableKeychainCanBeRetriedWithoutForgettingTheAccount() async throws {
    let store = MemoryShikimoriStore()
    let client = ShikimoriClient(transport: FakeShikimoriTransport())
    try await ShikimoriAccountService(client: client, store: store).signIn(code: "synthetic-code", credentials: credentials())
    let service = ShikimoriAccountService(client: client, store: store)
    await store.failNextRead()
    await #expect(throws: ShikimoriError.storageFailed) { try await service.restore() }
    #expect(await store.data != nil)
    #expect(try await service.restore().profile?.id == 42)
}

@Test func failedAuthorizationDoesNotHideAnUnreadSavedSession() async throws {
    let store = MemoryShikimoriStore()
    let transport = FakeShikimoriTransport()
    let client = ShikimoriClient(transport: transport)
    try await ShikimoriAccountService(client: client, store: store).signIn(code: "synthetic-code", credentials: credentials())
    let service = ShikimoriAccountService(client: client, store: store)
    await transport.setReply(.unauthorized)
    await #expect(throws: ShikimoriError.unauthorized) {
        try await service.signIn(code: "invalid-code", credentials: credentials())
    }
    #expect(try await service.restore().profile?.id == 42)
}

@Test func realPipeTransportFramesResponsesAndRestartsAfterShutdown() async throws {
    let script = """
    import sys,json
    for line in sys.stdin:
        q=json.loads(line)
        data=json.dumps({'version':1,'id':q['id'],'result':[]}).encode()+b'\\n'
        sys.stdout.buffer.write(data[:9]);sys.stdout.buffer.flush()
        sys.stdout.buffer.write(data[9:]);sys.stdout.buffer.flush()
    """
    let transport = BridgeProcessTransport(executable: URL(fileURLWithPath: "/usr/bin/python3"), arguments: ["-u", "-c", script])
    let client = ShikimoriClient(transport: transport)
    do {
        #expect(try await client.search("quoted \"title\"", page: 1).isEmpty)
        await client.shutdown()
        #expect(try await client.search("restart", page: 1).isEmpty)
        await client.shutdown()
    } catch {
        await client.shutdown()
        throw error
    }
}

private func credentials() throws -> ShikimoriCredentials {
    try ShikimoriCredentials(clientID: "synthetic-client", clientSecret: "synthetic-secret")
}

private actor MemoryShikimoriStore: CredentialStore {
    var data: Data?
    private var shouldFail = false
    private var readShouldFail = false
    init(data: Data? = nil) { self.data = data }
    func read(_ key: CredentialKey) async throws -> Data? {
        if readShouldFail { readShouldFail = false; throw CredentialStoreError.unavailable }
        return data
    }
    func write(_ data: Data, for key: CredentialKey) async throws {
        if shouldFail { shouldFail = false; throw CredentialStoreError.unavailable }
        self.data = data
    }
    func delete(_ key: CredentialKey) async throws { data = nil }
    func failNextRead() { readShouldFail = true }
    func failNextWrite() { shouldFail = true }
}

private actor FakeShikimoriTransport: BridgeTransport {
    enum Reply { case normal, wrongID, unauthorized, rejectOriginalToken, rejectReads }
    private var reply = Reply.normal
    private let expired: Bool
    private let pauseRefresh: Bool
    private var refreshWaiter: CheckedContinuation<Void, Never>?
    private var refreshStarted: CheckedContinuation<Void, Never>?
    private(set) var refreshCount = 0
    private(set) var lastWriteWasProtected = false
    private(set) var lastRateID: Int64?
    init(expired: Bool = false, pauseRefresh: Bool = false) {
        self.expired = expired; self.pauseRefresh = pauseRefresh
    }
    func setReply(_ value: Reply) { reply = value }
    func waitForRefresh() async {
        if refreshCount == 0 { await withCheckedContinuation { refreshStarted = $0 } }
    }
    func resumeRefresh() { refreshWaiter?.resume(); refreshWaiter = nil }
    func exchange(_ data: Data, cancelSafe: Bool) async throws -> Data {
        let request = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let method = try #require(request["method"] as? String)
        let id = try #require(request["id"] as? String)
        let parameters = request["parameters"] as? [String: Any]
        let accessToken = parameters?["accessToken"] as? String
        let isRead = method == "account.whoami" || method == "watchlist.list" || method == "anime.details"
        if reply == .unauthorized || (isRead && (reply == .rejectReads ||
            (reply == .rejectOriginalToken && accessToken == "synthetic-access"))) {
            return try JSONSerialization.data(withJSONObject: ["version": 1, "id": id,
                "error": ["code": "unauthorized", "message": "secret server diagnostics"]])
        }
        var result: Any = []
        switch method {
        case "account.exchange", "account.refresh":
            if method == "account.refresh" {
                refreshCount += 1
                refreshStarted?.resume(); refreshStarted = nil
                if pauseRefresh { await withCheckedContinuation { refreshWaiter = $0 } }
            }
            result = ["accessToken": method == "account.refresh" ? "rotated-access" : "synthetic-access",
                      "refreshToken": "synthetic-refresh",
                      "expiresAt": Date().timeIntervalSince1970 + (expired && method == "account.exchange" ? -1 : 3600)] as [String: Any]
        case "account.whoami": result = ["id": 42, "nickname": "Example"] as [String: Any]
        case "watchlist.save":
            lastWriteWasProtected = !cancelSafe
            let parameters = try #require(request["parameters"] as? [String: Any])
            lastRateID = (parameters["rateID"] as? NSNumber)?.int64Value
            result = ["id": 7_000_000_000 as Int64, "animeID": 1, "status": "on_hold", "episodes": 3, "score": 8] as [String: Any]
        default: break
        }
        return try JSONSerialization.data(withJSONObject: ["version": 1, "id": reply == .wrongID ? "other" : id, "result": result])
    }
    func shutdown() async {}
}
