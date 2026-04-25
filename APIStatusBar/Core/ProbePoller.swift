import Foundation
import SwiftUI
import Combine

/// Periodic health probe of the gateway. v0.1 returns mocked data so the UI
/// can be designed and verified end-to-end. M2 will swap `mockSnapshot()`
/// for a real call (likely a tiny GET against `/api/status` or a synthetic
/// chat completion against the cheapest model with a 5s timeout, measuring
/// latency and asserting 200/success).
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

    struct Snapshot: Equatable {
        let health: Health
        let latencyMS: Int
        let timestamp: Date
    }

    @Published private(set) var snapshot: Snapshot?

    private let intervalSeconds: Int
    private var loop: Task<Void, Never>?

    init(intervalSeconds: Int = 30) {
        self.intervalSeconds = intervalSeconds
    }

    func refresh() async {
        snapshot = mockSnapshot()
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

    /// 95% healthy / 4% degraded / 1% down. Latency normally clusters 80–180ms,
    /// degraded shifts to 250–600ms, down → 0 (no response).
    private func mockSnapshot() -> Snapshot {
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
        return Snapshot(health: health, latencyMS: latency, timestamp: Date())
    }
}
