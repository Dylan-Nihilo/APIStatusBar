import Combine
import Foundation

protocol CredentialStorage {
    func readAccessToken() throws -> String?
    func setAccessToken(_ token: String) throws
    func deleteAccessToken() throws
}

struct KeychainCredentialStorage: CredentialStorage {
    func readAccessToken() throws -> String? {
        try KeychainStore.readAccessToken()
    }

    func setAccessToken(_ token: String) throws {
        try KeychainStore.setAccessToken(token)
    }

    func deleteAccessToken() throws {
        try KeychainStore.deleteAccessToken()
    }
}

@MainActor
final class CredentialStore: ObservableObject {
    @Published private(set) var accessToken: String
    @Published private(set) var lastError: Error?

    private let storage: CredentialStorage

    init(loadStoredToken: Bool = true,
         storage: CredentialStorage = KeychainCredentialStorage()) {
        self.storage = storage

        guard loadStoredToken else {
            accessToken = ""
            lastError = nil
            return
        }

        do {
            accessToken = try storage.readAccessToken() ?? ""
            lastError = nil
        } catch {
            accessToken = ""
            lastError = error
        }
    }

    @discardableResult
    func saveAccessToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        accessToken = trimmed
        do {
            if trimmed.isEmpty {
                try storage.deleteAccessToken()
            } else {
                try storage.setAccessToken(trimmed)
            }
            lastError = nil
            return true
        } catch {
            lastError = error
            return true
        }
    }

    @discardableResult
    func clearAccessToken() -> Bool {
        saveAccessToken("")
    }
}
