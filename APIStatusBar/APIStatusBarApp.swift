import AppKit
import Combine
import SwiftUI

@main
@MainActor
struct APIStatusBarApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var appDelegate
    @StateObject private var settings = AppSettings.shared
    @StateObject private var credentials: CredentialStore
    @StateObject private var poller: QuotaPoller
    @StateObject private var modelStats: ModelStatsPoller
    @StateObject private var probe: ProbePoller
    private let statusItemController: StatusItemController
    private let settingsWindowController: SettingsWindowController

    init() {
        let settings = AppSettings.shared
        let credentials = CredentialStore(loadStoredToken: settings.isConfigured)
        let baseURL = URL(string: settings.serverURL) ?? URL(string: "https://invalid.local")!
        let client = NewAPIClient(baseURL: baseURL,
                                  accessToken: credentials.accessToken)
        let poller = QuotaPoller(client: client,
                                 intervalSeconds: settings.refreshIntervalSeconds)
        let modelStats = ModelStatsPoller(client: client,
                                          intervalSeconds: 300,
                                          quotaPerUnit: QuotaFormatter.quotaPerRMB)
        let probe = ProbePoller(intervalSeconds: 30)
        let settingsWindowController = SettingsWindowController(settings: settings,
                                                                credentials: credentials,
                                                                onCommit: {
                                                                    Self.rebuildPollerIfNeeded(settings: settings,
                                                                                               credentials: credentials,
                                                                                               poller: poller,
                                                                                               modelStats: modelStats,
                                                                                               probe: probe)
                                                                })
        _credentials = StateObject(wrappedValue: credentials)
        _poller = StateObject(wrappedValue: poller)
        _modelStats = StateObject(wrappedValue: modelStats)
        _probe = StateObject(wrappedValue: probe)
        let statusItemController = StatusItemController()
        self.statusItemController = statusItemController
        self.settingsWindowController = settingsWindowController
        Self.applyActivationPolicy(settings: settings, credentials: credentials)
        appDelegate.shouldPresentSettingsOnLaunch = {
            let isReady = settings.isConfigured && !credentials.accessToken.isEmpty
            return LaunchPresentationPolicy.shouldPresentSettingsOnLaunch(isReady: isReady)
        }
        appDelegate.openSettings = {
            settingsWindowController.show()
        }
        statusItemController.configure(poller: poller,
                                       modelStats: modelStats,
                                       probe: probe,
                                       credentials: credentials,
                                       settings: settings,
                                       rebuildPoller: {
                                           Self.rebuildPollerIfNeeded(settings: settings,
                                                                      credentials: credentials,
                                                                      poller: poller,
                                                                      modelStats: modelStats,
                                                                      probe: probe)
                                       },
                                       openSettings: {
                                           settingsWindowController.show()
                                       })
    }

    var body: some Scene {
        Settings {
            SettingsView(settings: settings,
                         credentials: credentials,
                         onCommit: rebuildPollerIfNeeded)
        }
        .windowResizability(.contentSize)

        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }

    private func rebuildPollerIfNeeded() {
        Self.rebuildPollerIfNeeded(settings: settings,
                                   credentials: credentials,
                                   poller: poller,
                                   modelStats: modelStats,
                                   probe: probe)
    }

    private static func rebuildPollerIfNeeded(settings: AppSettings,
                                              credentials: CredentialStore,
                                              poller: QuotaPoller,
                                              modelStats: ModelStatsPoller,
                                              probe: ProbePoller) {
        applyActivationPolicy(settings: settings, credentials: credentials)

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
        let client = NewAPIClient(baseURL: url,
                                  accessToken: token)
        poller.replaceClient(client, intervalSeconds: settings.refreshIntervalSeconds)
        poller.start()
        modelStats.replaceClient(client)
        modelStats.start()
        // Probe uses the same baseURL but no auth — public status feed.
        probe.replaceClient(StatusFeedClient(baseURL: url))
        probe.start()
    }

    private static func applyActivationPolicy(settings: AppSettings,
                                              credentials: CredentialStore) {
        let isReady = settings.isConfigured && !credentials.accessToken.isEmpty
        switch LaunchPresentationPolicy.activationMode(isReady: isReady) {
        case .dock:
            NSApp.setActivationPolicy(.regular)
        case .accessory:
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

@MainActor
private final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    var shouldPresentSettingsOnLaunch: (() -> Bool)?
    var openSettings: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor [weak self] in
            guard self?.shouldPresentSettingsOnLaunch?() == true else { return }
            self?.openSettings?()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings?()
        return true
    }
}

private struct PopoverHost: View {
    @ObservedObject var poller: QuotaPoller
    @ObservedObject var modelStats: ModelStatsPoller
    @ObservedObject var probe: ProbePoller
    @ObservedObject var credentials: CredentialStore
    @ObservedObject var settings: AppSettings
    let rebuildPoller: () -> Void
    let openSettings: () -> Void

    private var isReady: Bool {
        settings.isConfigured && !credentials.accessToken.isEmpty
    }

    var body: some View {
        PopoverView(poller: poller,
                    modelStats: modelStats,
                    probe: probe,
                    settings: settings,
                    isConfigured: isReady) {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .onAppear {
            rebuildPoller()
            if isReady {
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

@MainActor
private final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let settings: AppSettings
    private let credentials: CredentialStore
    private let onCommit: () -> Void
    private var window: NSWindow?

    init(settings: AppSettings,
         credentials: CredentialStore,
         onCommit: @escaping () -> Void) {
        self.settings = settings
        self.credentials = credentials
        self.onCommit = onCommit
    }

    func show() {
        if let window {
            present(window)
            return
        }

        let rootView = SettingsView(settings: settings,
                                    credentials: credentials,
                                    onCommit: onCommit)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "APIStatusBar 设置"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 760, height: 540)
        window.setContentSize(NSSize(width: 760, height: 580))
        window.collectionBehavior = [.moveToActiveSpace]
        window.tabbingMode = .disallowed
        window.delegate = self
        window.center()

        self.window = window
        present(window)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }

    private func present(_ window: NSWindow) {
        let isReady = settings.isConfigured && !credentials.accessToken.isEmpty
        switch LaunchPresentationPolicy.activationMode(isReady: isReady) {
        case .dock:
            NSApp.setActivationPolicy(.regular)
        case .accessory:
            NSApp.setActivationPolicy(.accessory)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

@MainActor
private final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()

    private weak var poller: QuotaPoller?
    private weak var modelStats: ModelStatsPoller?
    private weak var probe: ProbePoller?
    private weak var credentials: CredentialStore?
    private weak var settings: AppSettings?
    private var rebuildPoller: (() -> Void)?
    private var openSettings: (() -> Void)?
    private var statusMenu: NSMenu?

    func configure(poller: QuotaPoller,
                   modelStats: ModelStatsPoller,
                   probe: ProbePoller,
                   credentials: CredentialStore,
                   settings: AppSettings,
                   rebuildPoller: @escaping () -> Void,
                   openSettings: @escaping () -> Void) {
        self.poller = poller
        self.modelStats = modelStats
        self.probe = probe
        self.credentials = credentials
        self.settings = settings
        self.rebuildPoller = rebuildPoller
        self.openSettings = openSettings
        statusItem.autosaveName = LaunchPresentationPolicy.statusItemAutosaveName

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
            button.toolTip = "APIStatusBar"
        }

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 336, height: 460)
        popover.contentViewController = NSHostingController(
            rootView: PopoverHost(poller: poller,
                                  modelStats: modelStats,
                                  probe: probe,
                                  credentials: credentials,
                                  settings: settings,
                                  rebuildPoller: rebuildPoller,
                                  openSettings: { [weak self] in
                                      self?.popover.performClose(nil)
                                      openSettings()
                                  })
        )

        cancellables.removeAll()
        poller.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateStatusItemImage() }
            }
            .store(in: &cancellables)
        credentials.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateStatusItemImage() }
            }
            .store(in: &cancellables)
        settings.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateStatusItemImage() }
            }
            .store(in: &cancellables)

        updateStatusItemImage()
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
            return
        }

        if !isConfigured {
            openSettings?()
            return
        }

        if popover.isShown {
            popover.performClose(sender)
            return
        }
        showPopover(relativeTo: sender)
    }

    private func showPopover(relativeTo sender: NSStatusBarButton) {
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showStatusMenu() {
        let menu = makeStatusMenu()
        statusMenu = menu
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        addItem("打开面板", systemImage: "menubar.rectangle", to: menu, action: #selector(openPanelFromMenu))
        addItem("立即刷新", systemImage: "arrow.clockwise", to: menu, action: #selector(refreshFromMenu)).isEnabled = isConfigured
        addItem("打开控制台", systemImage: "safari", to: menu, action: #selector(openConsoleFromMenu)).isEnabled = settings?.isConfigured == true
        menu.addItem(.separator())
        addItem("设置…", systemImage: "gearshape", to: menu, action: #selector(openSettingsFromMenu))
        addItem("清除本地配置…", systemImage: "trash", to: menu, action: #selector(clearLocalDataFromMenu))
        menu.addItem(.separator())
        addItem("退出 APIStatusBar", systemImage: "power", to: menu, action: #selector(quitFromMenu))

        return menu
    }

    @discardableResult
    private func addItem(_ title: String,
                         systemImage: String,
                         to menu: NSMenu,
                         action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
        menu.addItem(item)
        return item
    }

    @objc private func openPanelFromMenu() {
        guard isConfigured, let button = statusItem.button else {
            openSettings?()
            return
        }
        showPopover(relativeTo: button)
    }

    @objc private func refreshFromMenu() {
        guard isConfigured,
              let poller,
              let modelStats,
              let probe else { return }

        Task {
            await poller.refresh()
            await modelStats.refresh()
            await probe.refresh()
        }
    }

    @objc private func openConsoleFromMenu() {
        guard let settings,
              var components = URLComponents(string: settings.serverURL),
              components.host != nil else {
            openSettings?()
            return
        }

        if components.path.isEmpty || components.path == "/" {
            components.path = "/console/personal"
        }
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openSettingsFromMenu() {
        popover.performClose(nil)
        openSettings?()
    }

    @objc private func clearLocalDataFromMenu() {
        let alert = NSAlert()
        alert.messageText = "清除本地配置？"
        alert.informativeText = "这会删除服务器地址、轮询设置和本应用保存的访问令牌，不会影响你的 New API 服务器。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "清除")
        alert.addButton(withTitle: "取消")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        clearLocalData()
    }

    private func clearLocalData() {
        popover.performClose(nil)
        poller?.stop()
        modelStats?.stop()
        probe?.replaceClient(nil)
        probe?.stop()
        _ = credentials?.clearAccessToken()
        settings?.resetToDefaults()
        rebuildPoller?()
        updateStatusItemImage()
        openSettings?()
    }

    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
    }

    private func updateStatusItemImage() {
        guard let button = statusItem.button,
              let settings,
              let credentials,
              let poller else { return }

        let isConfigured = settings.isConfigured && !credentials.accessToken.isEmpty
        let image = Self.makeAngularOpenAIStatusImage()
        if !isConfigured {
            button.contentTintColor = .secondaryLabelColor
        } else if poller.lastError != nil {
            button.contentTintColor = .systemYellow
        } else {
            button.contentTintColor = Self.isLowBalance(settings: settings, poller: poller) ? .systemYellow : nil
        }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        button.image = image
    }

    private static func isLowBalance(settings: AppSettings, poller: QuotaPoller) -> Bool {
        guard let snapshot = poller.snapshot else { return false }
        let formatter = QuotaFormatter(quotaPerUnit: settings.quotaPerUnit)
        return formatter.rmb(fromRaw: snapshot.quotaRaw) < settings.lowBalanceThresholdRMB
    }

    private var isConfigured: Bool {
        guard let settings, let credentials else { return false }
        return settings.isConfigured && !credentials.accessToken.isEmpty
    }

    private static func makeAngularOpenAIStatusImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            for index in 0..<6 {
                let path = NSBezierPath()
                let points = Self.angularOpenAIArm(rotatedBy: index)
                guard let first = points.first else { continue }
                path.move(to: first)
                for point in points.dropFirst() {
                    path.line(to: point)
                }
                path.lineWidth = 1.3
                path.lineJoinStyle = .miter
                path.lineCapStyle = .butt
                path.stroke()
            }
            return true
        }
        image.accessibilityDescription = "APIStatusBar"
        image.isTemplate = true
        return image
    }

    private static func angularOpenAIArm(rotatedBy index: Int) -> [NSPoint] {
        let center = NSPoint(x: 9, y: 9)
        let scale: CGFloat = 1.22
        let base = [
            NSPoint(x: 1.35, y: -0.7),
            NSPoint(x: 4.15, y: -2.35),
            NSPoint(x: 5.95, y: -1.25),
            NSPoint(x: 5.95, y: 2.1),
            NSPoint(x: 4.45, y: 2.95),
            NSPoint(x: 4.45, y: 0.25),
            NSPoint(x: 2.25, y: -1.0)
        ]
        let angle = Double(index) * Double.pi / 3
        let cosine = CGFloat(cos(angle))
        let sine = CGFloat(sin(angle))
        return base.map { point in
            let x = point.x * scale
            let y = point.y * scale
            return NSPoint(x: center.x + x * cosine - y * sine,
                           y: center.y + x * sine + y * cosine)
        }
    }

    private static func makeFallbackImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()
        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: 4, y: 4, width: 10, height: 10)).fill()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
