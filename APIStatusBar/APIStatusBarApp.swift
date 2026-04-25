import SwiftUI

@main
struct APIStatusBarApp: App {
    @StateObject private var settings = AppSettings.shared
    @StateObject private var poller: QuotaPoller
    @StateObject private var modelStats: ModelStatsPoller

    init() {
        let settings = AppSettings.shared
        let token = (try? KeychainStore.readAccessToken()) ?? ""
        let baseURL = URL(string: settings.serverURL) ?? URL(string: "https://invalid.local")!
        let client = NewAPIClient(baseURL: baseURL, accessToken: token, userID: settings.userID)
        _poller = StateObject(wrappedValue: QuotaPoller(client: client,
                                                          intervalSeconds: settings.refreshIntervalSeconds))
        _modelStats = StateObject(wrappedValue: ModelStatsPoller(client: client,
                                                                  intervalSeconds: 300))
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverHost(poller: poller,
                         modelStats: modelStats,
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
            SettingsView(settings: settings)
                .onDisappear { rebuildPollerIfNeeded() }
        }
        .windowResizability(.contentSize)
    }

    /// Recreate both pollers' clients when server / token / user ID change.
    private func rebuildPollerIfNeeded() {
        let token = (try? KeychainStore.readAccessToken()) ?? ""
        guard let url = URL(string: settings.serverURL), url.host != nil, settings.isConfigured else {
            poller.stop()
            modelStats.stop()
            return
        }
        let client = NewAPIClient(baseURL: url, accessToken: token, userID: settings.userID)
        poller.replaceClient(client, intervalSeconds: settings.refreshIntervalSeconds)
        poller.start()
        modelStats.replaceClient(client)
        modelStats.start()
    }
}

private struct PopoverHost: View {
    @ObservedObject var poller: QuotaPoller
    @ObservedObject var modelStats: ModelStatsPoller
    @ObservedObject var settings: AppSettings
    let rebuildPoller: () -> Void

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        PopoverView(poller: poller, modelStats: modelStats, settings: settings) {
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
            }
        }
    }
}
