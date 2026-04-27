import SwiftUI

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
        .background(Theme.panelFillElevated,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.surfaceBorder, lineWidth: 0.6)
        }
    }

    private func row(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(label == "剩余" ? Theme.accentStrong : .primary)
                .monospacedDigit()
                .lineLimit(1)
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
        }
        .frame(maxWidth: .infinity)
    }

    private var remainingText: String {
        guard let snapshot = poller.snapshot else { return "-" }
        return formatter.displayString(usd: formatter.usd(fromRaw: snapshot.quotaRaw))
    }

    private var todayText: String {
        let today = Calendar.current.startOfDay(for: Date())
        guard let bucket = modelStats.dailyBuckets[today] else { return "$0.00" }
        return formatter.displayString(usd: bucket.usd)
    }

    private var usedText: String {
        guard let snapshot = poller.snapshot else { return "-" }
        return formatter.displayString(usd: formatter.usd(fromRaw: snapshot.usedQuotaRaw))
    }

    private var requestText: String {
        guard let snapshot = poller.snapshot else { return "-" }
        return snapshot.requestCount.formatted()
    }
}
