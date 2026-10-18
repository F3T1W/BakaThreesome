import Foundation
import Security

/// Security operations run outside MainActor. Each account is a single item so
/// a rotated access/refresh token pair is replaced atomically.
public actor KeychainCredentialStore: CredentialStore {
    private let service: String

    public init(service: String = "dev.bakathreesome.accounts") {
        self.service = service
    }

    public func read(_ key: CredentialKey) throws -> Data? {
        var query = query(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw CredentialStoreError.unavailable
        }
        return data
    }

    public func write(_ data: Data, for key: CredentialKey) throws {
        let query = query(for: key)
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            // Local ad-hoc builds use the macOS login keychain and its app ACL.
            // kSecAttrAccessible requires the entitlement-backed data protection keychain.
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
                throw CredentialStoreError.unavailable
            }
        } else if status != errSecSuccess {
            throw CredentialStoreError.unavailable
        }
    }

    public func delete(_ key: CredentialKey) throws {
        let status = SecItemDelete(query(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.unavailable
        }
    }

    private func query(for key: CredentialKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecUseDataProtectionKeychain as String: false
        ]
    }
}
