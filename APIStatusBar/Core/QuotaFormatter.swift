import Foundation

struct QuotaFormatter {
    let quotaPerUnit: Int

    func usd(fromRaw raw: Int) -> Double {
        Double(raw) / Double(quotaPerUnit)
    }

    func displayString(usd: Double) -> String {
        if usd >= 1000 {
            return String(format: "$%.1fk", usd / 1000)
        } else if usd >= 100 {
            return String(format: "$%.0f", usd)
        } else {
            return String(format: "$%.2f", usd)
        }
    }
}
