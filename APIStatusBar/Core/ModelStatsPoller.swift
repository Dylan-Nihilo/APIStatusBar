import Foundation
import Combine

/// Fetches per-model usage from `/api/data/self`, rolls up to per-provider
/// totals, exposes the top providers for the popover strip and the menu bar
/// icon. Polls less often than `QuotaPoller` because daily aggregates change
/// slowly — once every 5 minutes is plenty.
@MainActor
final class ModelStatsPoller: ObservableObject {
    @Published private(set) var topProviders: [ProviderUsage] = []
    @Published private(set) var lastError: Error?

    private var client: NewAPIClient
    private let intervalSeconds: Int
    private let lookbackDays: Int
    private var loop: Task<Void, Never>?

    init(client: NewAPIClient, intervalSeconds: Int = 300, lookbackDays: Int = 30) {
        self.client = client
        self.intervalSeconds = intervalSeconds
        self.lookbackDays = lookbackDays
    }

    /// Pull the latest rows and re-aggregate. Safe to call manually for
    /// instant refresh after a settings change.
    func refresh() async {
        let now = Date()
        let start = Calendar.current.date(byAdding: .day,
                                          value: -lookbackDays,
                                          to: now) ?? now
        do {
            let rows = try await client.getDataSelf(start: start, end: now)
            topProviders = aggregate(rows: rows)
            lastError = nil
        } catch {
            lastError = error
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

    func replaceClient(_ client: NewAPIClient) {
        stop()
        self.client = client
    }

    /// Roll per-(model, hour) rows into per-provider totals, sorted by quota desc.
    /// Models with no provider rule are bucketed under "other" so they still
    /// contribute to totals but stay out of the strip.
    func aggregate(rows: [QuotaDataRow]) -> [ProviderUsage] {
        var byProvider: [String: (models: Set<String>, quota: Int, count: Int)] = [:]
        for row in rows {
            guard let provider = ProviderMapping.provider(for: row.modelName) else { continue }
            var bucket = byProvider[provider] ?? (models: [], quota: 0, count: 0)
            bucket.models.insert(row.modelName)
            bucket.quota += row.quota
            bucket.count += row.count
            byProvider[provider] = bucket
        }
        return byProvider
            .map { ProviderUsage(providerAsset: $0.key,
                                 modelNames: Array($0.value.models).sorted(),
                                 quotaRaw: $0.value.quota,
                                 requestCount: $0.value.count) }
            .sorted { $0.quotaRaw > $1.quotaRaw }
    }
}
