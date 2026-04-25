import XCTest
@testable import APIStatusBar

final class KeychainStoreTests: XCTestCase {
    private var service: String!

    override func setUp() {
        super.setUp()
        service = "com.dylan.apistatusbar.tests.\(UUID().uuidString)"
    }

    override func tearDown() {
        try? KeychainStore.delete(service: service, account: "default")
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
