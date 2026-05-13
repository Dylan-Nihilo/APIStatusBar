import XCTest
@testable import APIStatusBar

@MainActor
final class AppSettingsTests: XCTestCase {
    func test_resetToDefaultsClearsConfigurationInputs() {
        let suiteName = "com.dylan.apistatusbar.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("https://newapi.example.com", forKey: "serverURL")
        defaults.set(300, forKey: "refreshIntervalSeconds")
        defaults.set(30.0, forKey: "lowBalanceThresholdRMB")

        let settings = AppSettings(defaults: defaults)
        settings.resetToDefaults()

        XCTAssertEqual(settings.serverURL, "")
        XCTAssertEqual(settings.refreshIntervalSeconds, AppSettings.defaultRefreshIntervalSeconds)
        XCTAssertEqual(settings.lowBalanceThresholdRMB, AppSettings.defaultLowBalanceThresholdRMB)
        XCTAssertFalse(settings.isConfigured)
    }
}
