import SwiftUI

@main
struct APIStatusBarApp: App {
    @StateObject private var settings = AppSettings.shared
    @StateObject private var credentials: CredentialStore
    @StateObject private var poller: QuotaPoller
    @StateObject private var modelStats: ModelStatsPoller
    @StateObject private var probe = ProbePoller(intervalSeconds: 30)

    init() {
        let settings = AppSettings.shared
        let credentials = CredentialStore()
        let baseURL = URL(string: settings.serverURL) ?? URL(string: "https://invalid.local")!
        let client = NewAPIClient(baseURL: baseURL,
                                  accessToken: credentials.accessToken,
                                  userID: settings.userID)
        _credentials = StateObject(wrappedValue: credentials)
        _poller = StateObject(wrappedValue: QuotaPoller(client: client,
                                                          intervalSeconds: settings.refreshIntervalSeconds))
        _modelStats = StateObject(wrappedValue: ModelStatsPoller(client: client,
                                                                  intervalSeconds: 300,
                                                                  quotaPerUnit: settings.quotaPerUnit))
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverHost(poller: poller,
                         modelStats: modelStats,
                         probe: probe,
                         settings: settings,
                         rebuildPoller: rebuildPollerIfNeeded)
        } label: {
            MenuBarLabel(
                snapshot: poller.snapshot,
                formatter: QuotaFormatter(quotaPerUnit: settings.quotaPerUnit),
                lowBalanceThresholdUSD: settings.lowBalanceThresholdUSD,
                hasError: poller.lastError != nil,
                isConfigured: settings.isConfigured,
                topProviderAsset: modelStats.topProviders.first?.providerAsset
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(settings: settings, credentials: credentials)
                .onDisappear { rebuildPollerIfNeeded() }
        }
        .windowResizability(.contentSize)
    }

    private func rebuildPollerIfNeeded() {
        let token = credentials.accessToken
        guard let url = URL(string: settings.serverURL),
              url.host != nil,
              settings.isConfigured,
              !token.isEmpty else {
            poller.stop()
            modelStats.stop()
            probe.replaceClient(nil)
            probe.stop()
            return
        }
        let client = NewAPIClient(baseURL: url, accessToken: token, userID: settings.userID)
        poller.replaceClient(client, intervalSeconds: settings.refreshIntervalSeconds)
        poller.start()
        modelStats.replaceClient(client)
        modelStats.start()
        // Probe uses the same baseURL but no auth — public status feed.
        probe.replaceClient(KaizoStatusClient(baseURL: url))
        probe.start()
    }
}

private struct PopoverHost: View {
    @ObservedObject var poller: QuotaPoller
    @ObservedObject var modelStats: ModelStatsPoller
    @ObservedObject var probe: ProbePoller
    @ObservedObject var settings: AppSettings
    let rebuildPoller: () -> Void

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        PopoverView(poller: poller, modelStats: modelStats, probe: probe, settings: settings) {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .onAppear {
            rebuildPoller()
            if settings.isConfigured {
                if poller.snapshot == nil {
                    Task { await poller.refresh() }
                }
                if modelStats.topProviders.isEmpty {
                    Task { await modelStats.refresh() }
                }
                if probe.snapshot == nil {
                    Task { await probe.refresh() }
                }
            }
        }
    }
}
