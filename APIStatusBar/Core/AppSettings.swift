import Foundation
import Combine

/// Non-secret user preferences. The access token is NOT here — it lives in `KeychainStore`.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults: UserDefaults

    @Published var serverURL: String {
        didSet { defaults.set(serverURL, forKey: Keys.serverURL) }
    }

    @Published var userID: Int {
        didSet { defaults.set(userID, forKey: Keys.userID) }
    }

    @Published var quotaPerUnit: Int {
        didSet { defaults.set(quotaPerUnit, forKey: Keys.quotaPerUnit) }
    }

    @Published var refreshIntervalSeconds: Int {
        didSet { defaults.set(refreshIntervalSeconds, forKey: Keys.refreshIntervalSeconds) }
    }

    @Published var lowBalanceThresholdUSD: Double {
        didSet { defaults.set(lowBalanceThresholdUSD, forKey: Keys.lowBalanceThresholdUSD) }
    }

    private enum Keys {
        static let serverURL = "serverURL"
        static let userID = "userID"
        static let quotaPerUnit = "quotaPerUnit"
        static let refreshIntervalSeconds = "refreshIntervalSeconds"
        static let lowBalanceThresholdUSD = "lowBalanceThresholdUSD"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.serverURL = defaults.string(forKey: Keys.serverURL) ?? ""
        self.userID = defaults.integer(forKey: Keys.userID)
        let qpu = defaults.integer(forKey: Keys.quotaPerUnit)
        self.quotaPerUnit = qpu == 0 ? 500_000 : qpu
        let interval = defaults.integer(forKey: Keys.refreshIntervalSeconds)
        self.refreshIntervalSeconds = interval == 0 ? 60 : interval
        let threshold = defaults.double(forKey: Keys.lowBalanceThresholdUSD)
        self.lowBalanceThresholdUSD = threshold == 0 ? 5.0 : threshold
    }

    /// `userID` is an internal compatibility cache for new-api deployments
    /// that require the `New-Api-User` header. 0 = unresolved, -1 = no header
    /// needed, >0 = cached header value.
    var newAPIUserHeaderID: Int? {
        userID > 0 ? userID : nil
    }

    /// True if all fields needed for a successful API call are populated.
    var isConfigured: Bool {
        guard let url = URL(string: serverURL), url.host != nil else { return false }
        return userID != 0
    }
}
