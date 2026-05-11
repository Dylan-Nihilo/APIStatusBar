import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var credentials: CredentialStore
    var onCommit: () -> Void = { }

    @State private var accessToken: String = ""
    @State private var isTokenRevealed: Bool = false
    @State private var verification: Verification = .idle
    @State private var lastSavedAccessToken: String = ""
    @FocusState private var tokenFocused: Bool

    private let formatter = QuotaFormatter()

    enum Verification: Equatable {
        case idle
        case checking
        case success(remainingRMB: Double)
        case failure(String)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    connectionCard
                    credentialCard
                    billingCard
                }
                .padding(22)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 680)
        .frame(minHeight: 430)
        .navigationTitle("APIStatusBar 设置")
        .onAppear {
            accessToken = credentials.accessToken
            lastSavedAccessToken = credentials.accessToken
        }
        .onDisappear {
            if persistAccessTokenIfNeeded() {
                onCommit()
            }
        }
    }

    // MARK: - Sections

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.panelFillElevated)
                    AppLogoMark()
                        .foregroundStyle(Theme.accentStrong)
                        .frame(width: 22, height: 22)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text("APIStatusBar")
                        .font(.headline.weight(.semibold))
                    Text("New API")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsStatusPill(title: sidebarStatusTitle,
                               systemImage: sidebarStatusImage,
                               tint: sidebarStatusTint)

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 188)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.panelFill)
    }

    private var connectionCard: some View {
        SettingsCard(title: "服务器", systemImage: "network") {
            settingsRow("地址") {
                TextField("https://newapi.example.com", text: $settings.serverURL)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onChange(of: settings.serverURL) { _ in
                        verification = .idle
                    }
            }

            settingsRow("控制台") {
                HStack(spacing: 8) {
                    Button {
                        openInBrowser()
                    } label: {
                        Label("打开控制台", systemImage: "safari")
                    }
                    .disabled(URL(string: settings.serverURL)?.host == nil)

                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var credentialCard: some View {
        SettingsCard(title: "凭据", systemImage: "key.horizontal") {
            settingsRow("令牌") {
                HStack(spacing: 8) {
                    Group {
                        if isTokenRevealed {
                            TextField("系统访问令牌", text: $accessToken)
                        } else {
                            SecureField("系统访问令牌", text: $accessToken)
                        }
                    }
                    .focused($tokenFocused)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .onChange(of: accessToken) { _ in
                        verification = .idle
                    }

                    Button {
                        isTokenRevealed.toggle()
                        tokenFocused = true
                    } label: {
                        Image(systemName: isTokenRevealed ? "eye.slash" : "eye")
                    }
                    .help(isTokenRevealed ? "隐藏令牌" : "显示令牌")

                    Button {
                        pasteAccessToken()
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .help("从剪贴板读取")
                }
            }

            settingsRow("连接") {
                HStack(spacing: 10) {
                    Button {
                        Task { await verifyConnection() }
                    } label: {
                        verifyButtonLabel
                    }
                    .disabled(!canVerify)

                    statusInline
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var billingCard: some View {
        SettingsCard(title: "计费与轮询", systemImage: "yensign.circle") {
            settingsRow("刷新") {
                Stepper("\(settings.refreshIntervalSeconds) 秒",
                        value: $settings.refreshIntervalSeconds,
                        in: 15...3600,
                        step: 15)
                    .monospacedDigit()
            }

            settingsRow("低余额") {
                Stepper("¥\(settings.lowBalanceThresholdRMB, specifier: "%.0f")",
                        value: $settings.lowBalanceThresholdRMB,
                        in: 0...10_000,
                        step: 5)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var verifyButtonLabel: some View {
        if verification == .checking {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text("验证中")
            }
        } else {
            Label("验证连接", systemImage: "checkmark.shield")
        }
    }

    @ViewBuilder
    private var statusInline: some View {
        switch verification {
        case .idle, .checking:
            EmptyView()
        case .success(let rmb):
            Label(formatter.displayRMB(rmb: rmb), systemImage: "checkmark.circle.fill")
                .foregroundStyle(Theme.champagne)
                .font(.callout)
        case .failure(let msg):
            Label(shortError(msg), systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.warning)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func settingsRow<Content: View>(_ title: String,
                                            @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(Theme.metricSecondary)
                .frame(width: 58, alignment: .leading)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Computed

    private var canVerify: Bool {
        guard URL(string: settings.serverURL)?.host != nil else { return false }
        guard !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return verification != .checking
    }

    private var sidebarStatusTitle: String {
        switch verification {
        case .checking:
            return "验证中"
        case .success:
            return "已连接"
        case .failure:
            return "连接失败"
        case .idle:
            return settings.isConfigured && !accessToken.isEmpty ? "已配置" : "待配置"
        }
    }

    private var sidebarStatusImage: String {
        switch verification {
        case .checking:
            return "arrow.triangle.2.circlepath"
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "exclamationmark.triangle.fill"
        case .idle:
            return settings.isConfigured && !accessToken.isEmpty ? "checkmark.circle" : "circle.dotted"
        }
    }

    private var sidebarStatusTint: Color {
        switch verification {
        case .success:
            return Theme.champagne
        case .failure:
            return Theme.warning
        default:
            return Theme.metricSecondary
        }
    }

    // MARK: - Actions

    private func openInBrowser() {
        guard var components = URLComponents(string: settings.serverURL) else { return }
        if components.path.isEmpty || components.path == "/" {
            components.path = "/console/personal"
        }
        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }

    private func pasteAccessToken() {
        guard let pasted = NSPasteboard.general.string(forType: .string) else { return }
        accessToken = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        tokenFocused = true
    }

    private func verifyConnection() async {
        verification = .checking
        guard persistAccessTokenIfNeeded() else {
            verification = .failure("令牌保存失败，请允许 Keychain 访问")
            return
        }
        onCommit()
        guard let url = URL(string: settings.serverURL), url.host != nil else {
            verification = .failure("服务器地址无效")
            return
        }
        do {
            let resp = try await NewAPIClient(baseURL: url,
                                             accessToken: accessToken).getSelf()
            verification = .success(remainingRMB: formatter.rmb(fromRaw: resp.quota))
        } catch let err as NewAPIError {
            switch err {
            case .httpStatus(401):
                verification = .failure("HTTP 401 — 令牌无效或无权限")
            case .httpStatus(let code):
                verification = .failure("HTTP \(code)")
            case .apiFailure(let msg):
                verification = .failure(msg)
            case .decoding:
                verification = .failure("响应格式异常")
            }
        } catch {
            verification = .failure(error.localizedDescription)
        }
    }

    private func shortError(_ message: String) -> String {
        if message.contains("401") { return "令牌无效" }
        if message.contains("响应") || message.contains("decoding") { return "响应异常" }
        if message.contains("服务器") || message.contains("HTTP") { return "服务器不可用" }
        if message.count > 12 { return "连接失败" }
        return message
    }

    @discardableResult
    private func persistAccessTokenIfNeeded() -> Bool {
        let trimmed = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != lastSavedAccessToken else { return true }
        guard credentials.saveAccessToken(trimmed) else { return false }
        accessToken = trimmed
        lastSavedAccessToken = trimmed
        return true
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(title: String,
         systemImage: String,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 12) {
                content
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panelFillElevated,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        }
    }
}

private struct SettingsStatusPill: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
            Text(title)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
