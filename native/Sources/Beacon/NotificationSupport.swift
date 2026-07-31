import AppKit
import Foundation
import UserNotifications

struct NotificationSettingsSnapshot: Equatable {
    var isLoaded: Bool
    var authorizationStatus: UNAuthorizationStatus
    var alertSetting: UNNotificationSetting
    var alertStyle: UNAlertStyle

    static let loading = NotificationSettingsSnapshot(
        isLoaded: false,
        authorizationStatus: .notDetermined,
        alertSetting: .notSupported,
        alertStyle: .none
    )

    static let unavailable = NotificationSettingsSnapshot(
        isLoaded: true,
        authorizationStatus: .denied,
        alertSetting: .notSupported,
        alertStyle: .none
    )

    init(
        isLoaded: Bool = true,
        authorizationStatus: UNAuthorizationStatus,
        alertSetting: UNNotificationSetting,
        alertStyle: UNAlertStyle
    ) {
        self.isLoaded = isLoaded
        self.authorizationStatus = authorizationStatus
        self.alertSetting = alertSetting
        self.alertStyle = alertStyle
    }

    init(_ settings: UNNotificationSettings) {
        self.init(
            authorizationStatus: settings.authorizationStatus,
            alertSetting: settings.alertSetting,
            alertStyle: settings.alertStyle
        )
    }

    var summary: String {
        guard isLoaded else { return "Checking…" }
        switch authorizationStatus {
        case .notDetermined:
            return "Not requested"
        case .denied:
            return "Off"
        case .authorized, .provisional:
            guard alertSetting == .enabled, alertStyle != .none else {
                return "Banners off"
            }
            switch alertStyle {
            case .banner:
                return "Banners"
            case .alert:
                return "Alerts"
            case .none:
                return "Banners off"
            @unknown default:
                return "On"
            }
        @unknown default:
            return "Unknown"
        }
    }

    var explanation: String? {
        guard isLoaded else { return nil }
        switch authorizationStatus {
        case .notDetermined:
            return "Allow notifications so price alerts can appear outside the menu bar."
        case .denied:
            return "Beacon is not allowed to post notifications. Alerts still remain visible in its menu."
        case .authorized, .provisional:
            guard alertSetting == .enabled, alertStyle != .none else {
                return "Beacon can add alerts to Notification Center, but macOS is not showing banners."
            }
            return nil
        @unknown default:
            return "macOS returned an unknown notification permission state."
        }
    }

    var needsSystemSettings: Bool {
        guard isLoaded else { return false }
        switch authorizationStatus {
        case .denied:
            return true
        case .authorized, .provisional:
            return alertSetting != .enabled || alertStyle == .none
        case .notDetermined:
            return false
        @unknown default:
            return true
        }
    }

    var canSendTest: Bool {
        guard isLoaded else { return false }
        switch authorizationStatus {
        case .authorized, .provisional:
            return alertSetting == .enabled && alertStyle != .none
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
    }
}

/// Foreground apps do not receive visible notifications unless their delegate
/// explicitly opts into presentation. A menu-bar app can remain active after
/// Settings or its menu was used, so omitting this made banners intermittent.
final class NotificationPresentationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }
}

func openBeaconNotificationSettings() {
    let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.inol.beacon"
    let destinations = [
        "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleIdentifier)",
        "x-apple.systempreferences:com.apple.preference.notifications",
    ]
    for destination in destinations {
        guard let url = URL(string: destination) else { continue }
        if NSWorkspace.shared.open(url) { return }
    }
}
