import XCTest
@testable import APIStatusBar

final class HeatmapGridTests: XCTestCase {
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components)!
    }

    // today = 2026-04-25 (Sat), 13-column grid → today is column 12, row 5
    func test_today_isAtLastColumnAndCorrectRow() {
        let today = date(2026, 4, 25)
        let cell = HeatmapGrid.cell(for: today, today: today)
        XCTAssertEqual(cell, HeatmapGrid.Cell(column: 12, row: 5))
    }

    func test_yesterday_isAtLastColumnOneRowUp() {
        let today = date(2026, 4, 25)
        let cell = HeatmapGrid.cell(for: date(2026, 4, 24), today: today)
        XCTAssertEqual(cell, HeatmapGrid.Cell(column: 12, row: 4))
    }

    // Apr 19 (Sun) is one week back → column 11, row 6
    func test_dayInPriorWeek_isAtPriorColumn() {
        let today = date(2026, 4, 25)
        let cell = HeatmapGrid.cell(for: date(2026, 4, 19), today: today)
        XCTAssertEqual(cell, HeatmapGrid.Cell(column: 11, row: 6))
    }

    // leftmost Monday with today=Apr 25 is Jan 26
    func test_oldestVisibleDay_isInColumnZero() {
        let today = date(2026, 4, 25)
        let cell = HeatmapGrid.cell(for: date(2026, 1, 26), today: today)
        XCTAssertEqual(cell, HeatmapGrid.Cell(column: 0, row: 0))
    }

    // Jan 25 (Sun) is one day before the window → nil
    func test_dayBeforeOldestVisible_returnsNil() {
        let today = date(2026, 4, 25)
        let cell = HeatmapGrid.cell(for: date(2026, 1, 25), today: today)
        XCTAssertNil(cell)
    }

    func test_futureDay_returnsNil() {
        let today = date(2026, 4, 25)
        let cell = HeatmapGrid.cell(for: date(2026, 4, 26), today: today)
        XCTAssertNil(cell)
    }

    func test_dateForCell_inverseMapping() {
        let today = date(2026, 4, 25)
        XCTAssertEqual(HeatmapGrid.date(forCell: HeatmapGrid.Cell(column: 12, row: 5),
                                        today: today),
                       today)
        XCTAssertEqual(HeatmapGrid.date(forCell: HeatmapGrid.Cell(column: 0, row: 0),
                                        today: today),
                       date(2026, 1, 26))
    }

    func test_allCellDatesCoveredInOrder() {
        let today = date(2026, 4, 25)
        let dates = HeatmapGrid.allCells.map {
            HeatmapGrid.date(forCell: $0, today: today)
        }
        // 13 columns × 7 rows = 91 cells
        XCTAssertEqual(dates.count, 91)
        // first cell = (col:0, row:0) = leftmost Monday = Jan 26
        XCTAssertEqual(dates.first, date(2026, 1, 26))
        // last cell = (col:12, row:6) = Sunday after today = Apr 26
        XCTAssertEqual(dates.last, date(2026, 4, 26))
    }
}
