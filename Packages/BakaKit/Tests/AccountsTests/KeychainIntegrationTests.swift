import Accounts
import Foundation
import Testing

@Suite(.enabled(if: ProcessInfo.processInfo.environment["BAKA_KEYCHAIN_INTEGRATION"] == "1"))
struct KeychainIntegrationTests {
    @Test func isolatedItemCanBeCreatedReadUpdatedAndDeleted() async throws {
        let service = "dev.bakathreesome.tests.\(UUID().uuidString)"
        let store = KeychainCredentialStore(service: service)
        do {
            #expect(try await store.read(.shikimoriSession) == nil)
            try await store.write(Data("synthetic-first-value".utf8), for: .shikimoriSession)
            #expect(try await store.read(.shikimoriSession) == Data("synthetic-first-value".utf8))
            try await store.write(Data("synthetic-replacement-value".utf8), for: .shikimoriSession)
            #expect(try await store.read(.shikimoriSession) == Data("synthetic-replacement-value".utf8))
            try await store.delete(.shikimoriSession)
            #expect(try await store.read(.shikimoriSession) == nil)
            try await store.delete(.shikimoriSession)
        } catch {
            try? await store.delete(.shikimoriSession)
            throw error
        }
    }
}
