import SwiftUI

struct PopoverView: View {
    @ObservedObject var poller: QuotaPoller
    @ObservedObject var modelStats: ModelStatsPoller
    @ObservedObject var probe: ProbePoller
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

    // MARK: - Empty (first-run) state

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

    // MARK: - Configured state

    private var configuredBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            balanceBlock
            statsBlock
            topModelsStrip
            actionRow
        }
        .padding(16)
    }

    private var balanceBlock: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            Spacer(minLength: 8)
            if let asset = topProviderAsset {
                Image(asset)
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 44, height: 44)
                    .help("Top model · \(asset.capitalized)")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var statsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            statRow("Used", value: usedText)
            statRow("Requests", value: requestText)
            statRow("Last refresh", value: refreshedText)
            if let error = poller.lastError {
                Label(String(describing: error), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            Divider().opacity(0.4)
            probeRow
        }
        .font(.callout)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func statRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 12)
            Text(value)
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    /// Live probe block: header row (status dot + label + current latency)
    /// stacked above a 30-minute time-series bar chart. Bar height = latency,
    /// color = health. Currently fed by mocked data.
    private var probeRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(probe.snapshot?.health.color ?? .gray)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 0.5))
                Text("Probe")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 12)
                probeStatusText
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            probeChart
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var probeStatusText: some View {
        if let s = probe.snapshot {
            Text(probeStatusString(s))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        } else {
            Text("Checking…")
                .foregroundStyle(.tertiary)
        }
    }

    /// Single-line status summary so SwiftUI's truncation works cleanly
    /// instead of an HStack of segments wrapping unpredictably.
    private func probeStatusString(_ s: ProbePoller.Snapshot) -> String {
        var parts: [String] = []
        if let channel = probe.primaryChannelName {
            parts.append(channel)
            parts.append(s.health == .down ? s.health.label : "\(s.latencyMS) ms")
            if let up = probe.uptime24h {
                parts.append(String(format: "%.1f%% 24h", up * 100))
            }
        } else {
            // Mock fallback — no channel name, show the descriptive label.
            if s.health == .down {
                parts.append(s.health.label)
            } else {
                parts.append("\(s.health.label) · \(s.latencyMS) ms")
            }
        }
        return parts.joined(separator: " · ")
    }

    private var probeChart: some View {
        // 60 bars across ~280pt internal card width → ~3.6pt per bar with 1pt gap.
        // Use GeometryReader so this scales if the popover width changes later.
        GeometryReader { geo in
            let samples = probe.history
            let count = max(samples.count, 1)
            let spacing: CGFloat = 1
            let totalSpacing = spacing * CGFloat(count - 1)
            let barWidth = max((geo.size.width - totalSpacing) / CGFloat(count), 2)
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(samples) { sample in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(sample.health.color)
                        .frame(width: barWidth,
                               height: barHeight(for: sample))
                        .help(barTooltip(for: sample))
                }
            }
            .frame(width: geo.size.width, height: 22, alignment: .bottom)
        }
        .frame(height: 22)
    }

    /// Categorical height: green tops out (healthy ceiling), yellow dips
    /// halfway (unstable), red collapses to a stub (down). Latency stays in
    /// the tooltip — the bar's job here is "is the service OK?", read at a
    /// glance from the chart's silhouette.
    private func barHeight(for sample: ProbePoller.Snapshot) -> CGFloat {
        switch sample.health {
        case .healthy:  return 18
        case .degraded: return 9
        case .down:     return 4
        case .unknown:  return 2
        }
    }

    private func barTooltip(for sample: ProbePoller.Snapshot) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        let when = f.localizedString(for: sample.timestamp, relativeTo: Date())
        if sample.health == .down {
            return "\(sample.health.label) · \(when)"
        }
        return "\(sample.latencyMS) ms · \(when)"
    }

    /// Standalone bare row of provider icons sized by usage share, sitting
    /// between the stats card and the action footer.
    private var topModelsStrip: some View {
        let top = Array(modelStats.topProviders.prefix(5))
        return HStack(alignment: .center, spacing: 8) {
            Text("Top models")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .fixedSize()
            if top.isEmpty {
                Text(modelStats.lastError == nil ? "loading…" : "—")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            } else {
                ForEach(top) { provider in
                    Image(provider.providerAsset)
                        .resizable()
                        .renderingMode(.original)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: iconSize(for: provider, top: top),
                               height: iconSize(for: provider, top: top))
                        .help("\(provider.providerAsset.capitalized) — \(provider.requestCount) requests")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
    }

    private func iconSize(for p: ProviderUsage, top: [ProviderUsage]) -> CGFloat {
        guard top.count > 1, let max = top.first?.quotaRaw, max > 0 else { return 18 }
        let ratio = CGFloat(p.quotaRaw) / CGFloat(max)
        return 14 + ratio * 8
    }

    private var actionRow: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    Task { await poller.refresh(); await modelStats.refresh(); await probe.refresh() }
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

    // MARK: - Computed

    private var topProviderAsset: String? {
        modelStats.topProviders.first?.providerAsset
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
