import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var accessToken: String = ""
    @State private var savedMessage: String?

    var body: some View {
        Form {
            Section("Server") {
                TextField("Server URL", text: $settings.serverURL, prompt: Text("https://api.example.com"))
                    .textFieldStyle(.roundedBorder)
                TextField("Access Token", text: $accessToken, prompt: Text("paste from Web UI"))
                    .textFieldStyle(.roundedBorder)
                    .onAppear {
                        accessToken = (try? KeychainStore.readAccessToken()) ?? ""
                    }
                Stepper("User ID: \(settings.userID)",
                        value: $settings.userID, in: 0...10_000_000)
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

            HStack {
                Button("Save Token") { saveToken() }
                    .glassEffect(.regular.tint(Theme.accent.opacity(0.4)).interactive(),
                                 in: Capsule())
                    .buttonStyle(.plain)
                if let msg = savedMessage {
                    Text(msg).foregroundStyle(.secondary).font(.caption)
                }
                Spacer()
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 480)
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
}
