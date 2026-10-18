import Foundation

public enum CredentialKey: String, Sendable {
    case shikimoriSession = "shikimori-session"
}

public protocol CredentialStore: Sendable {
    func read(_ key: CredentialKey) async throws -> Data?
    func write(_ data: Data, for key: CredentialKey) async throws
    func delete(_ key: CredentialKey) async throws
}

public enum CredentialStoreError: Error, LocalizedError {
    case unavailable

    public var errorDescription: String? {
        "macOS Keychain could not be accessed. Unlock your keychain and try again."
    }
}
