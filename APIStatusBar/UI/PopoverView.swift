import SwiftUI

struct PopoverView: View {
    @ObservedObject var poller: QuotaPoller
    @ObservedObject var settings: AppSettings
    let openSettings: () -> Void

    private var formatter: QuotaFormatter {
        QuotaFormatter(quotaPerUnit: settings.quotaPerUnit)
    }

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                balanceCard
                statsCard
                footerRow
            }
            .padding(14)
            .frame(width: 300)
        }
    }

    private var balanceCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Remaining").font(.caption).foregroundStyle(.secondary)
                Text(balanceText)
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isLow ? Theme.warning : .primary)
            }
            Spacer()
            if poller.isRefreshing {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            row("Used", value: usedText)
            row("Requests", value: requestText)
            row("Last refresh", value: refreshedText)
            if let error = poller.lastError {
                Text("Error: \(String(describing: error))")
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var footerRow: some View {
        HStack(spacing: 6) {
            Button("Refresh") {
                Task { await poller.refresh() }
            }
            .keyboardShortcut("r")
            .glassEffect(.regular.tint(Theme.accent.opacity(0.4)).interactive(),
                         in: Capsule())

            Button("Web Console") {
                if let url = URL(string: settings.serverURL), url.host != nil {
                    NSWorkspace.shared.open(url)
                }
            }
            .disabled(!settings.isConfigured)
            .glassEffect(.regular.interactive(), in: Capsule())

            Spacer()

            Button("Settings…") { openSettings() }
                .keyboardShortcut(",")
                .glassEffect(.regular.interactive(), in: Capsule())

            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
                .glassEffect(.regular.interactive(), in: Capsule())
        }
        .controlSize(.small)
        .buttonStyle(.plain)
    }

    private func row(_ key: String, value: String) -> some View {
        HStack {
            Text(key).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.callout)
    }

    private var balanceText: String {
        guard let snap = poller.snapshot else { return settings.isConfigured ? "—" : "Setup needed" }
        return formatter.displayString(usd: formatter.usd(fromRaw: snap.quotaRaw))
    }

    private var usedText: String {
        guard let snap = poller.snapshot else { return "—" }
        return formatter.displayString(usd: formatter.usd(fromRaw: snap.usedQuotaRaw))
    }

    private var requestText: String {
        guard let snap = poller.snapshot else { return "—" }
        return snap.requestCount.formatted()
    }

    private var refreshedText: String {
        guard let snap = poller.snapshot else { return "never" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: snap.fetchedAt, relativeTo: Date())
    }

    private var isLow: Bool {
        guard let snap = poller.snapshot else { return false }
        return formatter.usd(fromRaw: snap.quotaRaw) < settings.lowBalanceThresholdUSD
    }
}
