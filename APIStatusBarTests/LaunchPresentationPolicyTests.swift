import XCTest
@testable import APIStatusBar

final class LaunchPresentationPolicyTests: XCTestCase {
    func test_shouldPresentSettingsOnLaunchUntilAppIsConfigured() {
        XCTAssertTrue(LaunchPresentationPolicy.shouldPresentSettingsOnLaunch(isReady: false))
        XCTAssertFalse(LaunchPresentationPolicy.shouldPresentSettingsOnLaunch(isReady: true))
    }

    func test_activationModeShowsDockUntilAppIsConfigured() {
        XCTAssertEqual(LaunchPresentationPolicy.activationMode(isReady: false), .dock)
        XCTAssertEqual(LaunchPresentationPolicy.activationMode(isReady: true), .accessory)
    }

    func test_statusItemAutosaveNameIsStable() {
        XCTAssertEqual(LaunchPresentationPolicy.statusItemAutosaveName,
                       "com.dylan.apistatusbar.statusItem")
    }
}
