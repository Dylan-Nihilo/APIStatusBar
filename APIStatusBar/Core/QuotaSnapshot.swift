import Foundation

/// Immutable result of a single `/api/user/self` poll.
struct QuotaSnapshot: Equatable, Sendable {
    let quotaRaw: Int
    let usedQuotaRaw: Int
    let requestCount: Int
    let fetchedAt: Date
}
