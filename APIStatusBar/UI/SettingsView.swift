import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var credentials: CredentialStore
    @State private var accessToken: String = ""
    @State private var isTokenRevealed: Bool = false
    @State private var verification: Verification = .idle
    @State private var lastSavedAccessToken: String = ""
    @State private var showAdvanced: Bool = false
    @FocusState private var tokenFocused: Bool

    enum Verification: Equatable {
        case idle
        case checking
        case success(remainingUSD: Double)
        case failure(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("APIStatusBar")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.accentStrong)
                    Text("new-api 账户监控")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                connectionBadge
            }

            settingsSection("服务器") {
                settingRow("地址") {
                    TextField("https://api.your-host.com", text: $settings.serverURL)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textContentType(.URL)
                        .frame(minWidth: 280)
                }

                settingRow("控制台") {
                    Button("打开") { openInBrowser() }
                        .disabled(URL(string: settings.serverURL)?.host == nil)
                }
            }

            settingsSection("凭据") {
                settingRow("令牌") {
                    HStack(spacing: 6) {
                        Group {
                            if isTokenRevealed {
                                TextField("粘贴系统访问令牌", text: $accessToken)
                            } else {
                                SecureField("粘贴系统访问令牌", text: $accessToken)
                            }
                        }
                        .focused($tokenFocused)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .onChange(of: accessToken) { _, _ in
                            verification = .idle
                        }

                        iconButton(isTokenRevealed ? "eye.slash" : "eye",
                                   help: isTokenRevealed ? "隐藏令牌" : "显示令牌") {
                            isTokenRevealed.toggle()
                            tokenFocused = true
                        }

                        iconButton("doc.on.clipboard", help: "从剪贴板粘贴") {
                            if let pasted = NSPasteboard.general.string(forType: .string) {
                                accessToken = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        }
                    }
                }

                settingRow("连接") {
                    HStack(spacing: 8) {
                        Button {
                            Task { await verifyConnection() }
                        } label: {
                            if verification == .checking {
                                HStack(spacing: 5) {
                                    ProgressView().controlSize(.mini)
                                    Text("验证中")
                                }
                            } else {
                                Text("验证连接")
                            }
                        }
                        .disabled(!canVerify)

                        statusInline
                    }
                }

                helpFooter
            }

            settingsSection("高级") {
                DisclosureGroup("计费与轮询", isExpanded: $showAdvanced) {
                    VStack(spacing: 10) {
                        settingRow("每 $1") {
                            intControl(value: $settings.quotaPerUnit,
                                       range: 1_000...10_000_000,
                                       step: 50_000,
                                       suffix: "")
                        }
                        settingRow("刷新") {
                            intControl(value: $settings.refreshIntervalSeconds,
                                       range: 15...3600,
                                       step: 15,
                                       suffix: "秒")
                        }
                        settingRow("低余额") {
                            doubleControl(value: $settings.lowBalanceThresholdUSD,
                                          range: 0...1000,
                                          step: 1,
                                          prefix: "$")
                        }
                    }
                    .padding(.top, 8)
                }
                .font(.callout)
            }
        }
        .padding(18)
        .frame(width: 520)
        .navigationTitle("设置")
        .onAppear {
            accessToken = credentials.accessToken
            lastSavedAccessToken = credentials.accessToken
        }
        .onDisappear {
            persistAccessTokenIfNeeded()
        }
    }

    private func settingsSection<Content: View>(_ title: String,
                                                @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.metricSecondary)
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.panelFill,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 0.5)
            }
        }
    }

    private func settingRow<Content: View>(_ label: String,
                                           @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .font(.callout)
                .foregroundStyle(Theme.metricSecondary)
                .frame(width: 58, alignment: .trailing)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func iconButton(_ systemName: String,
                            help: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Theme.metricSecondary)
        .background(Theme.panelFillElevated,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .help(help)
    }

    private func intControl(value: Binding<Int>,
                            range: ClosedRange<Int>,
                            step: Int,
                            suffix: String) -> some View {
        HStack(spacing: 6) {
            stepButton("minus") {
                value.wrappedValue = max(range.lowerBound, value.wrappedValue - step)
            }
            Text(valueText(value.wrappedValue, suffix: suffix))
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(Theme.accentStrong)
                .frame(width: 104)
            stepButton("plus") {
                value.wrappedValue = min(range.upperBound, value.wrappedValue + step)
            }
        }
        .padding(4)
        .background(Theme.panelFillElevated,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 0.5)
        }
    }

    private func doubleControl(value: Binding<Double>,
                               range: ClosedRange<Double>,
                               step: Double,
                               prefix: String) -> some View {
        HStack(spacing: 6) {
            stepButton("minus") {
                value.wrappedValue = max(range.lowerBound, value.wrappedValue - step)
            }
            Text("\(prefix)\(value.wrappedValue, specifier: "%.0f")")
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(Theme.accentStrong)
                .frame(width: 104)
            stepButton("plus") {
                value.wrappedValue = min(range.upperBound, value.wrappedValue + step)
            }
        }
        .padding(4)
        .background(Theme.panelFillElevated,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 0.5)
        }
    }

    private func stepButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.caption.weight(.bold))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Theme.metricSecondary)
        .background(Theme.panelFill,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func valueText(_ value: Int, suffix: String) -> String {
        let formatted = value.formatted()
        return suffix.isEmpty ? formatted : "\(formatted) \(suffix)"
    }

    @ViewBuilder
    private var statusInline: some View {
        switch verification {
        case .idle, .checking:
            EmptyView()
        case .success(let usd):
            compactBadge(String(format: "$%.2f", usd),
                         systemImage: "checkmark.circle.fill",
                         color: Theme.champagne)
        case .failure(let msg):
            compactBadge(shortError(msg),
                         systemImage: "exclamationmark.triangle.fill",
                         color: Theme.warning)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder
    private var connectionBadge: some View {
        switch verification {
        case .checking:
            compactBadge("检查中", systemImage: "clock", color: Theme.accent)
        case .success:
            compactBadge("已验证", systemImage: "checkmark.seal.fill", color: Theme.champagne)
        case .failure:
            compactBadge("未连接", systemImage: "exclamationmark.triangle.fill", color: Theme.warning)
        case .idle:
            compactBadge("待验证", systemImage: "circle.dotted", color: Theme.accent)
        }
    }

    private func compactBadge(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private var helpFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("访问令牌是 个人设置 → 系统访问令牌 → 生成令牌 处的 UUID，不是 `sk-…` 开头的 API Key。",
                  systemImage: "key.fill")
            Label("令牌只保存在 macOS Keychain；设置页关闭或验证连接时才会保存，不会每次打开弹窗都读取。",
                  systemImage: "lock.shield")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 4)
    }

    private var canVerify: Bool {
        guard URL(string: settings.serverURL)?.host != nil else { return false }
        guard !accessToken.isEmpty else { return false }
        return verification != .checking
    }

    private func openInBrowser() {
        guard var c = URLComponents(string: settings.serverURL) else { return }
        if c.path.isEmpty || c.path == "/" { c.path = "/console/personal" }
        if let url = c.url { NSWorkspace.shared.open(url) }
    }

    private func verifyConnection() async {
        verification = .checking
        guard persistAccessTokenIfNeeded() else {
            verification = .failure("令牌保存失败，请允许 Keychain 访问")
            return
        }
        guard let url = URL(string: settings.serverURL), url.host != nil else {
            verification = .failure("服务器地址无效")
            return
        }
        do {
            let resp = try await resolveAccountBinding(url: url)
            let usd = Double(resp.quota) / Double(settings.quotaPerUnit)
            verification = .success(remainingUSD: usd)
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

    private func resolveAccountBinding(url: URL) async throws -> UserSelfResponse {
        if let userID = settings.newAPIUserHeaderID {
            do {
                return try await NewAPIClient(baseURL: url,
                                             accessToken: accessToken,
                                             userID: userID).getSelf()
            } catch let err as NewAPIError {
                if err == .httpStatus(401) {
                    settings.userID = 0
                } else {
                    throw err
                }
            }
        }

        do {
            let resp = try await NewAPIClient(baseURL: url,
                                             accessToken: accessToken).getSelf()
            settings.userID = -1
            return resp
        } catch {
            // Some new-api deployments still require New-Api-User. Keep this
            // compatibility path hidden from users.
        }

        for candidate in 1...50 {
            let client = NewAPIClient(baseURL: url, accessToken: accessToken, userID: candidate)
            do {
                let resp = try await client.getSelf()
                settings.userID = candidate
                return resp
            } catch {
                continue
            }
        }
        throw NewAPIError.apiFailure("无法自动识别账号，请确认令牌来自当前服务器")
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
