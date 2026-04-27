import SwiftUI

struct HeatmapView: View {
    let dailyBuckets: [Date: DayBucket]
    let today: Date
    let topModel: String?

    private let cellSpacing: CGFloat = 2
    private let weekdayWidth: CGFloat = 12

    private var stats: HeatmapStats {
        HeatmapStats(dailyBuckets: dailyBuckets, today: today, topModel: topModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statsGrid
            monthLabelsRow
            heatmapGrid
            legendRow
        }
    }

    // MARK: - Stats cards (2 rows × 4 columns)

    private var statsGrid: some View {
        let s = stats
        return Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                statCell("花费", value: s.totalSpendText)
                statCell("请求", value: s.totalRequestsText)
                statCell("活跃", value: "\(s.activeDays) 天")
                statCell("峰值日", value: s.peakDayText)
            }
            GridRow {
                statCell("连续", value: s.currentStreakText)
                statCell("最长", value: s.longestStreakText)
                statCell("日均", value: s.avgDailyText)
                statCell("常用", value: s.topModelText)
            }
        }
    }

    private func statCell(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.accentStrong)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Theme.panelFill,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 0.5)
        }
    }

    // MARK: - Month labels

    private var monthLabelsRow: some View {
        GeometryReader { geo in
            let cellSize = self.cellSize(for: geo.size.width)
            HStack(alignment: .top, spacing: cellSpacing) {
                Color.clear.frame(width: weekdayWidth + cellSpacing, height: 1)
                ForEach(0..<HeatmapGrid.columnCount, id: \.self) { col in
                    let colDate = HeatmapGrid.date(
                        forCell: HeatmapGrid.Cell(column: col, row: 0), today: today)
                    let label = monthLabel(for: col, date: colDate)
                    Text(label)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .opacity(label.isEmpty ? 0 : 1)
                        .frame(width: cellSize)
                }
            }
        }
        .frame(height: 12)
    }

    // MARK: - Heatmap grid (fills width)

    private var heatmapGrid: some View {
        GeometryReader { geo in
            let cellSize = self.cellSize(for: geo.size.width)
            HStack(alignment: .top, spacing: cellSpacing) {
                weekdayColumn(cellSize: cellSize)
                HStack(alignment: .top, spacing: cellSpacing) {
                    ForEach(0..<HeatmapGrid.columnCount, id: \.self) { col in
                        VStack(spacing: cellSpacing) {
                            ForEach(0..<7, id: \.self) { row in
                                cell(at: HeatmapGrid.Cell(column: col, row: row),
                                     size: cellSize)
                            }
                        }
                        .frame(width: cellSize)
                    }
                }
            }
        }
        .frame(height: gridHeight)
    }

    private var gridHeight: CGFloat {
        // Approximate — will be recalculated by GeometryReader but needed for frame
        let approxCellSize: CGFloat = 20
        return approxCellSize * 7 + cellSpacing * 6
    }

    private func cellSize(for availableWidth: CGFloat) -> CGFloat {
        let gridWidth = availableWidth - weekdayWidth - cellSpacing
        let totalSpacing = cellSpacing * CGFloat(HeatmapGrid.columnCount - 1)
        return floor((gridWidth - totalSpacing) / CGFloat(HeatmapGrid.columnCount))
    }

    private func weekdayColumn(cellSize: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: cellSpacing) {
            ForEach(0..<7, id: \.self) { row in
                let label: String = [0: "一", 2: "三", 4: "五"][row] ?? ""
                Text(label)
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .opacity(label.isEmpty ? 0 : 1)
                    .frame(width: weekdayWidth, height: cellSize)
            }
        }
    }

    private func cell(at position: HeatmapGrid.Cell, size: CGFloat) -> some View {
        let cellDate = HeatmapGrid.date(forCell: position, today: today)
        let isVisible = HeatmapGrid.cell(for: cellDate, today: today) != nil
        let day = Calendar.current.startOfDay(for: cellDate)
        let bucket = isVisible ? dailyBuckets[day] : nil
        let bucketIndex = bucket.map { HeatmapBucket.bucket(forUSD: $0.usd) } ?? 0
        let isToday = Calendar.current.isDate(cellDate, inSameDayAs: today)

        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(fillColor(bucket: bucketIndex, isVisible: isVisible))
            .frame(width: size, height: size)
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(Theme.accentStrong.opacity(0.8), lineWidth: 1.2)
                }
            }
            .help(tooltip(date: cellDate, bucket: bucket, isVisible: isVisible))
    }

    private func fillColor(bucket: Int, isVisible: Bool) -> Color {
        guard isVisible, bucket > 0 else {
            return isVisible ? Theme.heatmapEmpty : Color.clear
        }
        let index = min(bucket, Theme.heatmapLevels.count - 1)
        return Theme.heatmapLevels[index]
    }

    private func tooltip(date: Date, bucket: DayBucket?, isVisible: Bool) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        formatter.locale = Locale(identifier: "zh-Hans")
        let dateText = formatter.string(from: date)
        guard isVisible else { return "" }
        guard let bucket else { return "\(dateText) · 无用量" }
        return String(format: "%@ · $%.2f · %d 次请求",
                      dateText, bucket.usd, bucket.requestCount)
    }

    // MARK: - Month label helpers

    private func monthLabel(for col: Int, date: Date) -> String {
        guard col > 0 else { return shortMonth(date) }
        let prevDate = HeatmapGrid.date(
            forCell: HeatmapGrid.Cell(column: col - 1, row: 0), today: today)
        let cal = Calendar.current
        if cal.component(.month, from: date) != cal.component(.month, from: prevDate) {
            return shortMonth(date)
        }
        return ""
    }

    private func shortMonth(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M月"
        f.locale = Locale(identifier: "zh-Hans")
        return f.string(from: date)
    }

    // MARK: - Legend

    private var legendRow: some View {
        HStack(spacing: 4) {
            Spacer()
            Text("少")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
            ForEach(1..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Theme.heatmapLevels[level])
                    .frame(width: 8, height: 8)
            }
            Text("多")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Stats computation

private struct HeatmapStats {
    let totalSpendText: String
    let totalRequestsText: String
    let activeDays: Int
    let peakDayText: String
    let currentStreakText: String
    let longestStreakText: String
    let avgDailyText: String
    let topModelText: String

    init(dailyBuckets: [Date: DayBucket], today: Date, topModel: String?) {
        let buckets = Array(dailyBuckets.values)
        let totalUSD = buckets.reduce(0.0) { $0 + $1.usd }
        let totalReqs = buckets.reduce(0) { $0 + $1.requestCount }

        totalSpendText = totalUSD >= 1000
            ? String(format: "$%.1fk", totalUSD / 1000)
            : String(format: "$%.1f", totalUSD)

        if totalReqs >= 10_000 {
            totalRequestsText = String(format: "%.1fw", Double(totalReqs) / 10_000)
        } else {
            totalRequestsText = totalReqs.formatted()
        }

        activeDays = buckets.count

        if let peak = buckets.max(by: { $0.usd < $1.usd }) {
            let f = DateFormatter()
            f.dateFormat = "M/d"
            peakDayText = f.string(from: peak.date)
        } else {
            peakDayText = "—"
        }

        let avgDaily = buckets.isEmpty ? 0 : totalUSD / Double(buckets.count)
        avgDailyText = String(format: "$%.1f", avgDaily)

        // Streak calculation
        let cal = Calendar.current
        let sortedDays = buckets.map { cal.startOfDay(for: $0.date) }.sorted(by: >)
        let todayStart = cal.startOfDay(for: today)

        var current = 0
        var checking = todayStart
        for _ in 0..<91 {
            if sortedDays.contains(checking) {
                current += 1
                checking = cal.date(byAdding: .day, value: -1, to: checking)!
            } else if current == 0 {
                // Today might not have data yet — check from yesterday
                checking = cal.date(byAdding: .day, value: -1, to: checking)!
                continue
            } else {
                break
            }
        }
        currentStreakText = "\(current)天"

        // Longest streak
        let daySet = Set(sortedDays)
        var longest = 0
        var visited = Set<Date>()
        for day in daySet {
            guard !visited.contains(day) else { continue }
            var streak = 1
            var d = cal.date(byAdding: .day, value: 1, to: day)!
            while daySet.contains(d) {
                streak += 1
                visited.insert(d)
                d = cal.date(byAdding: .day, value: 1, to: d)!
            }
            longest = max(longest, streak)
        }
        longestStreakText = "\(longest)天"

        if let model = topModel {
            let compact = model
                .replacingOccurrences(of: "claude-", with: "")
                .replacingOccurrences(of: "gpt-", with: "GPT ")
                .replacingOccurrences(of: "gemini-", with: "")
            topModelText = compact.count > 10
                ? String(compact.prefix(10))
                : compact
        } else {
            topModelText = "—"
        }
    }
}
