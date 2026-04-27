import SwiftUI

struct HeatmapView: View {
    let dailyBuckets: [Date: DayBucket]
    let today: Date

    private let cellSize: CGFloat = 14
    private let cellSpacing: CGFloat = 2
    private let weekdayLabels = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("用量热力图（最近 30 天）")
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 12)
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
                    ForEach(0..<5, id: \.self) { column in
                        cell(at: HeatmapGrid.Cell(column: column, row: row))
                    }
                }
            }
        }
    }

    private func cell(at position: HeatmapGrid.Cell) -> some View {
        let cellDate = HeatmapGrid.date(forCell: position, today: today)
        let isVisible = HeatmapGrid.cell(for: cellDate, today: today) != nil
        let day = Calendar.current.startOfDay(for: cellDate)
        let bucket = isVisible ? dailyBuckets[day] : nil
        let bucketIndex = bucket.map { HeatmapBucket.bucket(forUSD: $0.usd) } ?? 0
        let isToday = Calendar.current.isDate(cellDate, inSameDayAs: today)

        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(fillColor(bucket: bucketIndex, isVisible: isVisible))
            .frame(width: cellSize, height: cellSize)
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(.white.opacity(0.7), lineWidth: 1)
                }
            }
            .help(tooltip(date: cellDate, bucket: bucket, isVisible: isVisible))
    }

    private func fillColor(bucket: Int, isVisible: Bool) -> Color {
        guard isVisible, bucket > 0 else { return Theme.heatmapEmpty }
        let index = min(bucket, Theme.heatmapAlphas.count - 1)
        return Theme.accent.opacity(Theme.heatmapAlphas[index])
    }

    private func tooltip(date: Date, bucket: DayBucket?, isVisible: Bool) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        formatter.locale = Locale(identifier: "zh-Hans")
        let dateText = formatter.string(from: date)
        guard isVisible else { return "\(dateText) · 窗口外" }
        guard let bucket else { return "\(dateText) · 无用量" }
        return String(format: "%@ · $%.2f · %d 次请求",
                      dateText,
                      bucket.usd,
                      bucket.requestCount)
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Text("少")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            ForEach(1..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Theme.accent.opacity(Theme.heatmapAlphas[level]))
                    .frame(width: 10, height: 10)
            }
            Text("多")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .lineLimit(1)
    }
}
