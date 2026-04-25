import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var accessToken: String = ""
    @State private var savedMessage: String?
    @State private var verification: Verification = .idle
    @State private var detection: Detection = .idle

    enum Verification: Equatable {
        case idle
        case checking
        case success(remainingUSD: Double)
        case failure(String)
    }

    enum Detection: Equatable {
        case idle
        case scanning(current: Int)
        case found(Int)
        case notFound
    }

    var body: some View {
        Form {
            Section("Server") {
                LabeledContent("URL") {
                    TextField("https://api.your-host.com", text: $settings.serverURL)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textContentType(.URL)
                        .frame(minWidth: 260)
                }

                LabeledContent("Console") {
                    Button("Open in Browser…") { openInBrowser() }
                        .buttonStyle(.bordered)
                        .disabled(URL(string: settings.serverURL)?.host == nil)
                }
            }

            Section {
                LabeledContent("Access Token") {
                    HStack(spacing: 6) {
                        SecureField("UUID from Personal Settings", text: $accessToken)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 220)
                        Button {
                            pasteFromClipboard()
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                        }
                        .buttonStyle(.bordered)
                        .help("Paste from clipboard")
                    }
                }

                LabeledContent("User ID") {
                    HStack(spacing: 6) {
                        TextField("", value: $settings.userID, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .multilineTextAlignment(.trailing)
                        Stepper("", value: $settings.userID, in: 0...10_000_000)
                            .labelsHidden()
                        Button {
                            Task { await autoDetectUserID() }
                        } label: {
                            switch detection {
                            case .scanning(let n):
                                HStack(spacing: 4) {
                                    ProgressView().controlSize(.mini)
                                    Text("Scanning #\(n)…")
                                }
                            default:
                                Text("Auto-detect")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(accessToken.isEmpty || detection == .scanning(current: 0))
                    }
                }
            } header: {
                Text("Credentials")
            } footer: {
                helpFooter
            }

            Section("Conversion") {
                LabeledContent("Quota per $1") {
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

            Section("Polling") {
                LabeledContent("Refresh interval") {
                    Stepper("\(settings.refreshIntervalSeconds) seconds",
                            value: $settings.refreshIntervalSeconds,
                            in: 15...3600,
                            step: 15)
                }
                LabeledContent("Low-balance threshold") {
                    Stepper("$\(settings.lowBalanceThresholdUSD, specifier: "%.0f")",
                            value: $settings.lowBalanceThresholdUSD,
                            in: 0...1000,
                            step: 1)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 520)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footerBar
        }
        .onAppear {
            accessToken = (try? KeychainStore.readAccessToken()) ?? ""
        }
    }

    // MARK: - Footer bar

    private var footerBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                statusLabel
                Spacer()
                Button {
                    Task { await verifyConnection() }
                } label: {
                    if verification == .checking {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.mini)
                            Text("Verifying…")
                        }
                    } else {
                        Text("Verify Connection")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!canVerify)

                Button("Save") { saveAll() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch verification {
        case .idle:
            if let msg = savedMessage {
                Label(msg, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.accent)
                    .font(.callout)
            } else {
                EmptyView()
            }
        case .checking:
            EmptyView()
        case .success(let usd):
            Label(String(format: "Connected — $%.2f remaining", usd),
                  systemImage: "checkmark.circle.fill")
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

    // MARK: - Footer help text

    @ViewBuilder
    private var helpFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Access Token is a UUID from Personal Settings → System Access Token → Generate Token. It's not the same as an `sk-…` API key.",
                  systemImage: "key.fill")
            Label("Don't know your User ID? Tap **Auto-detect** to scan 1–50 with your token.",
                  systemImage: "person.crop.circle.badge.questionmark")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 4)
    }

    // MARK: - Computed

    private var canSave: Bool {
        let stored = (try? KeychainStore.readAccessToken()) ?? ""
        return accessToken != stored || savedMessage == nil
    }

    private var canVerify: Bool {
        guard URL(string: settings.serverURL)?.host != nil else { return false }
        guard !accessToken.isEmpty, settings.userID > 0 else { return false }
        return verification != .checking
    }

    // MARK: - Actions

    private func pasteFromClipboard() {
        if let pasted = NSPasteboard.general.string(forType: .string) {
            accessToken = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
            verification = .idle
        }
    }

    private func openInBrowser() {
        guard var components = URLComponents(string: settings.serverURL) else { return }
        if components.path.isEmpty || components.path == "/" {
            components.path = "/console/personal"
        }
        if let url = components.url { NSWorkspace.shared.open(url) }
    }

    private func saveAll() {
        do {
            if accessToken.isEmpty {
                try KeychainStore.deleteAccessToken()
                savedMessage = "Token cleared"
            } else {
                try KeychainStore.setAccessToken(accessToken)
                savedMessage = "Saved"
            }
        } catch {
            savedMessage = nil
            verification = .failure("Keychain error: \(error.localizedDescription)")
        }
    }

    private func verifyConnection() async {
        verification = .checking
        guard let url = URL(string: settings.serverURL), url.host != nil else {
            verification = .failure("Server URL invalid")
            return
        }
        let client = NewAPIClient(baseURL: url, accessToken: accessToken, userID: settings.userID)
        do {
            let resp = try await client.getSelf()
            let usd = Double(resp.quota) / Double(settings.quotaPerUnit)
            verification = .success(remainingUSD: usd)
            // Persist on success.
            try? KeychainStore.setAccessToken(accessToken)
            savedMessage = nil
        } catch let err as NewAPIError {
            switch err {
            case .httpStatus(401):
                verification = .failure("HTTP 401 — User ID may not match this token. Try Auto-detect.")
            case .httpStatus(let code):
                verification = .failure("HTTP \(code) — check server URL and token")
            case .apiFailure(let msg):
                verification = .failure(msg)
            case .decoding:
                verification = .failure("Unexpected response — is this really a new-api server?")
            }
        } catch {
            verification = .failure("Network: \(error.localizedDescription)")
        }
    }

    private func autoDetectUserID() async {
        guard !accessToken.isEmpty,
              let url = URL(string: settings.serverURL), url.host != nil else { return }
        verification = .idle
        for candidate in 1...50 {
            detection = .scanning(current: candidate)
            let client = NewAPIClient(baseURL: url, accessToken: accessToken, userID: candidate)
            do {
                _ = try await client.getSelf()
                detection = .found(candidate)
                settings.userID = candidate
                verification = .success(remainingUSD: 0)
                // Re-verify to populate the actual remaining balance.
                await verifyConnection()
                return
            } catch {
                continue
            }
        }
        detection = .notFound
        verification = .failure("Couldn't find a matching User ID in 1–50. Check /console/user in your admin panel.")
    }
}
