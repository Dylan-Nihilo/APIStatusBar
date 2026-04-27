import XCTest
@testable import APIStatusBar

@MainActor
final class ProbePollerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        URLProtocolStub.reset()
    }

    override func tearDown() {
        URLProtocolStub.reset()
        super.tearDown()
    }

    func test_refresh_decodesStringMonitorIDsAndChoosesBestUpChannel() async throws {
        URLProtocolStub.handler = { request in
            let body = """
            {
              "success": true,
              "generated_at": "2026-04-27 10:10:08",
              "data": {
                "groups": [
                  {"name": "slow", "monitors": [
                    {"id": "slow_channel", "name": "slow_channel", "group": "slow", "tag": "", "models": "claude", "priority": 0}
                  ]},
                  {"name": "fast", "monitors": [
                    {"id": "fast_channel", "name": "fast_channel", "group": "fast", "tag": "", "models": "claude", "priority": 0}
                  ]},
                  {"name": "down", "monitors": [
                    {"id": "down_channel", "name": "down_channel", "group": "down", "tag": "", "models": "claude", "priority": 0}
                  ]}
                ],
                "heartbeatList": {
                  "slow_channel": [{"status": 1, "time": "2026-04-27 10:05:01", "ping": 2000, "msg": ""}],
                  "fast_channel": [{"status": 1, "time": "2026-04-27 10:05:01", "ping": 120, "msg": ""}],
                  "down_channel": [{"status": 0, "time": "2026-04-27 10:05:01", "ping": 20, "msg": ""}]
                },
                "uptimeList": {
                  "fast_channel_24": 0.99,
                  "slow_channel_24": 0.98,
                  "down_channel_24": 0.0
                }
              }
            }
            """.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!,
                                            statusCode: 200,
                                            httpVersion: nil,
                                            headerFields: nil)!
            return (response, body)
        }

        let poller = ProbePoller(intervalSeconds: 30)
        let client = KaizoStatusClient(baseURL: URL(string: "https://status.example.com")!,
                                       session: URLProtocolStub.session())
        poller.replaceClient(client)
        await poller.refresh()

        XCTAssertEqual(URLProtocolStub.lastRequest?.url?.path, "/status/status.json")
        XCTAssertEqual(poller.primaryChannelName, "fast_channel")
        XCTAssertEqual(poller.snapshot?.latencyMS, 120)
        XCTAssertEqual(poller.snapshot?.health, .degraded)
        XCTAssertEqual(poller.uptime24h, 0.99)
        XCTAssertEqual(poller.history.map(\.latencyMS), [120])
    }
}
