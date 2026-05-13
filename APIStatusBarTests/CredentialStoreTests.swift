import XCTest
@testable import APIStatusBar

@MainActor
final class CredentialStoreTests: XCTestCase {
    func test_initCanSkipKeychainReadForFirstRun() {
        let storage = SpyCredentialStorage(storedToken: "saved")

        let store = CredentialStore(loadStoredToken: false, storage: storage)

        XCTAssertEqual(store.accessToken, "")
        XCTAssertEqual(storage.readCount, 0)
    }

    func test_initReadsKeychainAtMostOnceWhenRestoreIsRequested() {
        let storage = SpyCredentialStorage(storedToken: "saved")

        let store = CredentialStore(loadStoredToken: true, storage: storage)
        _ = store.accessToken
        _ = store.accessToken

        XCTAssertEqual(store.accessToken, "saved")
        XCTAssertEqual(storage.readCount, 1)
    }

    func test_saveUsesMemoryWithoutReadingKeychainAgain() {
        let storage = SpyCredentialStorage(storedToken: "saved")
        let store = CredentialStore(loadStoredToken: false, storage: storage)

        XCTAssertTrue(store.saveAccessToken(" fresh "))

        XCTAssertEqual(store.accessToken, "fresh")
        XCTAssertEqual(storage.readCount, 0)
        XCTAssertEqual(storage.savedTokens, ["fresh"])
    }

    func test_saveKeepsTokenInMemoryWhenPersistenceFails() {
        let storage = FailingCredentialStorage()
        let store = CredentialStore(loadStoredToken: false, storage: storage)

        XCTAssertTrue(store.saveAccessToken(" fresh "))

        XCTAssertEqual(store.accessToken, "fresh")
        XCTAssertNotNil(store.lastError)
    }
}

private final class SpyCredentialStorage: CredentialStorage {
    var storedToken: String?
    var readCount = 0
    var savedTokens: [String] = []
    var deleteCount = 0

    init(storedToken: String?) {
        self.storedToken = storedToken
    }

    func readAccessToken() throws -> String? {
        readCount += 1
        return storedToken
    }

    func setAccessToken(_ token: String) throws {
        savedTokens.append(token)
        storedToken = token
    }

    func deleteAccessToken() throws {
        deleteCount += 1
        storedToken = nil
    }
}

private final class FailingCredentialStorage: CredentialStorage {
    func readAccessToken() throws -> String? {
        throw TestError.failed
    }

    func setAccessToken(_ token: String) throws {
        throw TestError.failed
    }

    func deleteAccessToken() throws {
        throw TestError.failed
    }

    enum TestError: Error {
        case failed
    }
}
