# APIStatusBar M2 — Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the v0.2 dashboard window — opened from popover, showing account header, 30-day usage heatmap, and Top Models bar chart, all driven by the existing `ModelStatsPoller` data.

**Architecture:** Single new `WindowGroup(id: "dashboard")` SwiftUI scene with three vertically stacked `.regularMaterial` cards inside a `ScrollView`. Reuses `ModelStatsPoller` — extends it with a `dailyBuckets` published output derived from the same `/api/data/self` rows already being fetched, so no new network polling is introduced. UI components are kept small and focused (one card per file) for easy testing and incremental change.

**Tech Stack:** Swift 6.0 · SwiftUI · macOS 26.0+ · XCTest · existing `NewAPIClient` / `ModelStatsPoller` / `ProviderMapping` infrastructure.

**Spec:** [`docs/superpowers/specs/2026-04-26-apistatusbar-m2-dashboard-design.md`](../specs/2026-04-26-apistatusbar-m2-dashboard-design.md)

---

## File Structure

```
APIStatusBar/
├─ APIStatusBarApp.swift                      # +WindowGroup(id: "dashboard")
├─ Core/
│  ├─ ModelStatsPoller.swift                  # +DayBucket, +dailyBuckets, +daily aggregation
│  ├─ HeatmapBucket.swift                     # NEW - bucket math (USD → 0..4)
│  └─ HeatmapGrid.swift                       # NEW - cell-to-date mapping for 5×7 grid
├─ UI/
│  ├─ PopoverView.swift                       # +chart.bar.xaxis button → openWindow("dashboard")
│  └─ Dashboard/
│     ├─ DashboardView.swift                  # NEW - entry point, ScrollView + 3 cards
│     ├─ AccountCard.swift                    # NEW - 4-row LabeledContent
│     ├─ HeatmapView.swift                    # NEW - 5×7 Grid, weekday labels, legend
│     └─ TopModelsCard.swift                  # NEW - 5-row progress list

APIStatusBarTests/
├─ ModelStatsPollerTests.swift                # NEW - daily aggregation tests
├─ HeatmapBucketTests.swift                   # NEW - boundary tests
└─ HeatmapGridTests.swift                     # NEW - date↔cell mapping tests
```

---

## Phase 1 — Data Extensions (TDD)

### Task 1.1: Add `DayBucket` model + extend `ModelStatsPoller.aggregate` to compute per-day rollup

**Files:**
- Modify: `APIStatusBar/Core/ModelStatsPoller.swift`
- Create: `APIStatusBarTests/ModelStatsPollerTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `APIStatusBarTests/ModelStatsPollerTests.swift`:

```swift
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

    /// Helper: build a QuotaDataRow at a specific date, with given quota and count.
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
            row(date: day, model: "claude-3-opus", quota: 500_000),  // $1.00
            row(date: day.addingTimeInterval(3600), model: "gpt-4o", quota: 250_000),  // $0.50
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
            row(date: day, model: "claude-3-opus", quota: 100),  // tie with gpt-4o
            row(date: day, model: "deepseek-chat", quota: 200),  // largest
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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodegen generate && xcodebuild -project APIStatusBar.xcodeproj -scheme APIStatusBar -destination 'platform=macOS' test 2>&1 | grep -E "error:|FAILED" | tail -5
```

Expected: compile errors — `DayBucket` not found, `dailyBuckets` not a property, `aggregate(rows:)` is private and returns `[ProviderUsage]` not exposing daily output.

- [ ] **Step 3: Modify `ModelStatsPoller.swift`**

In `APIStatusBar/Core/ModelStatsPoller.swift`:

a) Add the `DayBucket` model near the top (alongside `ProviderUsage`) — at the END of `ProviderMapping.swift` is also acceptable since it's data-only:

```swift
/// Per-day rollup of usage for the heatmap and account "today" stat.
struct DayBucket: Equatable {
    /// Local-timezone start-of-day.
    let date: Date
    let quotaRaw: Int
    let usd: Double
    let requestCount: Int
    /// Top 3 raw model names ordered by quota desc, ties broken alphabetically asc.
    let topModels: [String]
}
```

b) In the `ModelStatsPoller` class body, add a published property next to `topProviders`:

```swift
@Published private(set) var dailyBuckets: [Date: DayBucket] = [:]
```

c) Take a `quotaPerUnit: Int` dependency so daily USD math doesn't need a separate formatter. Modify `init`:

```swift
private let quotaPerUnit: Int

init(client: NewAPIClient, intervalSeconds: Int = 300, lookbackDays: Int = 30,
     quotaPerUnit: Int = 500_000) {
    self.client = client
    self.intervalSeconds = intervalSeconds
    self.lookbackDays = lookbackDays
    self.quotaPerUnit = quotaPerUnit
}
```

d) Make `aggregate(rows:)` populate both outputs and become non-private. Rename the existing private one if necessary, or change its access:

```swift
/// Roll per-(model, hour) rows into per-provider AND per-day rollups.
/// Mutates `topProviders` and `dailyBuckets` in place. Returns the
/// per-provider list for callers that already use it; the per-day
/// rollup is read via the `dailyBuckets` published property.
@discardableResult
func aggregate(rows: [QuotaDataRow]) -> [ProviderUsage] {
    // --- per-provider rollup (existing behavior) ---
    var byProvider: [String: (models: Set<String>, quota: Int, count: Int)] = [:]
    for row in rows {
        guard let provider = ProviderMapping.provider(for: row.modelName) else { continue }
        var bucket = byProvider[provider] ?? (models: [], quota: 0, count: 0)
        bucket.models.insert(row.modelName)
        bucket.quota += row.quota
        bucket.count += row.count
        byProvider[provider] = bucket
    }
    let providers = byProvider
        .map { ProviderUsage(providerAsset: $0.key,
                              modelNames: Array($0.value.models).sorted(),
                              quotaRaw: $0.value.quota,
                              requestCount: $0.value.count) }
        .sorted { $0.quotaRaw > $1.quotaRaw }
    self.topProviders = providers

    // --- per-day rollup (new) ---
    var byDay: [Date: (models: [String: Int], quota: Int, count: Int)] = [:]
    let cal = Calendar.current
    for row in rows {
        let rowDate = Date(timeIntervalSince1970: TimeInterval(row.createdAt))
        let day = cal.startOfDay(for: rowDate)
        var bucket = byDay[day] ?? (models: [:], quota: 0, count: 0)
        bucket.models[row.modelName, default: 0] += row.quota
        bucket.quota += row.quota
        bucket.count += row.count
        byDay[day] = bucket
    }
    var newDailyBuckets: [Date: DayBucket] = [:]
    for (day, agg) in byDay {
        let topModels = agg.models
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            .prefix(3)
            .map(\.key)
        newDailyBuckets[day] = DayBucket(
            date: day,
            quotaRaw: agg.quota,
            usd: Double(agg.quota) / Double(quotaPerUnit),
            requestCount: agg.count,
            topModels: Array(topModels)
        )
    }
    self.dailyBuckets = newDailyBuckets

    return providers
}
```

e) Update `refresh()` to use the new aggregation (which already mutates state); the existing `topProviders = aggregate(rows: rows)` line should be replaced with a plain call:

```swift
func refresh() async {
    let now = Date()
    let start = Calendar.current.date(byAdding: .day,
                                      value: -lookbackDays,
                                      to: now) ?? now
    do {
        let rows = try await client.getDataSelf(start: start, end: now)
        aggregate(rows: rows)
        lastError = nil
    } catch {
        lastError = error
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild -project APIStatusBar.xcodeproj -scheme APIStatusBar -destination 'platform=macOS' test 2>&1 | grep -E "Executed [0-9]+ tests, with" | tail -2
```

Expected: 4 new ModelStatsPoller tests pass; total 20 tests green.

- [ ] **Step 5: Wire `quotaPerUnit` from `AppSettings` in `APIStatusBarApp`**

In `APIStatusBar/APIStatusBarApp.swift`, replace the `_modelStats` initializer line in `init()`:

```swift
_modelStats = StateObject(wrappedValue: ModelStatsPoller(client: client,
                                                          intervalSeconds: 300,
                                                          quotaPerUnit: settings.quotaPerUnit))
```

(Existing `_modelStats = StateObject(wrappedValue: ModelStatsPoller(client: client, intervalSeconds: 300))` becomes the above with explicit `quotaPerUnit`.)

- [ ] **Step 6: Build to confirm no regression**

```bash
xcodebuild -project APIStatusBar.xcodeproj -scheme APIStatusBar -configuration Debug -destination 'platform=macOS' build 2>&1 | grep -E "error:|FAILED|SUCCEEDED" | grep -v appintents | tail -3
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add APIStatusBar/Core/ModelStatsPoller.swift APIStatusBar/APIStatusBarApp.swift APIStatusBarTests/ModelStatsPollerTests.swift
git commit -m "feat(stats): expose per-day rollup as dailyBuckets

ModelStatsPoller.aggregate now produces both topProviders (existing) and
dailyBuckets (new) from the same /api/data/self response. DayBucket carries
date / quota / USD / request count / top-3 models per day, ready to feed
the dashboard's heatmap and 'today' stat. quotaPerUnit dependency added so
USD math happens once at aggregation time. 4 new TDD tests cover empty
input, daily summing, top-models tiebreaks, and day separation."
```

---

### Task 1.2: Add `HeatmapBucket` (USD → 0..4)

**Files:**
- Create: `APIStatusBar/Core/HeatmapBucket.swift`
- Create: `APIStatusBarTests/HeatmapBucketTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `APIStatusBarTests/HeatmapBucketTests.swift`:

```swift
import XCTest
@testable import APIStatusBar

final class HeatmapBucketTests: XCTestCase {
    func test_zero_isEmptyBucket() {
        XCTAssertEqual(HeatmapBucket.bucket(forUSD: 0), 0)
    }

    func test_belowFirstThreshold_isEmpty() {
        XCTAssertEqual(HeatmapBucket.bucket(forUSD: 0.005), 0)
    }

    func test_atFirstThreshold_isBucket1() {
        XCTAssertEqual(HeatmapBucket.bucket(forUSD: 0.01), 1)
    }

    func test_belowOneDollar_isBucket1() {
        XCTAssertEqual(HeatmapBucket.bucket(forUSD: 0.99), 1)
    }

    func test_atOneDollar_isBucket2() {
        XCTAssertEqual(HeatmapBucket.bucket(forUSD: 1.0), 2)
    }

    func test_belowFive_isBucket2() {
        XCTAssertEqual(HeatmapBucket.bucket(forUSD: 4.99), 2)
    }

    func test_atFive_isBucket3() {
        XCTAssertEqual(HeatmapBucket.bucket(forUSD: 5.0), 3)
    }

    func test_belowTwenty_isBucket3() {
        XCTAssertEqual(HeatmapBucket.bucket(forUSD: 19.99), 3)
    }

    func test_atTwenty_isBucket4() {
        XCTAssertEqual(HeatmapBucket.bucket(forUSD: 20.0), 4)
    }

    func test_largeValue_isBucket4() {
        XCTAssertEqual(HeatmapBucket.bucket(forUSD: 9999), 4)
    }

    func test_negativeIsTreatedAsEmpty() {
        XCTAssertEqual(HeatmapBucket.bucket(forUSD: -1), 0)
    }
}
```

- [ ] **Step 2: Run, confirm fail**

```bash
xcodebuild -project APIStatusBar.xcodeproj -scheme APIStatusBar -destination 'platform=macOS' test 2>&1 | grep -E "error:|FAILED" | tail -3
```

Expected: `cannot find 'HeatmapBucket' in scope`.

- [ ] **Step 3: Implement**

Create `APIStatusBar/Core/HeatmapBucket.swift`:

```swift
import Foundation

/// Maps a USD value to a heatmap bucket index 0…4 using half-open intervals.
/// Bucket 0 = empty / no usage. Buckets 1–4 = increasing intensity.
/// Edges are tunable for personal scale (see spec §6).
enum HeatmapBucket {
    /// `bucketEdges[i]` is the lower bound of bucket `i+1`. So a value `v`
    /// belongs to bucket `i+1` when `bucketEdges[i] ≤ v < bucketEdges[i+1]`,
    /// or to bucket `bucketEdges.count` (the topmost) when `v ≥ bucketEdges.last`.
    static let bucketEdges: [Double] = [0.01, 1.0, 5.0, 20.0]

    /// Returns 0…bucketEdges.count (= 4 by default).
    static func bucket(forUSD usd: Double) -> Int {
        guard usd > 0 else { return 0 }
        var index = 0
        for edge in bucketEdges {
            if usd < edge { return index }
            index += 1
        }
        return index
    }
}
```

- [ ] **Step 4: Run, confirm pass**

```bash
xcodegen generate && xcodebuild -project APIStatusBar.xcodeproj -scheme APIStatusBar -destination 'platform=macOS' test 2>&1 | grep -E "Executed [0-9]+ tests, with" | tail -2
```

Expected: 11 new HeatmapBucket tests pass; total 31 tests green.

- [ ] **Step 5: Commit**

```bash
git add APIStatusBar/Core/HeatmapBucket.swift APIStatusBarTests/HeatmapBucketTests.swift
git commit -m "feat(heatmap): bucket math for USD → intensity 0..4

Half-open intervals [0, 0.01), [0.01, 1), [1, 5), [5, 20), [20, ∞)
mapped to buckets 0..4. Edges tunable via bucketEdges constant. 11 TDD
tests cover boundary edges and zero/negative inputs."
```

---

### Task 1.3: Add `HeatmapGrid` (date ↔ 5×7 cell)

**Files:**
- Create: `APIStatusBar/Core/HeatmapGrid.swift`
- Create: `APIStatusBarTests/HeatmapGridTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `APIStatusBarTests/HeatmapGridTests.swift`:

```swift
import XCTest
@testable import APIStatusBar

final class HeatmapGridTests: XCTestCase {
    /// Helper: produce a Date at local-tz start-of-day.
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d
        return Calendar.current.date(from: c)!
    }

    func test_today_isAt_lastColumn_andCorrectRow() {
        // Saturday 2026-04-25 → ISO weekday 6 → row 5 (Mon=0..Sun=6)
        let today = date(2026, 4, 25)
        let cell = HeatmapGrid.cell(for: today, today: today)
        XCTAssertEqual(cell, HeatmapGrid.Cell(column: 4, row: 5))
    }

    func test_yesterday_isAt_lastColumn_oneRowUp() {
        // Friday 2026-04-24 → row 4
        let today = date(2026, 4, 25)
        let cell = HeatmapGrid.cell(for: date(2026, 4, 24), today: today)
        XCTAssertEqual(cell, HeatmapGrid.Cell(column: 4, row: 4))
    }

    func test_dayInPriorWeek_isAt_priorColumn() {
        // Sunday 2026-04-19 → row 6 (Sunday is the LAST day of ISO week, Mon-first)
        // Today is Sat 2026-04-25 → today's week starts Mon 2026-04-20
        // → 2026-04-19 is the prior week → column 3
        let today = date(2026, 4, 25)
        let cell = HeatmapGrid.cell(for: date(2026, 4, 19), today: today)
        XCTAssertEqual(cell, HeatmapGrid.Cell(column: 3, row: 6))
    }

    func test_oldestVisibleDay_isInColumnZero() {
        // Today Sat 2026-04-25, today's week starts Mon 2026-04-20.
        // Column 0 = 4 weeks before today's week = Mon 2026-03-23.
        let today = date(2026, 4, 25)
        let cell = HeatmapGrid.cell(for: date(2026, 3, 23), today: today)
        XCTAssertEqual(cell, HeatmapGrid.Cell(column: 0, row: 0))
    }

    func test_dayBeforeOldestVisible_returnsNil() {
        let today = date(2026, 4, 25)
        let cell = HeatmapGrid.cell(for: date(2026, 3, 22), today: today)
        XCTAssertNil(cell)
    }

    func test_futureDay_returnsNil() {
        let today = date(2026, 4, 25)
        let cell = HeatmapGrid.cell(for: date(2026, 4, 26), today: today)
        XCTAssertNil(cell)
    }

    func test_dateForCell_inverse_mapping() {
        let today = date(2026, 4, 25)
        // (column=4, row=5) should map back to today (Sat 2026-04-25).
        XCTAssertEqual(HeatmapGrid.date(forCell: HeatmapGrid.Cell(column: 4, row: 5), today: today),
                       today)
        // (column=0, row=0) → Mon 2026-03-23.
        XCTAssertEqual(HeatmapGrid.date(forCell: HeatmapGrid.Cell(column: 0, row: 0), today: today),
                       date(2026, 3, 23))
    }

    func test_allCellDatesCovered_inOrder() {
        let today = date(2026, 4, 25)
        let dates = HeatmapGrid.allCells.map {
            HeatmapGrid.date(forCell: $0, today: today)
        }
        XCTAssertEqual(dates.count, 35)
        XCTAssertEqual(dates.first, date(2026, 3, 23))
        XCTAssertEqual(dates.last, date(2026, 4, 26))  // Sun 2026-04-26 (today is Sat, this is the day after; allCells includes future days that the consumer must filter visually)
    }
}
```

- [ ] **Step 2: Run, confirm fail**

Expected: `cannot find 'HeatmapGrid' in scope`.

- [ ] **Step 3: Implement**

Create `APIStatusBar/Core/HeatmapGrid.swift`:

```swift
import Foundation

/// 5×7 grid mapping for the dashboard heatmap.
/// - Columns: 0…4. Column 4 holds today's ISO week; column 0 is 4 weeks earlier.
/// - Rows: 0…6. Row 0 = Monday … Row 6 = Sunday.
/// - The grid renders all 35 cells; cells whose mapped date falls outside the
///   30-day window OR after today are rendered gray by the view layer.
enum HeatmapGrid {
    struct Cell: Equatable, Hashable {
        let column: Int
        let row: Int
    }

    /// All 35 (column, row) pairs in row-major order.
    static let allCells: [Cell] = (0..<7).flatMap { row in
        (0..<5).map { col in Cell(column: col, row: row) }
    }

    /// Maps a calendar date to a cell, or nil if the date is outside the
    /// visible 5-week window (older than the Monday of the leftmost column,
    /// or strictly after today).
    static func cell(for date: Date, today: Date) -> Cell? {
        let cal = mondayFirstCalendar
        let dStart = cal.startOfDay(for: date)
        let tStart = cal.startOfDay(for: today)
        if dStart > tStart { return nil }

        let leftmostMonday = mondayOfLeftmostColumn(today: today)
        if dStart < leftmostMonday { return nil }

        // Column = how many weeks after leftmostMonday the date's week is.
        let dateWeekStart = cal.dateInterval(of: .weekOfYear, for: dStart)!.start
        let weekDelta = cal.dateComponents([.weekOfYear],
                                            from: leftmostMonday,
                                            to: dateWeekStart).weekOfYear ?? 0
        let column = weekDelta

        // Row 0 = Monday … Row 6 = Sunday.
        let weekday = cal.component(.weekday, from: dStart)  // 1=Sun..7=Sat in Gregorian
        let row = (weekday + 5) % 7  // 0=Mon..6=Sun

        return Cell(column: column, row: row)
    }

    /// Inverse mapping: given a (column, row), return the date that cell represents.
    /// Caller must filter cells whose result falls outside the 30-day window or in the future.
    static func date(forCell cell: Cell, today: Date) -> Date {
        let cal = mondayFirstCalendar
        let leftmost = mondayOfLeftmostColumn(today: today)
        let weekStart = cal.date(byAdding: .weekOfYear, value: cell.column, to: leftmost)!
        return cal.date(byAdding: .day, value: cell.row, to: weekStart)!
    }

    // MARK: - Internal

    private static var mondayFirstCalendar: Calendar {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2  // Monday
        return cal
    }

    private static func mondayOfLeftmostColumn(today: Date) -> Date {
        let cal = mondayFirstCalendar
        let todayWeekStart = cal.dateInterval(of: .weekOfYear, for: today)!.start
        return cal.date(byAdding: .weekOfYear, value: -4, to: todayWeekStart)!
    }
}
```

- [ ] **Step 4: Run, confirm pass**

```bash
xcodegen generate && xcodebuild -project APIStatusBar.xcodeproj -scheme APIStatusBar -destination 'platform=macOS' test 2>&1 | grep -E "Executed [0-9]+ tests, with" | tail -2
```

Expected: 8 new HeatmapGrid tests pass; total 39 tests green.

- [ ] **Step 5: Commit**

```bash
git add APIStatusBar/Core/HeatmapGrid.swift APIStatusBarTests/HeatmapGridTests.swift
git commit -m "feat(heatmap): 5x7 grid date mapping (Mon-first)

HeatmapGrid converts dates ↔ cells for the dashboard's 5-week heatmap.
Column 4 = current ISO week, column 0 = 4 weeks earlier; row 0..6 =
Monday..Sunday. cell(for:today:) returns nil for future or out-of-window
dates so the view layer can render them as empty placeholders. 8 TDD
tests cover today/yesterday/oldest-visible/out-of-window/inverse mapping."
```

---

## Phase 2 — UI Components

### Task 2.1: `AccountCard.swift`

**Files:**
- Create: `APIStatusBar/UI/Dashboard/AccountCard.swift`

- [ ] **Step 1: Create the directory**

```bash
mkdir -p APIStatusBar/UI/Dashboard
```

- [ ] **Step 2: Write the view**

Create `APIStatusBar/UI/Dashboard/AccountCard.swift`:

```swift
import SwiftUI

/// Top of dashboard: 4-row 1-column LabeledContent grid showing account-level
/// numbers. All numeric values use .contentTransition(.numericText()) so
/// digit changes roll smoothly when polled data updates.
struct AccountCard: View {
    @ObservedObject var poller: QuotaPoller
    @ObservedObject var modelStats: ModelStatsPoller
    @ObservedObject var settings: AppSettings

    private var formatter: QuotaFormatter {
        QuotaFormatter(quotaPerUnit: settings.quotaPerUnit)
    }

    var body: some View {
        VStack(spacing: 8) {
            row("剩余", value: remainingText)
            row("今日", value: todayText)
            row("总消耗", value: usedText)
            row("请求次数", value: requestText)
        }
        .font(.callout)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func row(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 12)
            Text(value)
                .monospacedDigit()
                .lineLimit(1)
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
        }
        .frame(maxWidth: .infinity)
    }

    private var remainingText: String {
        guard let s = poller.snapshot else { return "—" }
        return formatter.displayString(usd: formatter.usd(fromRaw: s.quotaRaw))
    }

    private var todayText: String {
        let today = Calendar.current.startOfDay(for: Date())
        guard let bucket = modelStats.dailyBuckets[today] else { return "$0.00" }
        return formatter.displayString(usd: bucket.usd)
    }

    private var usedText: String {
        guard let s = poller.snapshot else { return "—" }
        return formatter.displayString(usd: formatter.usd(fromRaw: s.usedQuotaRaw))
    }

    private var requestText: String {
        guard let s = poller.snapshot else { return "—" }
        return s.requestCount.formatted()
    }
}
```

- [ ] **Step 3: Build to confirm it compiles in isolation**

```bash
xcodegen generate && xcodebuild -project APIStatusBar.xcodeproj -scheme APIStatusBar -configuration Debug -destination 'platform=macOS' build 2>&1 | grep -E "error:|FAILED|SUCCEEDED" | grep -v appintents | tail -3
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add APIStatusBar/UI/Dashboard/AccountCard.swift
git commit -m "feat(dashboard): AccountCard — 4-row balance/today/used/requests"
```

---

### Task 2.2: `HeatmapView.swift`

**Files:**
- Create: `APIStatusBar/UI/Dashboard/HeatmapView.swift`

- [ ] **Step 1: Write the view**

Create `APIStatusBar/UI/Dashboard/HeatmapView.swift`:

```swift
import SwiftUI

/// 5×7 daily-usage heatmap. Each cell's color intensity reflects the USD
/// spent that day; cells outside the 30-day window or in the future render
/// in `Theme.heatmapEmpty`. Today's cell carries an inner stroke so it's
/// always findable regardless of fill bucket.
struct HeatmapView: View {
    let dailyBuckets: [Date: DayBucket]
    let today: Date

    private let cellSize: CGFloat = 14
    private let cellSpacing: CGFloat = 2
    private let weekdayLabels = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("用量热力图（最近 30 天）")
                    .font(.headline)
                Spacer()
                legend
            }

            HStack(alignment: .top, spacing: 8) {
                weekdayColumn
                grid
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var weekdayColumn: some View {
        VStack(spacing: cellSpacing) {
            ForEach(0..<7, id: \.self) { row in
                Text(weekdayLabels[row])
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 14, height: cellSize)
            }
        }
    }

    private var grid: some View {
        VStack(spacing: cellSpacing) {
            ForEach(0..<7, id: \.self) { row in
                HStack(spacing: cellSpacing) {
                    ForEach(0..<5, id: \.self) { col in
                        cell(at: HeatmapGrid.Cell(column: col, row: row))
                    }
                }
            }
        }
    }

    private func cell(at cellPos: HeatmapGrid.Cell) -> some View {
        let cellDate = HeatmapGrid.date(forCell: cellPos, today: today)
        let isWithinWindow = HeatmapGrid.cell(for: cellDate, today: today) != nil
        let bucket = isWithinWindow
            ? dailyBuckets[Calendar.current.startOfDay(for: cellDate)]
            : nil
        let bucketIndex = bucket.map { HeatmapBucket.bucket(forUSD: $0.usd) } ?? 0
        let isToday = Calendar.current.isDate(cellDate, inSameDayAs: today)

        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(fillColor(bucket: bucketIndex, withinWindow: isWithinWindow))
            .frame(width: cellSize, height: cellSize)
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(.white.opacity(0.7), lineWidth: 1)
                }
            }
            .help(tooltip(date: cellDate, bucket: bucket, withinWindow: isWithinWindow))
    }

    private func fillColor(bucket: Int, withinWindow: Bool) -> Color {
        guard withinWindow, bucket > 0 else { return Theme.heatmapEmpty }
        let alpha = Theme.heatmapAlphas[bucket]
        return Theme.accent.opacity(alpha)
    }

    private func tooltip(date: Date, bucket: DayBucket?, withinWindow: Bool) -> String {
        let f = DateFormatter()
        f.dateFormat = "M月d日"
        f.locale = Locale(identifier: "zh-Hans")
        let dateStr = f.string(from: date)
        guard withinWindow else { return "\(dateStr) · 窗口外" }
        guard let b = bucket else { return "\(dateStr) · 无用量" }
        return String(format: "%@ · $%.2f · %d 次请求", dateStr, b.usd, b.requestCount)
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Text("少").font(.caption2).foregroundStyle(.tertiary)
            ForEach(1..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Theme.accent.opacity(Theme.heatmapAlphas[level]))
                    .frame(width: 10, height: 10)
            }
            Text("多").font(.caption2).foregroundStyle(.tertiary)
        }
    }
}
```

- [ ] **Step 2: Build to confirm**

```bash
xcodebuild -project APIStatusBar.xcodeproj -scheme APIStatusBar -configuration Debug -destination 'platform=macOS' build 2>&1 | grep -E "error:|FAILED|SUCCEEDED" | grep -v appintents | tail -3
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add APIStatusBar/UI/Dashboard/HeatmapView.swift
git commit -m "feat(dashboard): HeatmapView — 5×7 grid, weekday labels, legend, tooltip

Cells fill via Theme.accent with 5-step alpha mapped from USD buckets;
out-of-window cells stay gray; today's cell carries a 1pt white inner
stroke so it's always findable regardless of fill bucket. Hover tooltip
formats Chinese date + USD + request count."
```

---

### Task 2.3: `TopModelsCard.swift`

**Files:**
- Create: `APIStatusBar/UI/Dashboard/TopModelsCard.swift`

- [ ] **Step 1: Write the view**

Create `APIStatusBar/UI/Dashboard/TopModelsCard.swift`:

```swift
import SwiftUI

/// 5-row Top Models card. Each row: provider icon · name · proportional
/// progress bar · USD · percent. Bars width-animate from 0 to target on
/// first appear via .spring(response: 0.5).
struct TopModelsCard: View {
    @ObservedObject var modelStats: ModelStatsPoller
    @ObservedObject var settings: AppSettings

    private var formatter: QuotaFormatter {
        QuotaFormatter(quotaPerUnit: settings.quotaPerUnit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Top Models（最近 30 天）")
                .font(.headline)

            if topProviders.isEmpty {
                Text("暂无用量数据")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                ForEach(topProviders) { provider in
                    row(for: provider)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.spring(response: 0.5), value: topProviders)
    }

    private var topProviders: [ProviderUsage] {
        Array(modelStats.topProviders.prefix(5))
    }

    private func row(for provider: ProviderUsage) -> some View {
        let usd = formatter.usd(fromRaw: provider.quotaRaw)
        let total = topProviders.reduce(0) { $0 + Double($1.quotaRaw) }
        let percent = total > 0 ? Double(provider.quotaRaw) / total : 0
        let leadFraction = leaderFraction(provider: provider)
        return HStack(spacing: 10) {
            Image(provider.providerAsset)
                .resizable()
                .renderingMode(.original)
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
            Text(provider.providerAsset.capitalized)
                .font(.callout)
                .lineLimit(1)
                .frame(minWidth: 64, alignment: .leading)
            ProgressBar(fraction: leadFraction)
                .frame(height: 8)
            Text(formatter.displayString(usd: usd))
                .font(.callout)
                .monospacedDigit()
                .frame(minWidth: 56, alignment: .trailing)
            Text(String(format: "%.1f%%", percent * 100))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 44, alignment: .trailing)
        }
    }

    /// Bar length is relative to the leader (top-1) so the leader fills the
    /// track. Subsequent rows are proportional to the leader's quota — easier
    /// to read than absolute %.
    private func leaderFraction(provider: ProviderUsage) -> Double {
        guard let leader = topProviders.first, leader.quotaRaw > 0 else { return 0 }
        return Double(provider.quotaRaw) / Double(leader.quotaRaw)
    }
}

private struct ProgressBar: View {
    let fraction: Double  // 0…1

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.heatmapEmpty)
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
    }
}
```

- [ ] **Step 2: Build to confirm**

```bash
xcodebuild -project APIStatusBar.xcodeproj -scheme APIStatusBar -configuration Debug -destination 'platform=macOS' build 2>&1 | grep -E "error:|FAILED|SUCCEEDED" | grep -v appintents | tail -3
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add APIStatusBar/UI/Dashboard/TopModelsCard.swift
git commit -m "feat(dashboard): TopModelsCard — top 5 providers with proportional bars

Each row: 24pt provider icon, name (capitalized), Capsule-track progress
bar sized relative to the leader's quota, USD figure, percent of top-5
total. .spring(response: 0.5) animates rebalancing when usage shifts."
```

---

### Task 2.4: `DashboardView.swift` (assembly)

**Files:**
- Create: `APIStatusBar/UI/Dashboard/DashboardView.swift`

- [ ] **Step 1: Write the view**

Create `APIStatusBar/UI/Dashboard/DashboardView.swift`:

```swift
import SwiftUI

/// Single-window dashboard: account header + 30-day heatmap + Top Models.
/// Cards fade-and-slide in on first appear with an 80ms stagger.
struct DashboardView: View {
    @ObservedObject var poller: QuotaPoller
    @ObservedObject var modelStats: ModelStatsPoller
    @ObservedObject var settings: AppSettings

    @State private var hasAppeared = false
    @State private var refreshSpin = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                AccountCard(poller: poller, modelStats: modelStats, settings: settings)
                    .modifier(StaggeredAppear(index: 0, hasAppeared: hasAppeared))

                HeatmapView(dailyBuckets: modelStats.dailyBuckets, today: Date())
                    .modifier(StaggeredAppear(index: 1, hasAppeared: hasAppeared))

                TopModelsCard(modelStats: modelStats, settings: settings)
                    .modifier(StaggeredAppear(index: 2, hasAppeared: hasAppeared))
            }
            .padding(16)
        }
        .frame(width: 480, height: 380)
        .navigationTitle("用量仪表板")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    refreshSpin.toggle()
                    Task {
                        await poller.refresh()
                        await modelStats.refresh()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(refreshSpin ? 360 : 0))
                        .animation(.easeOut(duration: 0.6), value: refreshSpin)
                }
                .help("刷新")
            }
        }
        .onAppear {
            withAnimation { hasAppeared = true }
            // First open after launch: kick a refresh if we have nothing yet.
            if modelStats.dailyBuckets.isEmpty {
                Task { await modelStats.refresh() }
            }
        }
    }
}

/// Slide-up + fade entrance with staggered delay per card.
private struct StaggeredAppear: ViewModifier {
    let index: Int
    let hasAppeared: Bool

    func body(content: Content) -> some View {
        content
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 8)
            .animation(
                .smooth(duration: 0.4).delay(Double(index) * 0.08),
                value: hasAppeared
            )
    }
}
```

- [ ] **Step 2: Build to confirm**

```bash
xcodebuild -project APIStatusBar.xcodeproj -scheme APIStatusBar -configuration Debug -destination 'platform=macOS' build 2>&1 | grep -E "error:|FAILED|SUCCEEDED" | grep -v appintents | tail -3
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add APIStatusBar/UI/Dashboard/DashboardView.swift
git commit -m "feat(dashboard): DashboardView assembly with staggered entrance

3-card vertical layout in a ScrollView; each card slides up 8pt + fades
in with an 80ms stagger via the StaggeredAppear modifier. Toolbar refresh
button rotates 360° on tap. First open after launch triggers a refresh
when dailyBuckets is empty."
```

---

## Phase 3 — Wiring

### Task 3.1: Add `WindowGroup(id: "dashboard")` to `APIStatusBarApp`

**Files:**
- Modify: `APIStatusBar/APIStatusBarApp.swift`

- [ ] **Step 1: Add the WindowGroup scene**

In `APIStatusBar/APIStatusBarApp.swift`, inside `var body: some Scene { ... }`, append a new scene after the existing `Settings { ... }` block:

```swift
        WindowGroup(id: "dashboard") {
            DashboardView(poller: poller, modelStats: modelStats, settings: settings)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 480, height: 380)
        .commands {
            CommandGroup(replacing: .newItem) { }  // suppress File > New Window
        }
```

- [ ] **Step 2: Build to confirm**

```bash
xcodegen generate && xcodebuild -project APIStatusBar.xcodeproj -scheme APIStatusBar -configuration Debug -destination 'platform=macOS' build 2>&1 | grep -E "error:|FAILED|SUCCEEDED" | grep -v appintents | tail -3
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add APIStatusBar/APIStatusBarApp.swift
git commit -m "feat(app): WindowGroup id:dashboard for the new dashboard scene

Pinned to content size (480×380); File > New Window menu command
suppressed since this is a singleton-style window opened by the popover
button rather than a document-style window."
```

---

### Task 3.2: Add the dashboard button to `PopoverView`

**Files:**
- Modify: `APIStatusBar/UI/PopoverView.swift`

- [ ] **Step 1: Add `@Environment(\.openWindow)` to the view**

Near the other property declarations (`@State private var refreshSpin = false`):

```swift
@Environment(\.openWindow) private var openWindow
```

- [ ] **Step 2: Insert the dashboard button into `actionRow`**

In `actionRow`'s `HStack`, between the safari button and the trailing `Spacer()`, insert:

```swift
                Button {
                    openWindow(id: "dashboard")
                } label: {
                    Image(systemName: "chart.bar.xaxis")
                }
                .buttonStyle(.glass)
                .help("用量仪表板")
```

The full insertion context:

```swift
                Button {
                    if let url = URL(string: settings.serverURL), url.host != nil {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "safari")
                }
                .buttonStyle(.glass)
                .help("打开 Web 控制台")

                Button {
                    openWindow(id: "dashboard")
                } label: {
                    Image(systemName: "chart.bar.xaxis")
                }
                .buttonStyle(.glass)
                .help("用量仪表板")

                Spacer()
```

- [ ] **Step 3: Build + run all tests**

```bash
xcodebuild -project APIStatusBar.xcodeproj -scheme APIStatusBar -destination 'platform=macOS' test 2>&1 | grep -E "Executed [0-9]+ tests, with" | tail -2
```

Expected: 39 tests pass.

- [ ] **Step 4: Commit**

```bash
git add APIStatusBar/UI/PopoverView.swift
git commit -m "feat(popover): dashboard button (chart.bar.xaxis)

New glass-style icon button between Web Console and the right-aligned
group; opens the dashboard WindowGroup via @Environment(\.openWindow)."
```

---

## Phase 4 — Smoke & Tag

### Task 4.1: Manual smoke test + tag v0.2.0

- [ ] **Step 1: Kill any running instance and relaunch**

```bash
pkill -f "APIStatusBar.app" 2>/dev/null; sleep 1
xcodebuild -project APIStatusBar.xcodeproj -scheme APIStatusBar -configuration Debug -destination 'platform=macOS' build 2>&1 | grep -E "FAILED|SUCCEEDED" | tail -1
open /Users/dylanthomas/Library/Developer/Xcode/DerivedData/APIStatusBar-*/Build/Products/Debug/APIStatusBar.app
```

Expected: BUILD SUCCEEDED, app launches, status bar item appears.

- [ ] **Step 2: Verify popover dashboard button**

Click the menu bar icon. Popover should show the existing 4-button row plus a new `chart.bar.xaxis` icon button between Safari and the right group.

- [ ] **Step 3: Open dashboard**

Click the new button. Dashboard window opens centered, 480×380.

Verify:
- Account card top: 剩余 / 今日 / 总消耗 / 请求次数 — all populated
- Heatmap middle: 5×7 grid; today's cell (rightmost column, current weekday row) has a thin white inner stroke; recent days reflect actual usage as colored cells; out-of-window/future cells are gray
- Top Models bottom: top 5 providers with bars sized relative to leader; provider icons render correctly

- [ ] **Step 4: Verify hover tooltips**

Hover any heatmap cell within the 30-day window — tooltip shows `4月20日 · $1.23 · 12 次请求`. Out-of-window cell tooltip shows `M月d日 · 窗口外`.

- [ ] **Step 5: Verify refresh**

Click toolbar refresh button. Icon rotates 360°; account / heatmap / top models all re-fetch and re-render with smooth digit-roll for changed numbers.

- [ ] **Step 6: Verify singleton-window behavior**

Close the dashboard. Click the popover dashboard button again — same window opens (or new instance, depending on system; either is acceptable for singleton-style). No File > New Window menu item.

- [ ] **Step 7: Tag v0.2.0**

```bash
git tag -a v0.2.0 -m "v0.2.0: dashboard window with 30-day heatmap + Top Models (M2)"
git log --oneline | head -15
git tag --list
```

Expected: tag `v0.2.0` present.

---

## End of M2

What ships:
- ✅ New dashboard window opened from popover icon button
- ✅ 5×7 30-day usage heatmap with hover tooltips and today's cell highlighted
- ✅ Account card with remaining / today / total used / requests, all numeric-rolling
- ✅ Top Models card with 5-row proportional bars
- ✅ Reuses `ModelStatsPoller` data — no new network polling
- ✅ Unit tests covering daily aggregation, heatmap bucket math, grid date mapping (39 tests total)
- ✅ Manual smoke against live new-api

Deferred to M3 plan:
- Notarized .dmg, GitHub Actions release workflow, Homebrew tap cask formula (signing prerequisite work)
- Account "账户 N 天" once `/api/user/self` exposes `created_at`
- Top Channels card when per-channel quota source is available
- Heatmap range toggle (30d / 90d / 1y) if real usage motivates it
