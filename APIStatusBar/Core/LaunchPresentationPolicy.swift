import Foundation

enum LaunchPresentationPolicy {
    enum ActivationMode {
        case dock
        case accessory
    }

    static let statusItemAutosaveName = "com.dylan.apistatusbar.statusItem"

    static func activationMode(isReady: Bool) -> ActivationMode {
        isReady ? .accessory : .dock
    }

    static func shouldPresentSettingsOnLaunch(isReady: Bool) -> Bool {
        !isReady
    }
}
