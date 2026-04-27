import Foundation

/// Date mapping for the dashboard's 5x7 usage heatmap.
/// Columns are ISO-like weeks, with column 4 holding today's week.
/// Rows are Monday through Sunday.
enum HeatmapGrid {
    struct Cell: Equatable, Hashable {
        let column: Int
        let row: Int
    }

    static let allCells: [Cell] = (0..<7).flatMap { row in
        (0..<5).map { column in
            Cell(column: column, row: row)
        }
    }

    static func cell(for date: Date, today: Date) -> Cell? {
        let calendar = mondayFirstCalendar
        let day = calendar.startOfDay(for: date)
        let todayStart = calendar.startOfDay(for: today)
        guard day <= todayStart else { return nil }

        let leftmostMonday = mondayOfLeftmostColumn(today: todayStart)
        guard day >= leftmostMonday else { return nil }

        guard let dateWeekStart = calendar.dateInterval(of: .weekOfYear, for: day)?.start else {
            return nil
        }
        let column = calendar.dateComponents([.weekOfYear],
                                             from: leftmostMonday,
                                             to: dateWeekStart).weekOfYear ?? 0
        guard (0..<5).contains(column) else { return nil }

        let weekday = calendar.component(.weekday, from: day)
        let row = (weekday + 5) % 7
        return Cell(column: column, row: row)
    }

    static func date(forCell cell: Cell, today: Date) -> Date {
        let calendar = mondayFirstCalendar
        let leftmostMonday = mondayOfLeftmostColumn(today: today)
        let weekStart = calendar.date(byAdding: .weekOfYear,
                                      value: cell.column,
                                      to: leftmostMonday) ?? leftmostMonday
        return calendar.date(byAdding: .day,
                             value: cell.row,
                             to: weekStart) ?? weekStart
    }

    private static var mondayFirstCalendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private static func mondayOfLeftmostColumn(today: Date) -> Date {
        let calendar = mondayFirstCalendar
        let todayStart = calendar.startOfDay(for: today)
        let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: todayStart)?.start ?? todayStart
        return calendar.date(byAdding: .weekOfYear,
                             value: -4,
                             to: currentWeekStart) ?? currentWeekStart
    }
}
