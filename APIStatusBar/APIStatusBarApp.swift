import SwiftUI

@main
struct APIStatusBarApp: App {
    @StateObject private var settings = AppSettings.shared
    @StateObject private var poller: QuotaPoller

    init() {
        let settings = AppSettings.shared
        let token = (try? KeychainStore.readAccessToken()) ?? ""
        let baseURL = URL(string: settings.serverURL) ?? URL(string: "https://invalid.local")!
        let client = NewAPIClient(baseURL: baseURL, accessToken: token, userID: settings.userID)
        _poller = StateObject(wrappedValue: QuotaPoller(client: client,
                                                          intervalSeconds: settings.refreshIntervalSeconds))
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverHost(poller: poller, settings: settings, rebuildPoller: rebuildPollerIfNeeded)
        } label: {
            MenuBarLabel(
                snapshot: poller.snapshot,
                formatter: QuotaFormatter(quotaPerUnit: settings.quotaPerUnit),
                lowBalanceThresholdUSD: settings.lowBalanceThresholdUSD,
                hasError: poller.lastError != nil,
                isConfigured: settings.isConfigured
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(settings: settings)
                .onDisappear { rebuildPollerIfNeeded() }
        }
    }

    /// Recreate the poller's `NewAPIClient` whenever server URL / token / user ID changes.
    /// Called on popover open and on settings close.
    private func rebuildPollerIfNeeded() {
        let token = (try? KeychainStore.readAccessToken()) ?? ""
        guard let url = URL(string: settings.serverURL), url.host != nil, settings.isConfigured else {
            poller.stop()
            return
        }
        let client = NewAPIClient(baseURL: url, accessToken: token, userID: settings.userID)
        poller.replaceClient(client, intervalSeconds: settings.refreshIntervalSeconds)
        poller.start()
    }
}

/// Hosts the popover content. Lives inside a View (not Scene) so we can read
/// `@Environment(\.openSettings)` — that environment key is only available on view bodies.
private struct PopoverHost: View {
    @ObservedObject var poller: QuotaPoller
    @ObservedObject var settings: AppSettings
    let rebuildPoller: () -> Void

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        PopoverView(poller: poller, settings: settings) {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .onAppear {
            rebuildPoller()
            // Only kick off a refresh when we have a real server to talk to —
            // otherwise we get a phantom spinner while a request to invalid.local times out.
            if poller.snapshot == nil && settings.isConfigured {
                Task { await poller.refresh() }
            }
        }
    }
}
