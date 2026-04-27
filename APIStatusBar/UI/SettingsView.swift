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
                    Button("在浏览器中打开…") { openInBrowser() }
                        .disabled(URL(string: settings.serverURL)?.host == nil)
                }
            }

            Section {
                LabeledContent("访问令牌") {
                    HStack(spacing: 6) {
                        Group {
                            if isTokenRevealed {
                                TextField("粘贴 UUID", text: $accessToken)
                            } else {
                                SecureField("粘贴 UUID", text: $accessToken)
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
                                HStack(spacing: 4) {
                                    ProgressView().controlSize(.mini)
                                    Text("验证中…")
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

            Section("换算") {
                LabeledContent("每 $1 配额") {
                    HStack(spacing: 6) {
                        TextField("", value: $settings.quotaPerUnit, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                            .multilineTextAlignment(.trailing)
                        Stepper("",
                                value: $settings.quotaPerUnit,
                                in: 1_000...10_000_000,
                                step: 50_000)
                            .labelsHidden()
                    }
                }
            }

            Section("轮询") {
                LabeledContent("刷新间隔") {
                    Stepper("\(settings.refreshIntervalSeconds) 秒",
                            value: $settings.refreshIntervalSeconds,
                            in: 15...3600, step: 15)
                }
                LabeledContent("低额度阈值") {
                    Stepper("$\(settings.lowBalanceThresholdUSD, specifier: "%.0f")",
                            value: $settings.lowBalanceThresholdUSD,
                            in: 0...1000, step: 1)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 480)
        .navigationTitle("APIStatusBar 设置")
        .onAppear {
            accessToken = credentials.accessToken
            lastSavedAccessToken = credentials.accessToken
        }
        .onDisappear {
            persistAccessTokenIfNeeded()
        }
    }

    @ViewBuilder
    private var statusInline: some View {
        switch verification {
        case .idle, .checking:
            EmptyView()
        case .success(let usd):
            Label(String(format: "$%.2f", usd), systemImage: "checkmark.circle.fill")
                .foregroundStyle(Theme.accent)
                .font(.callout)
        case .failure(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
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
