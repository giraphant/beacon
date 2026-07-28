import AppKit
import BeaconCore
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel.shared
    private var menuBar: MenuBarController?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()

        let menuBar = MenuBarController(actions: .init(
            refresh: { [model] in model.triggerRefresh() },
            dismissAlerts: { [model] in model.dismissAlerts() },
            openSettings: { SettingsWindowController.shared.showWindow(nil) }
        ))
        self.menuBar = menuBar

        // The published values are used rather than re-read from the model:
        // `@Published` fires in `willSet`, so the model's own properties are
        // still the previous ones while this runs.
        model.$menu
            .combineLatest(model.$recentAlerts)
            .sink { menu, alerts in
                MainActor.assumeIsolated { menuBar.render(menu, alerts: alerts) }
            }
            .store(in: &cancellables)

        model.start()
    }

    /// Cmd-W, Cmd-Q and the Edit clipboard commands only work when an
    /// `NSApp.mainMenu` exists — AppKit routes their key equivalents through it
    /// even for an accessory app with no visible menu bar of its own.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Quit Beacon", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"
        )
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    /// Launching an already-running accessory app is the only recovery path if
    /// the menu-bar icon is hidden or off-screen, so make it open Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        SettingsWindowController.shared.showWindow(nil)
        return true
    }
}

let app = NSApplication.shared
// Top-level code in `main.swift` runs on the main thread, but the compiler has
// no way to know that.
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
