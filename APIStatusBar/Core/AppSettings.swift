import Foundation
import Combine

/// Non-secret user preferences. The access token is NOT here — it lives in `KeychainStore`.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    static let defaultRefreshIntervalSeconds = 60
    static let defaultLowBalanceThresholdRMB = 5.0

    private let defaults: UserDefaults

    @Published var serverURL: String {
        didSet { defaults.set(serverURL, forKey: Keys.serverURL) }
    }

    let quotaPerUnit: Int = QuotaFormatter.quotaPerRMB

    @Published var refreshIntervalSeconds: Int {
        didSet { defaults.set(refreshIntervalSeconds, forKey: Keys.refreshIntervalSeconds) }
    }

    @Published var lowBalanceThresholdRMB: Double {
        didSet { defaults.set(lowBalanceThresholdRMB, forKey: Keys.lowBalanceThresholdRMB) }
    }

    private enum Keys {
        static let serverURL = "serverURL"
        static let refreshIntervalSeconds = "refreshIntervalSeconds"
        static let lowBalanceThresholdUSD = "lowBalanceThresholdUSD"
        static let lowBalanceThresholdRMB = "lowBalanceThresholdRMB"
        static let lowBalanceThresholdMigrationVersion = "lowBalanceThresholdMigrationVersion"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.serverURL = defaults.string(forKey: Keys.serverURL) ?? ""
        let interval = defaults.integer(forKey: Keys.refreshIntervalSeconds)
        self.refreshIntervalSeconds = interval == 0 ? Self.defaultRefreshIntervalSeconds : interval
        let rmbThreshold = defaults.double(forKey: Keys.lowBalanceThresholdRMB)
        let migrationVersion = defaults.integer(forKey: Keys.lowBalanceThresholdMigrationVersion)
        if migrationVersion < 2 {
            let legacyWrongMultiplier = 7.2
            if rmbThreshold > 0 {
                self.lowBalanceThresholdRMB = rmbThreshold / legacyWrongMultiplier
            } else {
                let usdThreshold = defaults.double(forKey: Keys.lowBalanceThresholdUSD)
                self.lowBalanceThresholdRMB = usdThreshold == 0 ? Self.defaultLowBalanceThresholdRMB : usdThreshold
            }
            defaults.set(self.lowBalanceThresholdRMB, forKey: Keys.lowBalanceThresholdRMB)
            defaults.set(2, forKey: Keys.lowBalanceThresholdMigrationVersion)
        } else if rmbThreshold > 0 {
            self.lowBalanceThresholdRMB = rmbThreshold
        } else {
            let usdThreshold = defaults.double(forKey: Keys.lowBalanceThresholdUSD)
            self.lowBalanceThresholdRMB = usdThreshold == 0 ? Self.defaultLowBalanceThresholdRMB : usdThreshold
        }
    }

    /// True if all fields needed for a successful API call are populated.
    var isConfigured: Bool {
        guard let url = URL(string: serverURL), url.host != nil else { return false }
        return true
    }

    func resetToDefaults() {
        serverURL = ""
        refreshIntervalSeconds = Self.defaultRefreshIntervalSeconds
        lowBalanceThresholdRMB = Self.defaultLowBalanceThresholdRMB

        defaults.removeObject(forKey: Keys.lowBalanceThresholdUSD)
        defaults.set(2, forKey: Keys.lowBalanceThresholdMigrationVersion)
    }
}
