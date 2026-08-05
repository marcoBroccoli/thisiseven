import Foundation
import Security

/// Small, reusable wrapper around one generic-password Keychain item. Sensitive
/// local features should depend on this instead of persisting to UserDefaults.
public struct KeychainDataStore: Sendable {
    public enum StoreError: Error, LocalizedError, Sendable {
        case keychainStatus(Int32)

        public var errorDescription: String? {
            switch self {
            case let .keychainStatus(status):
                return "Secure storage is unavailable (Keychain status \(status))."
            }
        }
    }

    public let service: String
    public let account: String

    public init(service: String, account: String) {
        self.service = service
        self.account = account
    }

    public func load() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw StoreError.keychainStatus(status) }
        return result as? Data
    }

    public func save(_ data: Data) throws {
        let status = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecItemNotFound {
            var query = baseQuery
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw StoreError.keychainStatus(addStatus) }
            return
        }
        guard status == errSecSuccess else { throw StoreError.keychainStatus(status) }
    }

    public func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.keychainStatus(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
