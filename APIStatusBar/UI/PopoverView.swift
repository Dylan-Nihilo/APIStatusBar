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
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(settings.isConfigured ? "Remaining" : "Not configured")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(balanceText)
                    .font(.system(size: settings.isConfigured ? 32 : 22,
                                  weight: .semibold,
                                  design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(isLow ? Theme.warning : .primary)
            }
            Spacer(minLength: 8)
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
            Button {
                Task { await poller.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .keyboardShortcut("r")
            .buttonStyle(.glassProminent)
            .tint(Theme.accent)
            .disabled(!settings.isConfigured)
            .help("Refresh now")

            Button {
                if let url = URL(string: settings.serverURL), url.host != nil {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Image(systemName: "safari")
            }
            .buttonStyle(.glass)
            .disabled(!settings.isConfigured)
            .help("Open Web Console")

            Spacer()

            Button("Settings…") { openSettings() }
                .keyboardShortcut(",")
                .buttonStyle(.glass)

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .keyboardShortcut("q")
            .buttonStyle(.glass)
            .help("Quit")
        }
        .controlSize(.small)
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
        guard let snap = poller.snapshot else {
            return settings.isConfigured ? "—" : "Tap Settings"
        }
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
