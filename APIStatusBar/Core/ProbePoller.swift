import Foundation
import SwiftUI
import Combine

/// Periodic health probe driven by `KaizoStatusClient`. With a client wired,
/// fetches `/status/status.json` every 5 minutes and surfaces:
/// - the primary channel's heartbeat history (for the bar chart),
/// - the OVERALL health across all channels (for the header status dot),
/// - the primary channel's 24h uptime fraction.
///
/// Without a client (unconfigured or service unreachable), produces no data —
/// no fakes, no mocks. Callers render a grayscale placeholder.
@MainActor
final class ProbePoller: ObservableObject {
    enum Health: String, Equatable {
        case healthy
        case degraded
        case down
        case unknown

        var color: Color {
            switch self {
            case .healthy:  return .green
            case .degraded: return .yellow
            case .down:     return .red
            case .unknown:  return .gray
            }
        }

        var label: String {
            switch self {
            case .healthy:  return "All systems normal"
            case .degraded: return "Degraded"
            case .down:     return "Service down"
            case .unknown:  return "Awaiting probe"
            }
        }
    }

    struct Snapshot: Equatable, Identifiable {
        let timestamp: Date
        let health: Health
        let latencyMS: Int
        var id: TimeInterval { timestamp.timeIntervalSince1970 }
    }

    @Published private(set) var history: [Snapshot] = []
    @Published private(set) var snapshot: Snapshot?
    @Published private(set) var primaryChannelName: String?
    @Published private(set) var uptime24h: Double?
    @Published private(set) var lastError: Error?

    let maxHistory: Int
    private var statusClient: KaizoStatusClient?
    private let intervalSeconds: Int
    private var loop: Task<Void, Never>?

    init(intervalSeconds: Int = 300, maxHistory: Int = 60) {
        self.intervalSeconds = intervalSeconds
        self.maxHistory = maxHistory
    }

    func refresh() async {
        guard let client = statusClient else {
            // No service → no data. Caller renders gray placeholder.
            return
        }
        do {
            let data = try await client.fetchStatus()
            apply(data)
            lastError = nil
        } catch {
            lastError = error
        }
    }

    func start() {
        stop()
        guard statusClient != nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let interval = self.intervalSeconds
                try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    /// Pass nil to clear all state and stop polling. Pass a client to start
    /// fetching real data; caller must `start()` afterwards.
    func replaceClient(_ client: KaizoStatusClient?) {
        stop()
        statusClient = client
        if client == nil {
            history = []
            snapshot = nil
            primaryChannelName = nil
            uptime24h = nil
            lastError = nil
        }
    }

    // MARK: - Apply real data

    /// Fold the status feed into the popover's view model.
    private func apply(_ data: StatusData) {
        let monitors = data.groups.flatMap(\.monitors)
        guard let primary = monitors.sorted(by: primaryRank).first else {
            history = []
            snapshot = nil
            primaryChannelName = nil
            uptime24h = nil
            return
        }

        let beats = data.heartbeatList[String(primary.id)] ?? []
        let bars: [Snapshot] = beats.compactMap { beat in
            guard let date = KaizoStatusHelpers.date(from: beat.time) else { return nil }
            return Snapshot(timestamp: date,
                             health: Self.health(for: beat),
                             latencyMS: beat.ping)
        }
        history = Array(bars.suffix(maxHistory))

        let overallHealth = Self.overallHealth(monitors: monitors,
                                                heartbeats: data.heartbeatList)
        let latestPrimary = beats.last
        snapshot = Snapshot(
            timestamp: latestPrimary.flatMap { KaizoStatusHelpers.date(from: $0.time) } ?? Date(),
            health: overallHealth,
            latencyMS: latestPrimary?.ping ?? 0
        )

        primaryChannelName = primary.name
        uptime24h = data.uptimeList["\(primary.id)_24"] ?? nil
    }

    /// Sort key: highest priority first, then smallest id.
    private func primaryRank(_ a: Monitor, _ b: Monitor) -> Bool {
        if a.priority != b.priority { return a.priority > b.priority }
        return a.id < b.id
    }

    /// Per the doc's getOverallStatus rules:
    ///   all channels' latest beat UP   → healthy
    ///   any UP                          → degraded
    ///   none UP                         → down
    private static func overallHealth(monitors: [Monitor],
                                       heartbeats: [String: [Heartbeat]]) -> Health {
        guard !monitors.isEmpty else { return .unknown }
        var allUp = true
        var anyUp = false
        for monitor in monitors {
            let beats = heartbeats[String(monitor.id)] ?? []
            let isUp = beats.last?.status == 1
            if isUp { anyUp = true } else { allUp = false }
        }
        if allUp { return .healthy }
        if anyUp { return .degraded }
        return .down
    }

    /// Per-bar health: status=1 + ping ≤ 1500ms → healthy; status=1 + ping >
    /// 1500ms → degraded (slow but UP); status=0 → down.
    private static func health(for beat: Heartbeat) -> Health {
        switch beat.status {
        case 1:  return beat.ping > 1500 ? .degraded : .healthy
        case 0:  return .down
        default: return .unknown
        }
    }
}
