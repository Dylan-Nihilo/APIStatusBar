import Foundation
import Combine

/// Per-day rollup of usage for the heatmap and account "today" stat.
struct DayBucket: Equatable {
    /// Local-timezone start-of-day.
    let date: Date
    let quotaRaw: Int
    let usd: Double
    let requestCount: Int
    /// Top 3 raw model names ordered by quota desc, ties broken alphabetically asc.
    let topModels: [String]
}

/// Fetches per-model usage from `/api/data/self`, rolls up to per-provider
/// totals, exposes the top providers for the popover strip and the menu bar
/// icon. Polls less often than `QuotaPoller` because daily aggregates change
/// slowly — once every 5 minutes is plenty.
@MainActor
final class ModelStatsPoller: ObservableObject {
    @Published private(set) var topProviders: [ProviderUsage] = []
    @Published private(set) var dailyBuckets: [Date: DayBucket] = [:]
    @Published private(set) var lastError: Error?

    private var client: NewAPIClient
    private let intervalSeconds: Int
    private let lookbackDays: Int
    private let quotaPerUnit: Int
    private var loop: Task<Void, Never>?

    init(client: NewAPIClient,
         intervalSeconds: Int = 300,
         lookbackDays: Int = 90,
         quotaPerUnit: Int = 500_000) {
        self.client = client
        self.intervalSeconds = intervalSeconds
        self.lookbackDays = lookbackDays
        self.quotaPerUnit = quotaPerUnit
    }

    /// Pull the latest rows and re-aggregate. Safe to call manually for
    /// instant refresh after a settings change.
    /// Splits the lookback into 30-day chunks (server enforces a 30-day max per call)
    /// and fires them in parallel.
    func refresh() async {
        let now = Date()
        let chunkDays = 30
        let chunkCount = Int(ceil(Double(lookbackDays) / Double(chunkDays)))

        do {
            var allRows: [QuotaDataRow] = []
            // Build windows: [(-90,-60), (-60,-30), (-30,0)] for lookbackDays=90
            try await withThrowingTaskGroup(of: [QuotaDataRow].self) { group in
                for i in 0..<chunkCount {
                    let offsetEnd   = -i * chunkDays
                    let offsetStart = -(i + 1) * chunkDays
                    let chunkEnd   = Calendar.current.date(byAdding: .day, value: offsetEnd,   to: now) ?? now
                    let chunkStart = Calendar.current.date(byAdding: .day, value: offsetStart, to: now) ?? now
                    group.addTask { [client] in
                        try await client.getDataSelf(start: chunkStart, end: chunkEnd)
                    }
                }
                for try await rows in group {
                    allRows += rows
                }
            }
            aggregate(rows: allRows)
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

    /// Roll per-(model, hour) rows into per-provider AND per-day rollups.
    /// Mutates `topProviders` and `dailyBuckets` in place. Returns the
    /// per-provider list for callers that already use it; the per-day
    /// rollup is read via the `dailyBuckets` published property.
    @discardableResult
    func aggregate(rows: [QuotaDataRow]) -> [ProviderUsage] {
        // --- per-provider rollup ---
        var byProvider: [String: (models: [String: Int], quota: Int, count: Int)] = [:]
        for row in rows {
            guard let provider = ProviderMapping.provider(for: row.modelName) else { continue }
            var bucket = byProvider[provider] ?? (models: [:], quota: 0, count: 0)
            bucket.models[row.modelName, default: 0] += row.quota
            bucket.quota += row.quota
            bucket.count += row.count
            byProvider[provider] = bucket
        }
        let providers = byProvider
            .map { ProviderUsage(providerAsset: $0.key,
                                  modelNames: sortedModels($0.value.models),
                                  quotaRaw: $0.value.quota,
                                  requestCount: $0.value.count) }
            .sorted { $0.quotaRaw > $1.quotaRaw }
        self.topProviders = providers

        // --- per-day rollup ---
        var byDay: [Date: (models: [String: Int], quota: Int, count: Int)] = [:]
        let cal = Calendar.current
        for row in rows {
            let rowDate = Date(timeIntervalSince1970: TimeInterval(row.createdAt))
            let day = cal.startOfDay(for: rowDate)
            var bucket = byDay[day] ?? (models: [:], quota: 0, count: 0)
            bucket.models[row.modelName, default: 0] += row.quota
            bucket.quota += row.quota
            bucket.count += row.count
            byDay[day] = bucket
        }
        var newDailyBuckets: [Date: DayBucket] = [:]
        for (day, agg) in byDay {
            let topModels = agg.models
                .sorted { lhs, rhs in
                    if lhs.value != rhs.value { return lhs.value > rhs.value }
                    return lhs.key < rhs.key
                }
                .prefix(3)
                .map(\.key)
            newDailyBuckets[day] = DayBucket(
                date: day,
                quotaRaw: agg.quota,
                usd: Double(agg.quota) / Double(quotaPerUnit),
                requestCount: agg.count,
                topModels: Array(topModels)
            )
        }
        self.dailyBuckets = newDailyBuckets

        return providers
    }

    private func sortedModels(_ models: [String: Int]) -> [String] {
        models
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            .map(\.key)
    }
}
