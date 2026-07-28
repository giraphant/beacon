import AppKit
import BeaconCore
import ServiceManagement
import SwiftUI

/// SwiftUI's `Settings` scene and `SettingsLink` do not reliably open from a
/// `MenuBarExtra` in an accessory app, so the window is AppKit — same shape as
/// veduta's.
@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    init() {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
        window.title = "Beacon"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        // A hosting controller sizes the window to the SwiftUI content, and a
        // Form has no width of its own — without this it opens at `minSize`.
        window.setContentSize(NSSize(width: 520, height: 620))
        window.minSize = NSSize(width: 440, height: 400)
        window.setFrameAutosaveName("BeaconSettingsWindow")
        super.init(window: window)
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// An accessory app has no Dock icon, so the window has to raise itself past
    /// whatever is frontmost — and the activation only takes if it happens after
    /// the window is already on screen, not before.
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SettingsView: View {
    @AppStorage(PreferenceKey.coins) private var coins = "BTC ETH NVDA QQQ"
    @AppStorage(PreferenceKey.alertRules) private var alertRules = ""
    @AppStorage(PreferenceKey.integerAlertRules) private var integerAlertRules = ""
    @AppStorage(PreferenceKey.integerAlertCooldownMinutes) private var cooldownMinutes = "10"
    @AppStorage(PreferenceKey.hideMenuBarSymbols) private var hideMenuBarSymbols = false
    @AppStorage(PreferenceKey.hideCurrencySymbol) private var hideCurrencySymbol = false
    @AppStorage(PreferenceKey.source) private var source = QuoteSourceKind.bybit.rawValue
    @AppStorage(PreferenceKey.relayUrl) private var relayURL = ""
    @AppStorage(PreferenceKey.refreshSeconds) private var refreshSeconds = 30
    @AppStorage(PreferenceKey.alertSoundEnabled) private var alertSoundEnabled = false

    @State private var relayToken = ""
    @State private var tokenError: String?
    @State private var credentialsDebounce: Task<Void, Never>?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Symbols") {
                TextField("Watchlist", text: $coins)
                Text("Space separated. A `|` splits menu-bar symbols from dropdown-only ones: `BTC ETH | NVDA QQQ`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Hide symbols in menu bar", isOn: $hideMenuBarSymbols)
                Toggle("Hide currency symbol", isOn: $hideCurrencySymbol)
            }

            Section("Alerts") {
                TextField("Percent rules", text: $alertRules)
                Text("`BTC:1 ETH:2` alerts when the price moves that percent from the last alert.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Boundary rules", text: $integerAlertRules)
                Text("`BTC:1000 JUP:0.05` alerts when the price crosses a multiple of that step.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Boundary cooldown (minutes)", text: $cooldownMinutes)
                Toggle("Play sound", isOn: $alertSoundEnabled)
            }

            Section("Source") {
                Picker("Quotes from", selection: $source) {
                    ForEach(QuoteSourceKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind.rawValue)
                    }
                }
                if source == QuoteSourceKind.relay.rawValue {
                    TextField("Relay URL", text: $relayURL)
                    // The keychain write is local and cheap, so it happens per
                    // keystroke — debouncing it would simply drop the last edit
                    // if the window closed or the app quit inside the wait. Only
                    // the refresh is worth waiting for a pause on, and the model
                    // has no other way to hear about a keychain change.
                    SecureField("Relay token", text: $relayToken)
                        .onChange(of: relayToken) { _, token in
                            guard token != Keychain.read(PreferenceKey.relayToken) ?? "" else { return }
                            guard Keychain.write(token, account: PreferenceKey.relayToken) else {
                                // Refreshing now would just re-send the old
                                // token and blame the relay for rejecting it.
                                tokenError = "Could not save the token to your keychain."
                                return
                            }
                            tokenError = nil
                            credentialsDebounce?.cancel()
                            credentialsDebounce = Task {
                                try? await Task.sleep(for: .milliseconds(800))
                                guard !Task.isCancelled else { return }
                                AppModel.shared.credentialsChanged()
                            }
                        }
                    if let tokenError {
                        Text(tokenError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                Stepper("Refresh every \(refreshSeconds)s", value: $refreshSeconds, in: 5...600, step: 5)
            }

            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        setLaunchAtLogin(enabled)
                    }
            }
        }
        .formStyle(.grouped)
        .onAppear { relayToken = Keychain.read(PreferenceKey.relayToken) ?? "" }
    }

    /// Registration needs a signed bundle; if it fails, snap the toggle back
    /// rather than showing a state the system does not actually have.
    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
