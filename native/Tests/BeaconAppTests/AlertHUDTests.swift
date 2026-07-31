import AppKit
import XCTest

@testable import Beacon
@testable import BeaconCore

@MainActor
final class AlertHUDTests: XCTestCase {
    func testPresentationUsesCurrentPriceAndRemovesTheRepeatedSymbol() {
        let notification = AlertNotification(
            symbol: "QQQ",
            title: "QQQ crossed above $670",
            message: "$669.90 → $670.21",
            movementPercent: 1,
            thresholdPercent: 5,
            crossedSteps: 1,
            currentPrice: 670.21,
            baselinePrice: 669.90
        )

        XCTAssertEqual(
            AlertHUDPresentation(notification: notification),
            AlertHUDPresentation(
                symbol: "QQQ",
                price: "$670.21",
                title: "Crossed above $670",
                direction: .up
            )
        )
    }

    func testHUDContentExplainsTheAlertWithoutTakingFocus() throws {
        let presentation = AlertHUDPresentation(
            symbol: "QQQ",
            price: "$670.21",
            title: "Crossed above $670",
            direction: .up
        )
        let view = AlertHUDContentView(presentation: presentation)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: view.intrinsicContentSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertEqual(view.symbolLabel.stringValue, "QQQ")
        XCTAssertEqual(view.priceLabel.stringValue, "$670.21")
        XCTAssertEqual(view.titleLabel.stringValue, "Crossed above $670")
        XCTAssertEqual(
            view.intrinsicContentSize,
            AlertHUDMetrics.contentSize(for: presentation)
        )
        XCTAssertEqual(view.visibleCardFrame.size.height, AlertHUDMetrics.cardHeight)
        XCTAssertEqual(view.visibleCardFrame.size.width, AlertHUDMetrics.minimumCardWidth)
        XCTAssertNotNil(view.directionImageView.image)
        XCTAssertEqual(
            view.directionBadgeView.layer?.cornerRadius,
            AlertHUDMetrics.badgeSize / 2
        )
        let cardWidth = view.visibleCardFrame.width
        XCTAssertEqual(
            view.contentGroupView.frame.midX,
            cardWidth / 2,
            accuracy: 0.5
        )
        XCTAssertEqual(
            view.contentGroupView.frame.midY,
            AlertHUDMetrics.cardHeight / 2,
            accuracy: 0.5
        )
        XCTAssertEqual(
            view.directionBadgeView.frame.midY,
            view.textBlockFrame.midY,
            accuracy: 0.5
        )
        XCTAssertEqual(
            view.contentGroupView.frame.minX,
            cardWidth - view.contentGroupView.frame.maxX,
            accuracy: 0.5
        )

        let representation = try XCTUnwrap(
            view.bitmapImageRepForCachingDisplay(in: view.bounds)
        )
        view.cacheDisplay(in: view.bounds, to: representation)
        let hudData = try XCTUnwrap(
            representation.representation(using: .png, properties: [:])
        )
        let hudImage = try XCTUnwrap(NSImage(data: hudData))

        let previewSize = NSSize(width: 720, height: 280)
        let preview = NSImage(size: previewSize)
        preview.lockFocus()
        NSGradient(colors: [
            NSColor(calibratedRed: 0.90, green: 0.92, blue: 0.95, alpha: 1),
            NSColor(calibratedRed: 0.99, green: 0.98, blue: 0.95, alpha: 1),
        ])?.draw(in: NSRect(origin: .zero, size: previewSize), angle: -12)
        hudImage.draw(
            at: NSPoint(
                x: (previewSize.width - view.bounds.width) / 2,
                y: (previewSize.height - view.bounds.height) / 2
            ),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        preview.unlockFocus()

        let previewRepresentation = try XCTUnwrap(
            NSBitmapImageRep(data: try XCTUnwrap(preview.tiffRepresentation))
        )
        let previewData = try XCTUnwrap(
            previewRepresentation.representation(using: .png, properties: [:])
        )
        try previewData.write(to: URL(fileURLWithPath: "/tmp/beacon-alert-hud.png"))
    }

    func testHUDPlacementUsesTheLowerFifthOfEachDisplay() {
        let presentation = AlertHUDPresentation.preview
        let contentSize = AlertHUDMetrics.contentSize(for: presentation)
        let main = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let secondary = NSRect(x: -1920, y: -120, width: 1920, height: 1080)

        for visibleFrame in [main, secondary] {
            let origin = AlertHUDMetrics.panelOrigin(
                contentSize: contentSize,
                in: visibleFrame
            )
            let cardFrame = NSRect(
                x: origin.x + AlertHUDMetrics.shadowInsetX,
                y: origin.y + AlertHUDMetrics.shadowInsetY,
                width: contentSize.width - AlertHUDMetrics.shadowInsetX * 2,
                height: AlertHUDMetrics.cardHeight
            )

            XCTAssertEqual(cardFrame.midX, visibleFrame.midX, accuracy: 0.001)
            XCTAssertLessThan(cardFrame.midY, visibleFrame.midY)
            XCTAssertGreaterThan(cardFrame.minY, visibleFrame.minY + 100)
            XCTAssertLessThan(cardFrame.midY, visibleFrame.minY + visibleFrame.height * 0.30)
        }
    }

    func testScreenResolverMapsQuartzCoordinatesAndChoosesLargestIntersection() throws {
        let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let right = CGRect(x: 1440, y: -100, width: 1920, height: 1080)
        let quartzBounds = CGRect(x: 1600, y: 130, width: 900, height: 700)
        let appKitFrame = try XCTUnwrap(
            AlertHUDScreenResolver.appKitWindowFrame(
                quartzBounds: quartzBounds,
                primaryScreenMaxY: main.maxY
            )
        )

        XCTAssertEqual(appKitFrame, CGRect(x: 1600, y: 70, width: 900, height: 700))
        XCTAssertEqual(
            AlertHUDScreenResolver.bestScreenFrame(
                forWindowFrame: appKitFrame,
                screenFrames: [main, right]
            ),
            right
        )
    }

    func testDefaultDeliveryChannelsPreferThePermissionFreeHUD() {
        let suite = "AlertHUDTests-\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        defer { store.removePersistentDomain(forName: suite) }
        store.register(defaults: Preferences.defaults)

        let preferences = Preferences.load(store)

        XCTAssertTrue(preferences.hudAlertsEnabled)
        XCTAssertEqual(preferences.hudDurationSeconds, HUDDuration.defaultSeconds)
        XCTAssertFalse(preferences.systemNotificationsEnabled)

        store.set(false, forKey: PreferenceKey.hudAlertsEnabled)
        store.set(7.5, forKey: PreferenceKey.hudDurationSeconds)
        store.set(true, forKey: PreferenceKey.systemNotificationsEnabled)
        let reversed = Preferences.load(store)
        XCTAssertFalse(reversed.hudAlertsEnabled)
        XCTAssertEqual(reversed.hudDurationSeconds, 7.5)
        XCTAssertTrue(reversed.systemNotificationsEnabled)
    }

    func testHUDDurationStaysWithinTheSupportedRange() {
        XCTAssertEqual(HUDDuration.normalized(.nan), HUDDuration.defaultSeconds)
        XCTAssertEqual(HUDDuration.normalized(0), HUDDuration.range.lowerBound)
        XCTAssertEqual(HUDDuration.normalized(30), HUDDuration.range.upperBound)
        XCTAssertEqual(HUDDuration.normalized(4.5), 4.5)
    }
}
