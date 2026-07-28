@testable import BeaconCore
import XCTest

final class FormatTests: XCTestCase {
    func testFormatsCompactSourceNativePrices() {
        XCTAssertEqual(formatPrice(103_245.18), "$103,245")
        XCTAssertEqual(formatPrice(421.456), "$421.46")
        XCTAssertEqual(formatPrice(0.123456), "$0.1235")
    }

    func testCanHideCurrencySymbol() {
        XCTAssertEqual(formatPrice(103_245.18, hideCurrencySymbol: true), "103,245")
        XCTAssertEqual(formatPrice(421.456, hideCurrencySymbol: true), "421.46")
        XCTAssertEqual(formatPrice(0.123456, hideCurrencySymbol: true), "0.1235")
    }

    func testFormatsSignedPercentageValues() {
        XCTAssertEqual(formatPercent(3.245), "+3.25%")
        XCTAssertEqual(formatPercent(-1), "-1.00%")
    }

    /// Ties round away from zero, matching `Intl.NumberFormat`; Foundation's
    /// default banker's rounding would give "0.12%" here.
    func testRoundsTiesAwayFromZero() {
        XCTAssertEqual(formatPercent(0.125), "+0.13%")
    }

    /// JS `toFixed` never groups, so a large percentage must not gain a comma.
    func testPercentDoesNotGroupThousands() {
        XCTAssertEqual(formatPercent(1234.5), "+1234.50%")
    }

    func testFormatsSecondsAndMinutes() {
        XCTAssertEqual(formatAge(updatedAt: 1_000, now: 12_000), "11s ago")
        XCTAssertEqual(formatAge(updatedAt: 1_000, now: 181_000), "3m ago")
    }

    func testClampsFutureTimestampsToZero() {
        XCTAssertEqual(formatAge(updatedAt: 12_000, now: 1_000), "0s ago")
    }
}
