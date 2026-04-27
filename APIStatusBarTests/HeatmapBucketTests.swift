import XCTest
@testable import APIStatusBar

final class HeatmapBucketTests: XCTestCase {
    func test_zero_isEmptyBucket() {
        XCTAssertEqual(HeatmapBucket.bucket(forUSD: 0), 0)
    }

    func test_belowFirstThreshold_isEmpty() {
        XCTAssertEqual(HeatmapBucket.bucket(forUSD: 0.005), 0)
    }

    func test_atFirstThreshold_isBucket1() {
        XCTAssertEqual(HeatmapBucket.bucket(forUSD: 0.01), 1)
    }

    func test_belowOneDollar_isBucket1() {
        XCTAssertEqual(HeatmapBucket.bucket(forUSD: 0.99), 1)
    }

    func test_atOneDollar_isBucket2() {
        XCTAssertEqual(HeatmapBucket.bucket(forUSD: 1.0), 2)
    }

    func test_belowFive_isBucket2() {
        XCTAssertEqual(HeatmapBucket.bucket(forUSD: 4.99), 2)
    }

    func test_atFive_isBucket3() {
        XCTAssertEqual(HeatmapBucket.bucket(forUSD: 5.0), 3)
    }

    func test_belowTwenty_isBucket3() {
        XCTAssertEqual(HeatmapBucket.bucket(forUSD: 19.99), 3)
    }

    func test_atTwenty_isBucket4() {
        XCTAssertEqual(HeatmapBucket.bucket(forUSD: 20.0), 4)
    }

    func test_largeValue_isBucket4() {
        XCTAssertEqual(HeatmapBucket.bucket(forUSD: 9999), 4)
    }

    func test_negativeIsTreatedAsEmpty() {
        XCTAssertEqual(HeatmapBucket.bucket(forUSD: -1), 0)
    }
}
