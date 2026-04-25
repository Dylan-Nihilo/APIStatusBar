import SwiftUI

struct MenuBarLabel: View {
    let snapshot: QuotaSnapshot?
    let formatter: QuotaFormatter
    let lowBalanceThresholdUSD: Double
    let hasError: Bool
    let isConfigured: Bool
    /// Asset name of the top-used provider's color icon. When set and configured,
    /// replaces the generic SF Symbol with the model's brand icon.
    let topProviderAsset: String?

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            iconView
                .frame(width: 14, height: 14)
            if isConfigured {
                Text(label)
                    .foregroundStyle(isLow ? Theme.warning : .primary)
                    .monospacedDigit()
            } else {
                Text("待配置")
            }
        }
        .font(.system(size: 13, weight: .medium))
    }

    @ViewBuilder
    private var iconView: some View {
        if !isConfigured {
            Image(systemName: "gearshape")
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else if hasError {
            Image(systemName: "exclamationmark.triangle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(Theme.warning)
        } else if let asset = topProviderAsset {
            Image(asset)
                .resizable()
                .renderingMode(.original)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "dollarsign.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(Theme.accent)
        }
    }

    private var usd: Double? {
        guard let snapshot else { return nil }
        return formatter.usd(fromRaw: snapshot.quotaRaw)
    }

    private var label: String {
        guard let usd else { return "—" }
        return formatter.displayString(usd: usd)
    }

    private var isLow: Bool {
        guard let usd else { return false }
        return usd < lowBalanceThresholdUSD
    }
}
