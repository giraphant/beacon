import AppKit
import BeaconCore

/// Owns the status item and turns a `MenuBarModel` into an `NSMenu`. Everything
/// it can't do itself — refreshing, dismissing, opening Settings — is injected.
///
/// Deliberately AppKit rather than SwiftUI's `MenuBarExtra`: when macOS declines
/// to place a `MenuBarExtra` — a menu bar with no room left, an item dragged off
/// — its backing `NSSceneStatusItem` responds by calling
/// `NSApplication.terminate:`, so the whole app exits a few seconds after every
/// launch with no crash and no log. An `NSStatusItem` merely goes undrawn, the
/// app keeps polling, and relaunching still reaches Settings.
@MainActor
final class MenuBarController: NSObject {
    struct Actions {
        var refresh: () -> Void
        var dismissAlerts: () -> Void
        var openSettings: () -> Void
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let actions: Actions
    private var model = MenuBarModel(title: "Beacon", isLoading: true)
    private var alerts: [String: RecentAlert] = [:]

    init(actions: Actions) {
        self.actions = actions
        super.init()
        // A stable autosave identity makes macOS remember this item's menu-bar
        // slot instead of occasionally parking it off-screen on multi-display
        // setups.
        statusItem.autosaveName = "BeaconMenuBarItem"
        // Beacon without its menu bar item is a background process the user
        // cannot see or reach, so a persisted "dragged off" state is overridden
        // rather than honoured.
        statusItem.isVisible = true
        menu.delegate = self
        statusItem.menu = menu
    }

    /// Only the button is touched here. Replacing the menu's contents on a
    /// refresh would yank the dropdown out from under a user who has it open;
    /// `menuNeedsUpdate` rebuilds it at the moment it is shown instead.
    func render(_ model: MenuBarModel, alerts: [String: RecentAlert]) {
        self.model = model
        self.alerts = alerts
        statusItem.button?.title = title(model, alerts)
    }

    private func title(_ model: MenuBarModel, _ alerts: [String: RecentAlert]) -> String {
        guard !alerts.isEmpty else { return model.title }
        let indicator = alerts.values.contains { $0.direction == .down } ? "🔴" : "🟢"
        return "\(indicator) \(model.title)"
    }

    // MARK: - Menu

    private func populate(_ menu: NSMenu) {
        menu.removeAllItems()

        for item in model.items { menu.addItem(label(item)) }

        for section in model.sections {
            if menu.numberOfItems > 0 { menu.addItem(.separator()) }
            if let title = section.title { menu.addItem(.sectionHeader(title: title)) }
            for item in section.items { menu.addItem(label(item)) }
        }

        if menu.numberOfItems > 0 { menu.addItem(.separator()) }

        menu.addItem(action("Refresh Now", key: "r", #selector(refresh)))
        if !alerts.isEmpty {
            menu.addItem(action("Dismiss Alerts", key: "", #selector(dismissAlerts)))
        }
        menu.addItem(action("Settings…", key: ",", #selector(openSettings)))
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(title: "Quit Beacon", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        )
    }

    /// A quote line is text, not a command: no action means AppKit draws it
    /// disabled, which is the intent.
    private func label(_ text: String) -> NSMenuItem {
        NSMenuItem(title: text, action: nil, keyEquivalent: "")
    }

    private func action(_ title: String, key: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: - Actions

    @objc private func refresh() { actions.refresh() }
    @objc private func dismissAlerts() { actions.dismissAlerts() }
    @objc private func openSettings() { actions.openSettings() }
}

extension MenuBarController: NSMenuDelegate {
    /// Called just before the dropdown is shown, so it always reflects the most
    /// recent refresh without being rebuilt 2,880 times a day for nobody.
    func menuNeedsUpdate(_ menu: NSMenu) {
        populate(menu)
    }
}
