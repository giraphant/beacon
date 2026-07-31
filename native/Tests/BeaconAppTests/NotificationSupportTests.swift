import UserNotifications
import XCTest

@testable import Beacon

final class NotificationSupportTests: XCTestCase {
    func testReportsAuthorizedBannerPresentation() {
        let settings = NotificationSettingsSnapshot(
            authorizationStatus: .authorized,
            alertSetting: .enabled,
            alertStyle: .banner
        )

        XCTAssertEqual(settings.summary, "Banners")
        XCTAssertTrue(settings.canSendTest)
        XCTAssertFalse(settings.needsSystemSettings)
        XCTAssertNil(settings.explanation)
    }

    func testExplainsAuthorizedNotificationsWithBannersDisabled() {
        let settings = NotificationSettingsSnapshot(
            authorizationStatus: .authorized,
            alertSetting: .enabled,
            alertStyle: .none
        )

        XCTAssertEqual(settings.summary, "Banners off")
        XCTAssertFalse(settings.canSendTest)
        XCTAssertTrue(settings.needsSystemSettings)
        XCTAssertNotNil(settings.explanation)
    }

    func testExplainsDeniedNotifications() {
        let settings = NotificationSettingsSnapshot(
            authorizationStatus: .denied,
            alertSetting: .disabled,
            alertStyle: .none
        )

        XCTAssertEqual(settings.summary, "Off")
        XCTAssertFalse(settings.canSendTest)
        XCTAssertTrue(settings.needsSystemSettings)
    }
}
