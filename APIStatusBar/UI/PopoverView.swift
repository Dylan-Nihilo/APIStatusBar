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
        VStack(spacing: 18) {
            providerGrid

            VStack(spacing: 6) {
                Text("Set up your account")
                    .font(.headline)
                Text("Add your new-api server URL and access token to start tracking your balance across every model your gateway routes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)

            Button("Open Settings…") { openSettings() }
                .buttonStyle(.glassProminent)
                .tint(Theme.accent)
                .controlSize(.large)

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

    /// 4×3 grid of representative LLM provider icons. Decorative — communicates
    /// "this app is for LLM gateways" without needing real /api/user/models data.
    private var providerGrid: some View {
        let providers = [
            "claude", "openai", "gemini", "deepseek",
            "qwen", "kimi", "doubao", "zhipu",
            "minimax", "mistral", "meta", "perplexity",
        ]
        return Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    ForEach(0..<4, id: \.self) { col in
                        Image(providers[row * 4 + col])
                            .resizable()
                            .renderingMode(.original)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 32, height: 32)
                            .padding(8)
                            .background(.regularMaterial,
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
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
        VStack(alignment: .leading, spacing: 10) {
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

            Divider().opacity(0.4)

            providerStrip
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Subtle row of provider icons hinting at the breadth of models the gateway routes.
    /// Decorative for v0.1 — M2 will wire this to /api/user/models for the real list.
    private var providerStrip: some View {
        let providers = [
            "claude", "openai", "gemini", "deepseek",
            "qwen", "kimi", "doubao", "mistral",
        ]
        return HStack(spacing: 6) {
            Text("Models")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            ForEach(providers, id: \.self) { name in
                Image(name)
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .opacity(0.85)
            }
            Text("+more")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
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
