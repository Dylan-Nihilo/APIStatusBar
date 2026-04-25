import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var accessToken: String = ""
    @State private var savedMessage: String?
    @State private var verificationState: VerificationState = .idle

    enum VerificationState: Equatable {
        case idle
        case checking
        case success(remainingUSD: Double, userID: Int)
        case failure(String)
    }

    var body: some View {
        Form {
            Section {
                TextField("Server URL", text: $settings.serverURL,
                          prompt: Text("https://api.your-host.com"))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textContentType(.URL)

                HStack {
                    Button {
                        openInBrowser()
                    } label: {
                        Label("Open in Browser", systemImage: "safari")
                    }
                    .buttonStyle(.glass)
                    .disabled(URL(string: settings.serverURL)?.host == nil)
                    .help("Open the new-api console — log in there, then come back to copy your access token and user ID")

                    Spacer()
                }
            } header: {
                Text("Server")
            } footer: {
                Text("After clicking *Open in Browser*, log in, go to Personal Settings → Generate Access Token, then come back and paste below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Credentials") {
                SecureField("Access Token", text: $accessToken,
                            prompt: Text("paste from new-api Web UI"))
                    .textFieldStyle(.roundedBorder)
                    .onAppear {
                        accessToken = (try? KeychainStore.readAccessToken()) ?? ""
                    }
                Stepper("User ID: \(settings.userID)",
                        value: $settings.userID, in: 0...10_000_000)

                HStack(spacing: 8) {
                    Button("Save Token") { saveToken() }
                        .buttonStyle(.glassProminent)
                        .tint(Theme.accent)
                        .disabled(accessToken == ((try? KeychainStore.readAccessToken()) ?? ""))

                    Button {
                        Task { await verifyConnection() }
                    } label: {
                        if verificationState == .checking {
                            HStack(spacing: 4) {
                                ProgressView().controlSize(.mini)
                                Text("Verify Connection")
                            }
                        } else {
                            Text("Verify Connection")
                        }
                    }
                    .buttonStyle(.glass)
                    .disabled(!canVerify)

                    if let msg = savedMessage {
                        Text(msg).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                verificationBanner
            }

            Section("Conversion") {
                Stepper("Quota per $1: \(settings.quotaPerUnit)",
                        value: $settings.quotaPerUnit, in: 1_000...10_000_000, step: 50_000)
            }

            Section("Polling") {
                Stepper("Refresh interval: \(settings.refreshIntervalSeconds)s",
                        value: $settings.refreshIntervalSeconds, in: 15...3600, step: 15)
                Stepper(value: $settings.lowBalanceThresholdUSD, in: 0...1000, step: 1) {
                    Text("Low-balance threshold: $\(settings.lowBalanceThresholdUSD, specifier: "%.0f")")
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 520)
    }

    @ViewBuilder
    private var verificationBanner: some View {
        switch verificationState {
        case .idle, .checking:
            EmptyView()
        case .success(let usd, let userID):
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.accent)
                Text("Connected — $\(usd, specifier: "%.2f") remaining for user #\(userID)")
                    .font(.callout)
                Spacer()
            }
            .padding(10)
            .glassEffect(.regular.tint(Theme.accent.opacity(0.25)),
                         in: RoundedRectangle(cornerRadius: 10))
        case .failure(let msg):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(msg).font(.callout)
                Spacer()
            }
            .padding(10)
            .glassEffect(.regular.tint(.red.opacity(0.2)),
                         in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var canVerify: Bool {
        guard URL(string: settings.serverURL)?.host != nil else { return false }
        guard settings.userID > 0 else { return false }
        guard !accessToken.isEmpty else { return false }
        return verificationState != .checking
    }

    private func openInBrowser() {
        guard var components = URLComponents(string: settings.serverURL) else { return }
        // Land them on the personal settings page where access tokens are minted and user_id is shown.
        if components.path.isEmpty || components.path == "/" {
            components.path = "/console/personal"
        }
        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }

    private func saveToken() {
        do {
            if accessToken.isEmpty {
                try KeychainStore.deleteAccessToken()
                savedMessage = "Token cleared"
            } else {
                try KeychainStore.setAccessToken(accessToken)
                savedMessage = "Token saved to Keychain"
            }
        } catch {
            savedMessage = "Error: \(error)"
        }
    }

    private func verifyConnection() async {
        verificationState = .checking
        guard let url = URL(string: settings.serverURL), url.host != nil else {
            verificationState = .failure("Server URL invalid")
            return
        }
        // Save the in-flight token to Keychain first so a successful verification
        // also persists it (user expectation: clicking Verify should "just work").
        do { try KeychainStore.setAccessToken(accessToken) } catch {}
        let client = NewAPIClient(baseURL: url, accessToken: accessToken, userID: settings.userID)
        do {
            let resp = try await client.getSelf()
            let usd = Double(resp.quota) / Double(settings.quotaPerUnit)
            verificationState = .success(remainingUSD: usd, userID: settings.userID)
            savedMessage = "Token saved to Keychain"
        } catch let err as NewAPIError {
            switch err {
            case .httpStatus(let code):
                verificationState = .failure("HTTP \(code) — check Server URL & token")
            case .apiFailure(let msg):
                verificationState = .failure("Server says: \(msg)")
            case .decoding:
                verificationState = .failure("Could not decode response — is this really a new-api server?")
            }
        } catch {
            verificationState = .failure("Network error: \(error.localizedDescription)")
        }
    }
}
