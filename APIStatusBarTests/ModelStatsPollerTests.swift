import XCTest
@testable import APIStatusBar

@MainActor
final class ModelStatsPollerTests: XCTestCase {
    private func client() -> NewAPIClient {
        NewAPIClient(baseURL: URL(string: "https://x.local")!,
                     accessToken: "t",
                     userID: 1,
                     session: URLProtocolStub.session())
    }

    private func row(date: Date,
                     model: String,
                     quota: Int,
                     count: Int = 1) -> QuotaDataRow {
        QuotaDataRow(modelName: model,
                     createdAt: Int64(date.timeIntervalSince1970),
                     count: count,
                     quota: quota,
                     tokenUsed: 0)
    }

    private func startOfDay(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d
        return Calendar.current.date(from: c)!
    }

    func test_aggregate_emptyRows_yieldsEmptyDailyBuckets() {
        let poller = ModelStatsPoller(client: client(), intervalSeconds: 300)
        _ = poller.aggregate(rows: [])
        XCTAssertTrue(poller.dailyBuckets.isEmpty)
    }

    func test_aggregate_sumsByDay() {
        let poller = ModelStatsPoller(client: client(), intervalSeconds: 300)
        let day = startOfDay(2026, 4, 20)
        _ = poller.aggregate(rows: [
            row(date: day, model: "claude-3-opus", quota: 500_000),
            row(date: day.addingTimeInterval(3600), model: "gpt-4o", quota: 250_000),
        ])
        let bucket = poller.dailyBuckets[day]!
        XCTAssertEqual(bucket.quotaRaw, 750_000)
        XCTAssertEqual(bucket.usd, 1.5, accuracy: 1e-9)
        XCTAssertEqual(bucket.requestCount, 2)
    }

    func test_aggregate_topModels_sortedByQuotaDescThenAlpha() {
        let poller = ModelStatsPoller(client: client(), intervalSeconds: 300)
        let day = startOfDay(2026, 4, 20)
        _ = poller.aggregate(rows: [
            row(date: day, model: "gpt-4o", quota: 100),
            row(date: day, model: "claude-3-opus", quota: 100),
            row(date: day, model: "deepseek-chat", quota: 200),
            row(date: day, model: "qwen3-72b", quota: 50),
        ])
        let bucket = poller.dailyBuckets[day]!
        XCTAssertEqual(bucket.topModels, ["deepseek-chat", "claude-3-opus", "gpt-4o"])
    }

    func test_aggregate_separatesDays() {
        let poller = ModelStatsPoller(client: client(), intervalSeconds: 300)
        let d1 = startOfDay(2026, 4, 20)
        let d2 = startOfDay(2026, 4, 21)
        _ = poller.aggregate(rows: [
            row(date: d1, model: "claude", quota: 100_000),
            row(date: d2, model: "claude", quota: 200_000),
        ])
        XCTAssertEqual(poller.dailyBuckets[d1]?.quotaRaw, 100_000)
        XCTAssertEqual(poller.dailyBuckets[d2]?.quotaRaw, 200_000)
    }
}
