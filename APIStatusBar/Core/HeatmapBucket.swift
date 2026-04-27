import Foundation

/// Maps a USD value to a heatmap bucket index 0…4 using half-open intervals.
/// Bucket 0 = empty / no usage. Buckets 1–4 = increasing intensity.
/// Edges are tunable for personal scale (see spec §6).
enum HeatmapBucket {
    /// `bucketEdges[i]` is the lower bound of bucket `i+1`. So a value `v`
    /// belongs to bucket `i+1` when `bucketEdges[i] ≤ v < bucketEdges[i+1]`,
    /// or to bucket `bucketEdges.count` (the topmost) when `v ≥ bucketEdges.last`.
    static let bucketEdges: [Double] = [0.01, 1.0, 5.0, 20.0]

    /// Returns 0…bucketEdges.count (= 4 by default).
    static func bucket(forUSD usd: Double) -> Int {
        guard usd > 0 else { return 0 }
        var index = 0
        for edge in bucketEdges {
            if usd < edge { return index }
            index += 1
        }
        return index
    }
}
