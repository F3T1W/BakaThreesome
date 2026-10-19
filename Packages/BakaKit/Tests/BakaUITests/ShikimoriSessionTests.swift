import Accounts
@testable import BakaUI
import Foundation
import ShikimoriBridge
import Testing

@MainActor
@Test func failedRestorationIsVisibleAndRetryRecoversSavedAccount() async throws {
    let data = Data("""
        {"credentials":{"clientID":"synthetic-client","clientSecret":"synthetic-secret"},
         "tokens":{"accessToken":"synthetic-access","refreshToken":"synthetic-refresh","expiresAt":4102444800},
         "profile":{"id":42,"nickname":"Example"}}
        """.utf8)
    let store = RecoverableSessionStore(data: data)
    let model = ShikimoriModel(store: store)
    await model.restore()
    #expect(model.restorationError != nil)
    #expect(!model.snapshot.isSignedIn)
    #expect(!model.isRestoring)
    #expect(await store.readCount == 1)
    await model.restore()
    #expect(model.restorationError == nil)
    #expect(model.snapshot.isSignedIn)
    #expect(model.snapshot.isPersisted)
    #expect(model.snapshot.profile?.id == 42)
    #expect(await store.readCount == 2)
    await model.shutdown()
}

@MainActor
@Test func absentSavedSessionIsSignedOutWithoutAnError() async {
    let model = ShikimoriModel(store: RecoverableSessionStore(data: nil, failFirstRead: false))
    await model.restore()
    #expect(model.restorationError == nil)
    #expect(!model.snapshot.isSignedIn)
    #expect(!model.isRestoring)
    await model.shutdown()
}

private actor RecoverableSessionStore: CredentialStore {
    private let data: Data?
    private var failFirstRead: Bool
    private(set) var readCount = 0

    init(data: Data?, failFirstRead: Bool = true) {
        self.data = data
        self.failFirstRead = failFirstRead
    }

    func read(_ key: CredentialKey) throws -> Data? {
        readCount += 1
        if failFirstRead {
            failFirstRead = false
            throw CredentialStoreError.unavailable
        }
        return data
    }

    func write(_ data: Data, for key: CredentialKey) throws {}
    func delete(_ key: CredentialKey) throws {}
}
