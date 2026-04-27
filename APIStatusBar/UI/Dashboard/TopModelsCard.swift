import SwiftUI

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
                .lineLimit(1)

            if topProviders.isEmpty {
                Text("暂无用量数据")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 8) {
                    ForEach(topProviders) { provider in
                        row(for: provider)
                    }
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
                .frame(width: 70, alignment: .leading)

            ProgressBar(fraction: leadFraction)
                .frame(height: 8)

            Text(formatter.displayString(usd: usd))
                .font(.callout)
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: 58, alignment: .trailing)

            Text(String(format: "%.1f%%", percent * 100))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: 46, alignment: .trailing)
        }
    }

    private func leaderFraction(provider: ProviderUsage) -> Double {
        guard let leader = topProviders.first, leader.quotaRaw > 0 else { return 0 }
        return Double(provider.quotaRaw) / Double(leader.quotaRaw)
    }
}

private struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.heatmapEmpty)
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: max(0, min(1, fraction)) * proxy.size.width)
            }
        }
        .accessibilityHidden(true)
    }
}
