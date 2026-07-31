import AppKit
import BeaconCore
import XCTest

@testable import Beacon

@MainActor
final class MenuBarControllerTests: XCTestCase {
    private func alert(
        _ symbol: String,
        direction: RecentAlert.Direction,
        title: String,
        triggeredAt: Millis
    ) -> RecentAlert {
        RecentAlert(
            symbol: symbol,
            direction: direction,
            title: title,
            message: "$100.00 → $101.00",
            triggeredAt: triggeredAt
        )
    }

    func testQuoteLineSplitsIntoSymbolAndPriceColumns() {
        XCTAssertEqual(
            splitQuoteMenuLine("QQQ: $676.85"),
            QuoteMenuColumns(symbol: "QQQ", price: "$676.85")
        )
        XCTAssertNil(splitQuoteMenuLine("Loading…"))
    }

    func testQuoteRowUsesPrimaryTextAndOpposingAlignment() throws {
        let view = QuoteMenuRowView(
            symbol: "QQQ",
            price: "$676.85",
            alertDirection: .down
        )
        view.layoutSubtreeIfNeeded()

        XCTAssertFalse(view.alertImageView.isHidden)
        XCTAssertNotNil(view.alertImageView.image)
        XCTAssertEqual(view.symbolLabel.textColor, .labelColor)
        XCTAssertEqual(view.priceLabel.textColor, .labelColor)
        XCTAssertEqual(view.symbolLabel.alignment, .left)
        XCTAssertEqual(view.priceLabel.alignment, .right)
        XCTAssertLessThan(view.symbolLabel.frame.minX, view.priceLabel.frame.minX)
        XCTAssertGreaterThan(view.alertImageView.frame.minX, view.symbolLabel.frame.maxX)
        XCTAssertGreaterThanOrEqual(
            view.priceLabel.frame.width,
            view.priceLabel.fittingSize.width
        )
        XCTAssertEqual(view.intrinsicContentSize, QuoteMenuRowView.rowSize)

        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.white.cgColor
        let representation = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: representation)
        let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: "/tmp/beacon-quote-menu-row.png"))
    }

    func testQuoteRowDoesNotReserveSpaceForAMissingAlert() throws {
        let view = QuoteMenuRowView(symbol: "ETH", price: "$1,908")
        view.layoutSubtreeIfNeeded()

        XCTAssertTrue(view.alertImageView.isHidden)
        XCTAssertNil(view.alertImageView.image)
        XCTAssertEqual(view.alertImageView.frame.width, 0)
        let leadingConstraint = try XCTUnwrap(view.constraints.first {
            $0.firstItem === view.symbolLabel && $0.firstAttribute == .leading
        })
        XCTAssertEqual(leadingConstraint.constant, 16)
    }

    func testInfoRowIsCompactAndPreservesItsFullTextAsATooltip() {
        let text = "Refresh issues: A deliberately long diagnostic that must not widen the menu"
        let view = InfoMenuRowView(text: text)

        XCTAssertEqual(view.intrinsicContentSize, NSSize(width: 200, height: 22))
        XCTAssertEqual(view.textLabel.lineBreakMode, .byTruncatingTail)
        XCTAssertEqual(view.toolTip, text)
    }

    func testLatestAlertControlsProminentDirection() {
        let alerts = [
            alert("BTC", direction: .up, title: "BTC rose 1.00%", triggeredAt: 20_000),
            alert("QQQ", direction: .down, title: "QQQ fell 1.00%", triggeredAt: 10_000),
        ]

        XCTAssertEqual(prominentAlertDirection(in: alerts), .up)
        XCTAssertEqual(latestAlert(for: "QQQ", in: alerts)?.direction, .down)
    }

    func testRecentAlertRowExplainsWhatTriggered() {
        let value = alert(
            "QQQ",
            direction: .up,
            title: "QQQ crossed above $670.00",
            triggeredAt: 10_000
        )
        let view = RecentAlertMenuRowView(alert: value, now: 22_000)

        XCTAssertEqual(view.titleLabel.stringValue, "QQQ")
        XCTAssertTrue(view.percentageLabel.isHidden)
        XCTAssertEqual(view.messageLabel.stringValue, "$100.00 → $101.00")
        XCTAssertEqual(view.ageLabel.stringValue, "12s ago")
        XCTAssertEqual(view.intrinsicContentSize.width, QuoteMenuRowView.rowSize.width)
        XCTAssertEqual(view.intrinsicContentSize.height, 42)
        XCTAssertEqual(view.toolTip, "QQQ crossed above $670.00\n$100.00 → $101.00")
    }

    func testRecentAlertRowRemovesRedundantMovementAndStepDetails() {
        let value = RecentAlert(
            symbol: "NVDA",
            direction: .up,
            title: "NVDA rose 1.01%",
            message: "$193.68 → $195.63, crossed 1 × 1.00% steps",
            triggeredAt: 10_000
        )
        let view = RecentAlertMenuRowView(alert: value, now: 22_000)

        XCTAssertEqual(view.titleLabel.stringValue, "NVDA")
        XCTAssertEqual(view.percentageLabel.stringValue, "(+1.01%)")
        XCTAssertFalse(view.percentageLabel.isHidden)
        XCTAssertEqual(view.detailStackView.spacing, 5)
        XCTAssertLessThan(
            view.percentageLabel.font!.pointSize,
            view.messageLabel.font!.pointSize
        )
        XCTAssertEqual(view.messageLabel.stringValue, "$193.68 → $195.63")
        XCTAssertEqual(
            view.toolTip,
            "NVDA rose 1.01%\n$193.68 → $195.63, crossed 1 × 1.00% steps"
        )
    }

    func testRecentAlertRowShowsSignedPercentageAfterThePriceChange() {
        let value = RecentAlert(
            symbol: "HOOD",
            direction: .down,
            title: "HOOD fell 2.80%",
            message: "$90.780 → $88.240, crossed 1 × 2.00% steps",
            triggeredAt: 10_000
        )

        let view = RecentAlertMenuRowView(alert: value, now: 22_000)

        XCTAssertEqual(view.titleLabel.stringValue, "HOOD")
        XCTAssertEqual(view.messageLabel.stringValue, "$90.780 → $88.240")
        XCTAssertEqual(view.percentageLabel.stringValue, "(−2.80%)")
        XCTAssertNotNil(view.directionImageView.image)
    }
}
