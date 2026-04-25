import Foundation
import Security

enum KeychainError: Error {
    case unhandled(OSStatus)
    case unexpectedItemFormat
}

enum KeychainStore {
    /// Store or update a string value. Overwrites if an item with the same service+account exists.
    static func set(_ value: String, service: String, account: String) throws {
        guard let data = value.data(using: .utf8) else { throw KeychainError.unexpectedItemFormat }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attrs: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unhandled(addStatus) }
        default:
            throw KeychainError.unhandled(updateStatus)
        }
    }

    /// Read a string value, or `nil` if not found.
    static func read(service: String, account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
                throw KeychainError.unexpectedItemFormat
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unhandled(status)
        }
    }

    /// Delete the item. No-op if absent.
    static func delete(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }
}

/// Convenience scoped to this app — the canonical service string for production reads/writes.
extension KeychainStore {
    static let appService = "com.dylan.apistatusbar"
    static let tokenAccount = "accessToken"

    static func setAccessToken(_ token: String) throws {
        try set(token, service: appService, account: tokenAccount)
    }

    static func readAccessToken() throws -> String? {
        try read(service: appService, account: tokenAccount)
    }

    static func deleteAccessToken() throws {
        try delete(service: appService, account: tokenAccount)
    }
}
