import Combine
import Foundation

@MainActor
final class CredentialStore: ObservableObject {
    @Published private(set) var accessToken: String
    @Published private(set) var lastError: Error?

    init() {
        do {
            accessToken = try KeychainStore.readAccessToken() ?? ""
            lastError = nil
        } catch {
            accessToken = ""
            lastError = error
        }
    }

    @discardableResult
    func saveAccessToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if trimmed.isEmpty {
                try KeychainStore.deleteAccessToken()
            } else {
                try KeychainStore.setAccessToken(trimmed)
            }
            accessToken = trimmed
            lastError = nil
            return true
        } catch {
            lastError = error
            return false
        }
    }
}
