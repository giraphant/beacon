import AppKit
import SwiftUI

/// Launching an already-running accessory app is the only recovery path if the
/// menu-bar icon is hidden or off-screen, so make it open Settings.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        MainActor.assumeIsolated { SettingsWindowController.shared.showWindow(nil) }
        return true
    }
}

@main
struct BeaconApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Text(model.menuBarTitle)
                .task { model.start() }
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuContent: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ForEach(Array(model.menu.items.enumerated()), id: \.offset) { _, item in
            Text(item)
        }

        ForEach(Array(model.menu.sections.enumerated()), id: \.offset) { _, section in
            Divider()
            if let title = section.title {
                Text(title)
            }
            ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                Text(item)
            }
        }

        Divider()

        Button("Refresh Now") { model.triggerRefresh() }
            .keyboardShortcut("r", modifiers: .command)

        if !model.recentAlerts.isEmpty {
            Button("Dismiss Alerts") { model.dismissAlerts() }
        }

        Button("Settings…") { SettingsWindowController.shared.showWindow(nil) }
            .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit Beacon") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}
