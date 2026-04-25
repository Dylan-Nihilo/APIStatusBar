import Foundation
import SwiftUI
import Combine

/// Periodic health probe of the gateway. Maintains a rolling history so the
/// popover can render a time-series bar chart. v0.1 produces mocked data —
/// `mockSnapshot(at:)` will be swapped in M2 for a real GET against
/// `/api/status` (or a synthetic chat completion) measuring latency and 200/ok.
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

    let maxHistory: Int
    private let intervalSeconds: Int
    private var loop: Task<Void, Never>?

    init(intervalSeconds: Int = 30, maxHistory: Int = 60) {
        self.intervalSeconds = intervalSeconds
        self.maxHistory = maxHistory
        // Pre-populate so the chart isn't empty on first popover open.
        let seeded = generateMockHistory(count: maxHistory, intervalSeconds: intervalSeconds)
        self.history = seeded
        self.snapshot = seeded.last
    }

    func refresh() async {
        let new = mockSnapshot(at: Date())
        snapshot = new
        history.append(new)
        if history.count > maxHistory {
            history.removeFirst(history.count - maxHistory)
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

    // MARK: - Mock generation

    /// 95% healthy / 4% degraded / 1% down. Latency clusters 80–180ms healthy,
    /// 250–600ms degraded, 0 when down.
    private func mockSnapshot(at timestamp: Date) -> Snapshot {
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

    /// Walks backward from now, generating one sample per `intervalSeconds`.
    private func generateMockHistory(count: Int, intervalSeconds: Int) -> [Snapshot] {
        let now = Date()
        return (0..<count).reversed().map { i in
            let offset = TimeInterval(intervalSeconds * i)
            let ts = now.addingTimeInterval(-offset)
            return mockSnapshot(at: ts)
        }
    }
}
