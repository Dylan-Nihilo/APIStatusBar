import SwiftUI

struct MenuBarLabel: View {
    let snapshot: QuotaSnapshot?
    let formatter: QuotaFormatter
    let lowBalanceThresholdUSD: Double
    let hasError: Bool
    let isConfigured: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
            if isConfigured {
                Text(label)
                    .foregroundStyle(isLow ? Theme.warning : .primary)
                    .monospacedDigit()
            } else {
                Text("Setup")
            }
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

    private var iconName: String {
        if !isConfigured { return "gear" }
        if hasError { return "exclamationmark.triangle" }
        return "gauge.with.dots.needle.bottom.50percent"
    }
}
