import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var accessToken: String = ""
    @State private var isTokenRevealed: Bool = false
    @State private var verification: Verification = .idle
    @State private var detection: Detection = .idle
    @FocusState private var tokenFocused: Bool

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
                        .frame(minWidth: 240)
                }

                LabeledContent("Console") {
                    Button("Open in Browser…") { openInBrowser() }
                        .disabled(URL(string: settings.serverURL)?.host == nil)
                }
            }

            Section {
                LabeledContent("Access Token") {
                    HStack(spacing: 6) {
                        Group {
                            if isTokenRevealed {
                                TextField("paste UUID", text: $accessToken)
                            } else {
                                SecureField("paste UUID", text: $accessToken)
                            }
                        }
                        .focused($tokenFocused)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .frame(minWidth: 200)
                        .onChange(of: accessToken) { _, newValue in
                            try? KeychainStore.setAccessToken(newValue)
                            verification = .idle
                        }

                        Button {
                            isTokenRevealed.toggle()
                            tokenFocused = true
                        } label: {
                            Image(systemName: isTokenRevealed ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                        .help(isTokenRevealed ? "Hide token" : "Show token")

                        Button {
                            if let pasted = NSPasteboard.general.string(forType: .string) {
                                accessToken = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                        }
                        .buttonStyle(.borderless)
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
                        Button("Auto-detect") {
                            Task { await autoDetectUserID() }
                        }
                        .disabled(accessToken.isEmpty || isScanning)
                    }
                }

                LabeledContent("Connection") {
                    HStack(spacing: 8) {
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
                        .disabled(!canVerify)

                        statusInline
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
                    Stepper("\(settings.refreshIntervalSeconds) s",
                            value: $settings.refreshIntervalSeconds,
                            in: 15...3600, step: 15)
                }
                LabeledContent("Low-balance threshold") {
                    Stepper("$\(settings.lowBalanceThresholdUSD, specifier: "%.0f")",
                            value: $settings.lowBalanceThresholdUSD,
                            in: 0...1000, step: 1)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 480)
        .navigationTitle("APIStatusBar Settings")
        .onAppear {
            accessToken = (try? KeychainStore.readAccessToken()) ?? ""
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
            Label("Token is the UUID from Personal Settings → System Access Token → Generate Token. Not an `sk-…` API key.",
                  systemImage: "key.fill")
            Label("If User ID 1 fails to verify, tap **Auto-detect** to scan 1–50 with your token.",
                  systemImage: "person.crop.circle.badge.questionmark")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 4)
    }

    private var canVerify: Bool {
        guard URL(string: settings.serverURL)?.host != nil else { return false }
        guard !accessToken.isEmpty, settings.userID > 0 else { return false }
        return verification != .checking
    }

    private var isScanning: Bool {
        if case .scanning = detection { return true }
        return false
    }

    private func openInBrowser() {
        guard var c = URLComponents(string: settings.serverURL) else { return }
        if c.path.isEmpty || c.path == "/" { c.path = "/console/personal" }
        if let url = c.url { NSWorkspace.shared.open(url) }
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
        } catch let err as NewAPIError {
            switch err {
            case .httpStatus(401):
                verification = .failure("HTTP 401 — User ID may not match this token")
            case .httpStatus(let code):
                verification = .failure("HTTP \(code)")
            case .apiFailure(let msg):
                verification = .failure(msg)
            case .decoding:
                verification = .failure("Unexpected response")
            }
        } catch {
            verification = .failure(error.localizedDescription)
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
                await verifyConnection()
                return
            } catch {
                continue
            }
        }
        detection = .notFound
        verification = .failure("No matching ID in 1–50. Check /console/user.")
    }
}
