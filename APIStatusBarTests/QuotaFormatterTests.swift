import XCTest
@testable import APIStatusBar

final class QuotaFormatterTests: XCTestCase {
    let f = QuotaFormatter(quotaPerUnit: 500_000)

    func test_usdConversion_basic() {
        XCTAssertEqual(f.usd(fromRaw: 500_000), 1.0, accuracy: 1e-9)
        XCTAssertEqual(f.usd(fromRaw: 250_000), 0.5, accuracy: 1e-9)
        XCTAssertEqual(f.usd(fromRaw: 0), 0, accuracy: 1e-9)
    }

    func test_displayString_lessThanHundred_twoDecimals() {
        XCTAssertEqual(f.displayString(usd: 0), "$0.00")
        XCTAssertEqual(f.displayString(usd: 12.345), "$12.35")
        XCTAssertEqual(f.displayString(usd: 99.99), "$99.99")
    }

    func test_displayString_hundredsAndUp_noDecimals() {
        XCTAssertEqual(f.displayString(usd: 100), "$100")
        XCTAssertEqual(f.displayString(usd: 567.4), "$567")
    }

    func test_displayString_thousandsAndUp_kSuffix() {
        XCTAssertEqual(f.displayString(usd: 1000), "$1.0k")
        XCTAssertEqual(f.displayString(usd: 1234), "$1.2k")
        XCTAssertEqual(f.displayString(usd: 9999), "$10.0k")
    }

    func test_customQuotaPerUnit() {
        let f2 = QuotaFormatter(quotaPerUnit: 1_000_000)
        XCTAssertEqual(f2.usd(fromRaw: 1_000_000), 1.0, accuracy: 1e-9)
    }
}
