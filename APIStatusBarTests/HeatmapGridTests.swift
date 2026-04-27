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

    func test_today_isAtLastColumnAndCorrectRow() {
        let today = date(2026, 4, 25)
        let cell = HeatmapGrid.cell(for: today, today: today)
        XCTAssertEqual(cell, HeatmapGrid.Cell(column: 4, row: 5))
    }

    func test_yesterday_isAtLastColumnOneRowUp() {
        let today = date(2026, 4, 25)
        let cell = HeatmapGrid.cell(for: date(2026, 4, 24), today: today)
        XCTAssertEqual(cell, HeatmapGrid.Cell(column: 4, row: 4))
    }

    func test_dayInPriorWeek_isAtPriorColumn() {
        let today = date(2026, 4, 25)
        let cell = HeatmapGrid.cell(for: date(2026, 4, 19), today: today)
        XCTAssertEqual(cell, HeatmapGrid.Cell(column: 3, row: 6))
    }

    func test_oldestVisibleDay_isInColumnZero() {
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

    func test_dateForCell_inverseMapping() {
        let today = date(2026, 4, 25)
        XCTAssertEqual(HeatmapGrid.date(forCell: HeatmapGrid.Cell(column: 4, row: 5),
                                        today: today),
                       today)
        XCTAssertEqual(HeatmapGrid.date(forCell: HeatmapGrid.Cell(column: 0, row: 0),
                                        today: today),
                       date(2026, 3, 23))
    }

    func test_allCellDatesCoveredInOrder() {
        let today = date(2026, 4, 25)
        let dates = HeatmapGrid.allCells.map {
            HeatmapGrid.date(forCell: $0, today: today)
        }
        XCTAssertEqual(dates.count, 35)
        XCTAssertEqual(dates.first, date(2026, 3, 23))
        XCTAssertEqual(dates.last, date(2026, 4, 26))
    }
}
