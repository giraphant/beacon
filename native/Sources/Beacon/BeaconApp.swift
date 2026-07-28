import AppKit
import SwiftUI

/// Launching an already-running accessory app is the only recovery path if the
/// menu-bar icon is hidden or off-screen, so make it open Settings.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// A ⌘-dragged-off status item persists as these keys and silently
    /// resurrects hidden on every launch — the app then looks dead, with no
    /// UI left to bring it back. Beacon without its menu bar item is useless,
    /// so launching IS the "show it again" gesture. Cleared before the scene
    /// builds. (Not MenuBarExtra(isInserted:): on macOS 14 that binding gets
    /// spuriously written false when another window opens, hiding the item.)
    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.removeObject(forKey: "NSStatusItem VisibleCC Item-0")
        UserDefaults.standard.removeObject(forKey: "NSStatusItem Visible Item-0")
    }

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
