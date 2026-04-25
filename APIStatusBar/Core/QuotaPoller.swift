import Foundation
import Combine

@MainActor
final class QuotaPoller: ObservableObject {
    @Published private(set) var snapshot: QuotaSnapshot?
    @Published private(set) var lastError: Error?
    @Published private(set) var isRefreshing: Bool = false

    private var client: NewAPIClient
    private var intervalSeconds: Int
    private let now: () -> Date
    private var loop: Task<Void, Never>?

    init(client: NewAPIClient, intervalSeconds: Int, now: @escaping () -> Date = Date.init) {
        self.client = client
        self.intervalSeconds = intervalSeconds
        self.now = now
    }

    /// Performs a single fetch. Updates `snapshot` on success, or `lastError` on failure
    /// (without clearing a previously-good snapshot).
    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let resp = try await client.getSelf()
            snapshot = QuotaSnapshot(
                quotaRaw: resp.quota,
                usedQuotaRaw: resp.usedQuota,
                requestCount: resp.requestCount,
                fetchedAt: now()
            )
            lastError = nil
        } catch {
            lastError = error
        }
    }

    /// Fire-and-forget continuous polling. Cancels any prior loop.
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

    /// Swap the underlying client (e.g. after settings change) and restart the loop.
    func replaceClient(_ client: NewAPIClient, intervalSeconds: Int) {
        stop()
        self.client = client
        self.intervalSeconds = intervalSeconds
    }
}
