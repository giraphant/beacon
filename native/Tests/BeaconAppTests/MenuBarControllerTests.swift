import AppKit
import XCTest

@testable import Beacon

@MainActor
final class MenuBarControllerTests: XCTestCase {
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
}
