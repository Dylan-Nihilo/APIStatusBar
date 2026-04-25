import Foundation
import SwiftUI
import Combine

/// Periodic health probe of the gateway. When a `KaizoStatusClient` is
/// supplied, fetches real heartbeats from `/status/status.json` and renders
/// them; without one, falls back to mocked data so the UI works on first
/// launch / unconfigured.
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
            case .unknown:  return "Checking…"
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
    /// Display name of the channel whose timeline is currently rendered.
    /// Nil when no real source is wired (mock mode).
    @Published private(set) var primaryChannelName: String?
    /// 24h uptime fraction (0…1) for the primary channel, when known.
    @Published private(set) var uptime24h: Double?
    @Published private(set) var lastError: Error?

    let maxHistory: Int
    private var statusClient: KaizoStatusClient?
    private var intervalSeconds: Int
    private var loop: Task<Void, Never>?

    init(intervalSeconds: Int = 30, maxHistory: Int = 60) {
        self.intervalSeconds = intervalSeconds
        self.maxHistory = maxHistory
        // Pre-populate so the chart isn't empty on first popover open.
        let seeded = Self.generateMockHistory(count: maxHistory, intervalSeconds: intervalSeconds)
        self.history = seeded
        self.snapshot = seeded.last
    }

    func refresh() async {
        if let client = statusClient {
            await refreshReal(client)
        } else {
            await appendMock()
        }
    }

    func start() {
        stop()
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

    /// Swap source. Pass nil to revert to mock. Adjusts polling cadence to
    /// match the data source (real status feed updates every 5 min on the
    /// server, so 5-min polling is right; mock cycles every 30s for variety).
    func replaceClient(_ client: KaizoStatusClient?) {
        stop()
        statusClient = client
        intervalSeconds = client == nil ? 30 : 300
    }

    // MARK: - Real source

    private func refreshReal(_ client: KaizoStatusClient) async {
        do {
            let data = try await client.fetchStatus()
            apply(data)
            lastError = nil
        } catch {
            lastError = error
        }
    }

    /// Convert the status feed into the popover's local view model.
    /// - bars: heartbeat timeline of the primary channel (last `maxHistory`)
    /// - header status: overall across ALL channels (allUp/anyUp/none)
    /// - uptime: primary channel's 24h figure
    private func apply(_ data: StatusData) {
        // Pick a primary monitor to render bars for: highest priority, then
        // smallest id. If any monitor has explicit priority > 0, use that;
        // otherwise fall through to the first one in the first group.
        let monitors = data.groups.flatMap(\.monitors)
        guard let primary = monitors.sorted(by: primaryRank).first else {
            history = []
            snapshot = nil
            primaryChannelName = nil
            uptime24h = nil
            return
        }

        // Convert primary's heartbeats to Snapshots.
        let beats = data.heartbeatList[String(primary.id)] ?? []
        let bars: [Snapshot] = beats.compactMap { beat in
            guard let date = KaizoStatusHelpers.date(from: beat.time) else { return nil }
            return Snapshot(timestamp: date,
                             health: Self.health(for: beat),
                             latencyMS: beat.ping)
        }
        history = Array(bars.suffix(maxHistory))

        // Header status reflects OVERALL — not just primary.
        let overallHealth = Self.overallHealth(monitors: monitors,
                                                heartbeats: data.heartbeatList)
        // Latency on the header = primary's most recent beat.
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

    /// Per-doc `getOverallStatus`:
    ///   all latest UP   → healthy (operational)
    ///   any UP          → degraded (partial outage)
    ///   none UP         → down (major outage)
    /// `unknown` only when there are no channels at all.
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

    /// Per-bar health: status=1 with reasonable ping → healthy; status=1 with
    /// ping > 1500ms → degraded (slow but technically up); status=0 → down.
    private static func health(for beat: Heartbeat) -> Health {
        switch beat.status {
        case 1:  return beat.ping > 1500 ? .degraded : .healthy
        case 0:  return .down
        default: return .unknown
        }
    }

    // MARK: - Mock source (fallback)

    private func appendMock() async {
        let new = Self.mockSnapshot(at: Date())
        snapshot = new
        history.append(new)
        if history.count > maxHistory {
            history.removeFirst(history.count - maxHistory)
        }
        primaryChannelName = nil
        uptime24h = nil
    }

    /// 95% healthy / 4% degraded / 1% down. Latency clusters 80–180ms healthy,
    /// 250–600ms degraded, 0 when down.
    private static func mockSnapshot(at timestamp: Date) -> Snapshot {
        let r = Int.random(in: 0..<100)
        let health: Health
        let latency: Int
        switch r {
        case 0..<95:
            health = .healthy
            latency = Int.random(in: 80...180)
        case 95..<99:
            health = .degraded
            latency = Int.random(in: 250...600)
        default:
            health = .down
            latency = 0
        }
        return Snapshot(timestamp: timestamp, health: health, latencyMS: latency)
    }

    private static func generateMockHistory(count: Int, intervalSeconds: Int) -> [Snapshot] {
        let now = Date()
        return (0..<count).reversed().map { i in
            let offset = TimeInterval(intervalSeconds * i)
            let ts = now.addingTimeInterval(-offset)
            return mockSnapshot(at: ts)
        }
    }
}
