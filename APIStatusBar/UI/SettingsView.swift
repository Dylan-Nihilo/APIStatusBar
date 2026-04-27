import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var credentials: CredentialStore
    @State private var accessToken: String = ""
    @State private var isTokenRevealed: Bool = false
    @State private var verification: Verification = .idle
    @State private var lastSavedAccessToken: String = ""
    @FocusState private var tokenFocused: Bool

    enum Verification: Equatable {
        case idle
        case checking
        case success(remainingUSD: Double)
        case failure(String)
    }

    var body: some View {
        Form {
            Section("服务器") {
                LabeledContent("地址") {
                    TextField("https://api.your-host.com", text: $settings.serverURL)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textContentType(.URL)
                        .frame(minWidth: 240)
                }

                LabeledContent("控制台") {
                    Button("打开") { openInBrowser() }
                        .disabled(URL(string: settings.serverURL)?.host == nil)
                }
            }

            Section {
                LabeledContent("令牌") {
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
                        .frame(minWidth: 200)
                        .onChange(of: accessToken) { _, _ in
                            verification = .idle
                        }

                        Button {
                            isTokenRevealed.toggle()
                            tokenFocused = true
                        } label: {
                            Image(systemName: isTokenRevealed ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                        .help(isTokenRevealed ? "隐藏令牌" : "显示令牌")

                        Button {
                            if let pasted = NSPasteboard.general.string(forType: .string) {
                                accessToken = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                        }
                        .buttonStyle(.borderless)
                        .help("从剪贴板粘贴")
                    }
                }

                LabeledContent("连接") {
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
            } header: {
                Text("凭据")
            } footer: {
                helpFooter
            }

            Section("计费与轮询") {
                LabeledContent("每 $1") {
                    Stepper("\(settings.quotaPerUnit.formatted())",
                            value: $settings.quotaPerUnit,
                            in: 1_000...10_000_000,
                            step: 50_000)
                }
                LabeledContent("刷新间隔") {
                    Stepper("\(settings.refreshIntervalSeconds) 秒",
                            value: $settings.refreshIntervalSeconds,
                            in: 15...3600, step: 15)
                }
                LabeledContent("低余额阈值") {
                    Stepper("$\(settings.lowBalanceThresholdUSD, specifier: "%.0f")",
                            value: $settings.lowBalanceThresholdUSD,
                            in: 0...1000, step: 1)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .navigationTitle("APIStatusBar 设置")
        .onAppear {
            accessToken = credentials.accessToken
            lastSavedAccessToken = credentials.accessToken
        }
        .onDisappear {
            persistAccessTokenIfNeeded()
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var statusInline: some View {
        switch verification {
        case .idle, .checking:
            EmptyView()
        case .success(let usd):
            Label(String(format: "$%.2f", usd), systemImage: "checkmark.circle.fill")
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

    @ViewBuilder
    private var helpFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("访问令牌是 个人设置 → 系统访问令牌 → 生成令牌 处的 UUID，不是 `sk-…` 开头的 API Key。",
                  systemImage: "key.fill")
            Label("令牌只保存在 macOS Keychain；设置页关闭或验证连接时才会保存。",
                  systemImage: "lock.shield")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: - Computed

    private var canVerify: Bool {
        guard URL(string: settings.serverURL)?.host != nil else { return false }
        guard !accessToken.isEmpty else { return false }
        return verification != .checking
    }

    // MARK: - Actions

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
            let resp = try await NewAPIClient(baseURL: url,
                                             accessToken: accessToken).getSelf()
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
