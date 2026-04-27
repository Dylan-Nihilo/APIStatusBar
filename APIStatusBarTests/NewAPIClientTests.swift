import XCTest
@testable import APIStatusBar

final class NewAPIClientTests: XCTestCase {
    var session: URLSession!

    override func setUp() {
        super.setUp()
        URLProtocolStub.reset()
        session = URLProtocolStub.session()
    }

    override func tearDown() {
        URLProtocolStub.reset()
        super.tearDown()
    }

    private func makeClient() -> NewAPIClient {
        NewAPIClient(
            baseURL: URL(string: "https://api.example.com")!,
            accessToken: "test-token",
            userID: 42,
            session: session
        )
    }

    func test_getSelf_sendsCorrectRequestShape() async throws {
        URLProtocolStub.handler = { _ in
            let body = """
            {"success":true,"message":"","data":{"quota":1000000,"used_quota":2500000,"request_count":120}}
            """.data(using: .utf8)!
            let response = HTTPURLResponse(url: URL(string: "https://api.example.com/api/user/self")!,
                                            statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }

        _ = try await makeClient().getSelf()

        let req = try XCTUnwrap(URLProtocolStub.lastRequest)
        XCTAssertEqual(req.url?.path, "/api/user/self")
        XCTAssertEqual(req.httpMethod, "GET")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "test-token")
        XCTAssertEqual(req.value(forHTTPHeaderField: "New-Api-User"), "42")
    }

    func test_getSelf_omitsUserHeaderWhenUnresolved() async throws {
        URLProtocolStub.handler = { _ in
            let body = """
            {"success":true,"message":"","data":{"quota":1000000,"used_quota":2500000,"request_count":120}}
            """.data(using: .utf8)!
            let response = HTTPURLResponse(url: URL(string: "https://api.example.com/api/user/self")!,
                                            statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }

        let client = NewAPIClient(
            baseURL: URL(string: "https://api.example.com")!,
            accessToken: "test-token",
            session: session
        )

        _ = try await client.getSelf()

        let req = try XCTUnwrap(URLProtocolStub.lastRequest)
        XCTAssertNil(req.value(forHTTPHeaderField: "New-Api-User"))
    }

    func test_getSelf_decodesPayload() async throws {
        URLProtocolStub.handler = { _ in
            let body = """
            {"success":true,"message":"","data":{"quota":1000000,"used_quota":2500000,"request_count":120}}
            """.data(using: .utf8)!
            let response = HTTPURLResponse(url: URL(string: "https://api.example.com/api/user/self")!,
                                            statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }

        let resp = try await makeClient().getSelf()
        XCTAssertEqual(resp.quota, 1_000_000)
        XCTAssertEqual(resp.usedQuota, 2_500_000)
        XCTAssertEqual(resp.requestCount, 120)
    }

    func test_getSelf_httpErrorThrows() async {
        URLProtocolStub.handler = { _ in
            let response = HTTPURLResponse(url: URL(string: "https://api.example.com/api/user/self")!,
                                            statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        await XCTAssertThrowsErrorAsync(try await self.makeClient().getSelf()) { error in
            guard case NewAPIError.httpStatus(let code) = error else {
                return XCTFail("expected httpStatus, got \(error)")
            }
            XCTAssertEqual(code, 500)
        }
    }

    func test_getSelf_apiFailureThrows() async {
        URLProtocolStub.handler = { _ in
            let body = """
            {"success":false,"message":"access token invalid","data":null}
            """.data(using: .utf8)!
            let response = HTTPURLResponse(url: URL(string: "https://api.example.com/api/user/self")!,
                                            statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }

        await XCTAssertThrowsErrorAsync(try await self.makeClient().getSelf()) { error in
            guard case NewAPIError.apiFailure(let msg) = error else {
                return XCTFail("expected apiFailure, got \(error)")
            }
            XCTAssertEqual(msg, "access token invalid")
        }
    }
}

func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ errorHandler: (_ error: Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail("Expected throw — \(message())", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
