import Foundation

struct QuotaFormatter {
    static let quotaPerRMB = 500_000

    let quotaPerUnit: Int

    init(quotaPerUnit: Int = Self.quotaPerRMB) {
        self.quotaPerUnit = quotaPerUnit
    }

    func usd(fromRaw raw: Int) -> Double {
        Double(raw) / Double(quotaPerUnit)
    }

    func rmb(fromRaw raw: Int) -> Double {
        Double(raw) / Double(quotaPerUnit)
    }

    func displayString(usd: Double, includeSymbol: Bool = true) -> String {
        let prefix = includeSymbol ? "$" : ""
        if usd >= 1000 {
            return String(format: "%@%.1fk", prefix, usd / 1000)
        } else if usd >= 100 {
            return String(format: "%@%.0f", prefix, usd)
        } else {
            return String(format: "%@%.2f", prefix, usd)
        }
    }

    func displayRMB(raw: Int, includeSymbol: Bool = true) -> String {
        displayRMB(rmb: rmb(fromRaw: raw), includeSymbol: includeSymbol)
    }

    func displayRMB(rmb: Double, includeSymbol: Bool = true) -> String {
        let prefix = includeSymbol ? "¥" : ""
        if rmb >= 10_000 {
            return String(format: "%@%.1f万", prefix, rmb / 10_000)
        } else if rmb >= 100 {
            return String(format: "%@%.0f", prefix, rmb)
        } else {
            return String(format: "%@%.2f", prefix, rmb)
        }
    }
}
