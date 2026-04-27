import SwiftUI

struct PopoverView: View {
    @ObservedObject var poller: QuotaPoller
    @ObservedObject var modelStats: ModelStatsPoller
    @ObservedObject var probe: ProbePoller
    @ObservedObject var settings: AppSettings
    let openSettings: () -> Void

    @State private var refreshSpin = false
    @State private var hoveredProvider: String?
    @Environment(\.openWindow) private var openWindow

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
                Text("尚未配置")
                    .font(.headline)
                Text("填入 new-api 服务器地址和访问令牌，即可追踪账户余额和各模型用量。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)

            Button("打开设置…") { openSettings() }
                .buttonStyle(.glassProminent)
                .tint(Theme.accent)
                .controlSize(.large)

            Divider().opacity(0.5)
            HStack {
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
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
                        let name = providers[row * 4 + col]
                        Image(name)
                            .resizable()
                            .renderingMode(.original)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 32, height: 32)
                            .padding(8)
                            .background(.regularMaterial,
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .scaleEffect(hoveredProvider == name ? 1.08 : 1.0)
                            .animation(.spring(response: 0.32, dampingFraction: 0.7),
                                       value: hoveredProvider)
                            .onHover { isHovering in
                                hoveredProvider = isHovering ? name : nil
                            }
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
                    Text("剩余额度")
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
                    .contentTransition(.numericText())
                    .animation(.snappy, value: balanceText)
            }
            Spacer(minLength: 8)
            if let asset = topProviderAsset {
                Image(asset)
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 44, height: 44)
                    .help("最常用模型 · \(asset.capitalized)")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var statsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            statRow("已用", value: usedText)
            statRow("请求次数", value: requestText)
            statRow("上次刷新", value: refreshedText)
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
                ProbeStatusDot(color: probe.snapshot?.health.color ?? .gray,
                                pulsing: probe.snapshot?.health == .healthy)
                probeStatusText
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
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
        } else if probe.lastError != nil {
            Text("探针不可用")
                .foregroundStyle(.tertiary)
        } else {
            Text("等待探测")
                .foregroundStyle(.tertiary)
        }
    }

    /// Single-line status summary — channel · ping · uptime — composed once
    /// so SwiftUI's truncation works cleanly instead of an HStack of segments
    /// wrapping unpredictably.
    private func probeStatusString(_ s: ProbePoller.Snapshot) -> String {
        guard let channel = probe.primaryChannelName else {
            return s.health.label
        }
        var parts: [String] = [channel]
        parts.append(s.health == .down ? s.health.label : "\(s.latencyMS) ms")
        if let up = probe.uptime24h {
            parts.append(String(format: "%.1f%%", up * 100))
        }
        return parts.joined(separator: " · ")
    }

    private var probeChart: some View {
        // 60 bars across ~280pt internal card width → ~3.6pt per bar with 1pt gap.
        // When history is empty (no service / awaiting first fetch), render
        // a flat row of low-opacity gray placeholder bars instead of mocking.
        GeometryReader { geo in
            let samples = probe.history
            let displayCount = max(samples.count, 60)
            let spacing: CGFloat = 1
            let totalSpacing = spacing * CGFloat(displayCount - 1)
            let barWidth = max((geo.size.width - totalSpacing) / CGFloat(displayCount), 2)
            HStack(alignment: .bottom, spacing: spacing) {
                if samples.isEmpty {
                    ForEach(0..<60, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.gray.opacity(0.22))
                            .frame(width: barWidth, height: 4)
                    }
                } else {
                    ForEach(samples) { sample in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(sample.health.color)
                            .frame(width: barWidth,
                                   height: barHeight(for: sample))
                            .help(barTooltip(for: sample))
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.6, anchor: .bottom)
                                    .combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                }
            }
            .frame(width: geo.size.width, height: 22, alignment: .bottom)
            .animation(.smooth(duration: 0.45), value: samples)
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
        f.locale = Locale(identifier: "zh-Hans")
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
            Text("常用模型")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .fixedSize()
            if top.isEmpty {
                Text(modelStats.lastError == nil ? "加载中…" : "—")
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
                        .help("\(provider.providerAsset.capitalized) — \(provider.requestCount) 次调用")
                        .transition(.scale.combined(with: .opacity))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .animation(.smooth(duration: 0.4), value: modelStats.topProviders)
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
                    refreshSpin.toggle()
                    Task {
                        await poller.refresh()
                        await modelStats.refresh()
                        await probe.refresh()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(refreshSpin ? 360 : 0))
                        .animation(.easeOut(duration: 0.6), value: refreshSpin)
                }
                .keyboardShortcut("r")
                .buttonStyle(.glassProminent)
                .tint(Theme.accent)
                .help("立即刷新")

                Button {
                    if let url = URL(string: settings.serverURL), url.host != nil {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "safari")
                }
                .buttonStyle(.glass)
                .help("打开 Web 控制台")

                Button {
                    openWindow(id: "dashboard")
                } label: {
                    Image(systemName: "chart.bar.xaxis")
                }
                .buttonStyle(.glass)
                .help("用量仪表板")

                Spacer()

                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .keyboardShortcut(",")
                .buttonStyle(.glass)
                .help("设置")

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .keyboardShortcut("q")
                .buttonStyle(.glass)
                .help("退出")
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
        guard let s = poller.snapshot else { return "尚未刷新" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        f.locale = Locale(identifier: "zh-Hans")
        return f.localizedString(for: s.fetchedAt, relativeTo: Date())
    }

    private var isLow: Bool {
        guard let s = poller.snapshot else { return false }
        return formatter.usd(fromRaw: s.quotaRaw) < settings.lowBalanceThresholdUSD
    }
}

/// Small status indicator: a solid dot, surrounded by a "pinging" halo when
/// the service is healthy. The halo expands and fades, looping forever — a
/// quiet visual sign that monitoring is live. Down/degraded states render
/// the dot only, no halo (you don't want a soothing pulse on a red light).
private struct ProbeStatusDot: View {
    let color: Color
    let pulsing: Bool

    @State private var animate = false

    var body: some View {
        ZStack {
            if pulsing {
                Circle()
                    .fill(color.opacity(0.45))
                    .frame(width: 8, height: 8)
                    .scaleEffect(animate ? 2.4 : 1.0)
                    .opacity(animate ? 0 : 0.7)
                    .animation(
                        .easeOut(duration: 1.8).repeatForever(autoreverses: false),
                        value: animate
                    )
            }
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle().strokeBorder(.white.opacity(0.3), lineWidth: 0.5)
                )
        }
        .frame(width: 14, height: 14)
        .onAppear { animate = pulsing }
        .onChange(of: pulsing) { _, newValue in
            animate = newValue
        }
    }
}
