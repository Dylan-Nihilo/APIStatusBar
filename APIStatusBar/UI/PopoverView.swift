import SwiftUI

struct PopoverView: View {
    @ObservedObject var poller: QuotaPoller
    @ObservedObject var settings: AppSettings
    let openSettings: () -> Void

    private var formatter: QuotaFormatter {
        QuotaFormatter(quotaPerUnit: settings.quotaPerUnit)
    }

    var body: some View {
        Group {
            if settings.isConfigured {
                configuredBody
            } else {
                emptyBody
            }
        }
        .frame(width: 320)
    }

    private var emptyBody: some View {
        VStack(spacing: 16) {
            ContentUnavailableView {
                Label("Set up your account", systemImage: "key.horizontal")
            } description: {
                Text("Add your new-api server URL and access token to start tracking your balance.")
            } actions: {
                Button("Open Settings…") { openSettings() }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.accent)
                    .controlSize(.large)
            }

            Divider().opacity(0.5)
            HStack {
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .keyboardShortcut("q")
            }
        }
        .padding(20)
    }

    private var configuredBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            balanceBlock
            statsBlock
            actionRow
        }
        .padding(16)
    }

    private var balanceBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Remaining")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if poller.isRefreshing {
                    ProgressView().controlSize(.mini)
                }
            }
            Text(balanceText)
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(isLow ? Theme.warning : .primary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var statsBlock: some View {
        VStack(spacing: 8) {
            LabeledContent("Used", value: usedText)
            LabeledContent("Requests", value: requestText)
            LabeledContent("Last refresh", value: refreshedText)
            if let error = poller.lastError {
                Label(String(describing: error), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
        }
        .font(.callout)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var actionRow: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    Task { await poller.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .keyboardShortcut("r")
                .buttonStyle(.glassProminent)
                .tint(Theme.accent)
                .help("Refresh now")

                Button {
                    if let url = URL(string: settings.serverURL), url.host != nil {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "safari")
                }
                .buttonStyle(.glass)
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
    }

    private var balanceText: String {
        guard let s = poller.snapshot else { return "—" }
        return formatter.displayString(usd: formatter.usd(fromRaw: s.quotaRaw))
    }

    private var usedText: String {
        guard let s = poller.snapshot else { return "—" }
        return formatter.displayString(usd: formatter.usd(fromRaw: s.usedQuotaRaw))
    }

    private var requestText: String {
        guard let s = poller.snapshot else { return "—" }
        return s.requestCount.formatted()
    }

    private var refreshedText: String {
        guard let s = poller.snapshot else { return "never" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: s.fetchedAt, relativeTo: Date())
    }

    private var isLow: Bool {
        guard let s = poller.snapshot else { return false }
        return formatter.usd(fromRaw: s.quotaRaw) < settings.lowBalanceThresholdUSD
    }
}
