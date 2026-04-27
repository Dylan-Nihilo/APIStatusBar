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
        .frame(width: 336)
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
                .tint(Theme.accentStrong)
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
                            .background(Theme.panelFill,
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Theme.hairline, lineWidth: 0.5)
                            }
                            .scaleEffect(hoveredProvider == name ? 1.04 : 1.0)
                            .animation(.smooth(duration: 0.18),
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
        VStack(alignment: .leading, spacing: 12) {
            accountHeader
            metricsRow
            probePanel
            topModelsStrip
            actionRow
        }
        .padding(14)
    }

    private var accountHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text("余额")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.metricSecondary)
                    if poller.isRefreshing {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(Theme.accent)
                    }
                }
                Text(balanceText)
                    .font(.system(size: 30, weight: .semibold, design: .default))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(isLow ? Theme.warning : Theme.accentStrong)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: balanceText)
            }
            Spacer(minLength: 8)
            if let asset = topProviderAsset {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(topProviderLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.metricSecondary)
                            .lineLimit(1)
                        if let model = topModelName {
                            Text(compactModelName(model))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 118, alignment: .trailing)
                                .help(model)
                        }
                    }
                    Image(asset)
                        .resizable()
                        .renderingMode(.original)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 36, height: 36)
                        .help("最常用模型 · \(asset.capitalized)")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panelFillElevated,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.surfaceBorder, lineWidth: 0.6)
        }
    }

    private var metricsRow: some View {
        HStack(spacing: 0) {
            metricColumn("已用", value: usedText)
            metricDivider
            metricColumn("请求", value: requestText)
            metricDivider
            metricColumn("刷新", value: refreshedText)
        }
        .padding(.vertical, 8)
        .background(Theme.panelFill,
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 0.5)
        }
    }

    private func metricColumn(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Text(value)
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .foregroundStyle(Theme.accentStrong)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(width: 0.5, height: 28)
    }

    /// Live probe strip: status, channel summary and 30-minute bar chart.
    private var probePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProbeStatusDot(color: probe.snapshot?.health.color ?? .gray,
                                pulsing: probe.snapshot?.health == .healthy)
                VStack(alignment: .leading, spacing: 1) {
                    Text("探针")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    probeStatusText
                }
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                if let error = poller.lastError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                        .help(String(describing: error))
                }
            }

            probeChart
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panelFill,
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private var probeStatusText: some View {
        if let s = probe.snapshot {
            Text(probeStatusString(s))
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.metricSecondary)
                .monospacedDigit()
        } else if probe.lastError != nil {
            Text("探针不可用")
                .font(.caption.weight(.medium))
                .foregroundStyle(.tertiary)
        } else {
            Text("等待探测")
                .font(.caption.weight(.medium))
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
            Text("常用")
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
                        .frame(width: 17, height: 17)
                        .padding(4)
                        .background(.thinMaterial, in: Circle())
                        .help("\(provider.providerAsset.capitalized) — \(provider.requestCount) 次调用")
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity)
        .animation(.smooth(duration: 0.25), value: modelStats.topProviders)
    }

    private var actionRow: some View {
        HStack(spacing: 7) {
            refreshToolbarButton
            toolbarButton("safari", help: "打开 Web 控制台") {
                if let url = URL(string: settings.serverURL), url.host != nil {
                    NSWorkspace.shared.open(url)
                }
            }
            toolbarButton("chart.bar.xaxis", help: "用量仪表板") {
                openWindow(id: "dashboard")
            }

            Spacer(minLength: 0)

            toolbarButton("gearshape", help: "设置") {
                openSettings()
            }
            .keyboardShortcut(",")
            toolbarButton("power", help: "退出") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(5)
        .background(Theme.panelFill,
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 0.5)
        }
    }

    private var refreshToolbarButton: some View {
        Button {
            refreshSpin.toggle()
            Task {
                await poller.refresh()
                await modelStats.refresh()
                await probe.refresh()
            }
        } label: {
            Image(systemName: "arrow.clockwise")
                .frame(width: 23, height: 23)
                .rotationEffect(.degrees(refreshSpin ? 360 : 0))
                .animation(.easeOut(duration: 0.42), value: refreshSpin)
        }
        .keyboardShortcut("r")
        .buttonStyle(.borderless)
        .foregroundStyle(Theme.accentStrong)
        .background(Theme.accentMuted.opacity(0.38),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .help("立即刷新")
    }

    private func toolbarButton(_ systemName: String,
                               help: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 23, height: 23)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Theme.metricSecondary)
        .background(Color.clear,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .help(help)
    }

    // MARK: - Computed

    private var topProviderAsset: String? {
        modelStats.topProviders.first?.providerAsset
    }

    private var topProviderLabel: String {
        guard let asset = topProviderAsset else { return "" }
        return asset.capitalized
    }

    private var topModelName: String? {
        modelStats.topProviders.first?.modelNames.first
    }

    private func compactModelName(_ model: String) -> String {
        model
            .replacingOccurrences(of: "claude-", with: "")
            .replacingOccurrences(of: "gpt-", with: "GPT ")
            .replacingOccurrences(of: "gemini-", with: "Gemini ")
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
