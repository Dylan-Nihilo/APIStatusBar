import XCTest
@testable import APIStatusBar

@MainActor
final class QuotaPollerTests: XCTestCase {
    var session: URLSession!

    override func setUp() async throws {
        URLProtocolStub.reset()
        session = URLProtocolStub.session()
    }

    override func tearDown() async throws {
        URLProtocolStub.reset()
    }

    private func makeClient() -> NewAPIClient {
        NewAPIClient(
            baseURL: URL(string: "https://api.example.com")!,
            accessToken: "tok",
            session: session
        )
    }

    func test_refresh_storesSnapshot_onSuccess() async {
        URLProtocolStub.handler = { _ in
            let body = """
            {"success":true,"message":"","data":{"quota":500000,"used_quota":1500000,"request_count":7}}
            """.data(using: .utf8)!
            let response = HTTPURLResponse(url: URL(string: "https://api.example.com")!,
                                            statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }

        let poller = QuotaPoller(client: makeClient(), intervalSeconds: 60, now: { Date(timeIntervalSince1970: 1000) })
        await poller.refresh()

        XCTAssertEqual(poller.snapshot?.quotaRaw, 500_000)
        XCTAssertEqual(poller.snapshot?.usedQuotaRaw, 1_500_000)
        XCTAssertEqual(poller.snapshot?.requestCount, 7)
        XCTAssertEqual(poller.snapshot?.fetchedAt, Date(timeIntervalSince1970: 1000))
        XCTAssertNil(poller.lastError)
    }

    func test_refresh_storesError_onFailure_andKeepsPreviousSnapshot() async {
        URLProtocolStub.handler = { _ in
            let body = """
            {"success":true,"message":"","data":{"quota":500000,"used_quota":0,"request_count":0}}
            """.data(using: .utf8)!
            let response = HTTPURLResponse(url: URL(string: "https://api.example.com")!,
                                            statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }

        let poller = QuotaPoller(client: makeClient(), intervalSeconds: 60, now: { Date() })
        await poller.refresh()
        XCTAssertNotNil(poller.snapshot)

        URLProtocolStub.handler = { _ in
            let response = HTTPURLResponse(url: URL(string: "https://api.example.com")!,
                                            statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        await poller.refresh()

        XCTAssertNotNil(poller.snapshot, "previous snapshot should be retained")
        XCTAssertNotNil(poller.lastError)
        if let err = poller.lastError as? NewAPIError, case .httpStatus(let code) = err {
            XCTAssertEqual(code, 401)
        } else {
            XCTFail("expected httpStatus 401, got \(String(describing: poller.lastError))")
        }
    }
}
