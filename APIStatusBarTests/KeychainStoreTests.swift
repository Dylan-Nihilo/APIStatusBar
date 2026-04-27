import XCTest
@testable import APIStatusBar

final class KeychainStoreTests: XCTestCase {
    private var service: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["APISTATUSBAR_RUN_KEYCHAIN_TESTS"] == "1",
            "Keychain tests touch the user's login keychain; set APISTATUSBAR_RUN_KEYCHAIN_TESTS=1 to run them explicitly."
        )
        service = "com.dylan.apistatusbar.tests.\(UUID().uuidString)"
    }

    override func tearDown() {
        if let service {
            try? KeychainStore.delete(service: service, account: "default")
        }
        super.tearDown()
    }

    func test_setThenRead_returnsSameValue() throws {
        try KeychainStore.set("hunter2", service: service, account: "default")
        XCTAssertEqual(try KeychainStore.read(service: service, account: "default"), "hunter2")
    }

    func test_readMissing_returnsNil() throws {
        XCTAssertNil(try KeychainStore.read(service: service, account: "default"))
    }

    func test_setOverwritesExisting() throws {
        try KeychainStore.set("first", service: service, account: "default")
        try KeychainStore.set("second", service: service, account: "default")
        XCTAssertEqual(try KeychainStore.read(service: service, account: "default"), "second")
    }

    func test_deleteRemovesValue() throws {
        try KeychainStore.set("token", service: service, account: "default")
        try KeychainStore.delete(service: service, account: "default")
        XCTAssertNil(try KeychainStore.read(service: service, account: "default"))
    }
}
