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
        // An (empty) toolbar is what makes SwiftUI's `navigationTitle` render
        // as the bold pane title in the detail column; without one AppKit just
        // centers the window title instead.
        let toolbar = NSToolbar(identifier: "BeaconSettingsToolbar")
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        // A hosting controller sizes the window to the SwiftUI content, and a
        // NavigationSplitView has no size of its own — without this it opens at
        // `minSize`.
        window.setContentSize(NSSize(width: 760, height: 540))
        window.minSize = NSSize(width: 640, height: 420)
        // Not the pre-sidebar autosave name: a frame saved by the old
        // single-form window is too narrow for the split view.
        window.setFrameAutosaveName("BeaconSettingsWindowSplit")
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

private enum SettingsPane: String, CaseIterable, Identifiable {
    case symbols
    case alerts
    case source
    case general

    var id: Self { self }

    var title: String {
        switch self {
        case .symbols: "Symbols"
        case .alerts: "Alerts"
        case .source: "Source"
        case .general: "General"
        }
    }

    var symbolName: String {
        switch self {
        case .symbols: "chart.line.uptrend.xyaxis"
        case .alerts: "bell"
        case .source: "antenna.radiowaves.left.and.right"
        case .general: "gearshape"
        }
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
    /// Keychain writes are async now, so each keystroke's write is chained onto
    /// the previous one — left to run concurrently they can land out of order
    /// and persist a token the user has already typed past.
    @State private var tokenWrite: Task<Void, Never>?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var selectedPane: SettingsPane? = .symbols

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selectedPane) { pane in
                Label(pane.title, systemImage: pane.symbolName)
                    .tag(pane)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            detailView
                .navigationTitle((selectedPane ?? .symbols).title)
        }
        .task { relayToken = await Keychain.read(PreferenceKey.relayToken) ?? "" }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedPane ?? .symbols {
        case .symbols: symbolsPane
        case .alerts: alertsPane
        case .source: sourcePane
        case .general: generalPane
        }
    }

    private var symbolsPane: some View {
        Form {
            Section {
                TextField("Watchlist", text: $coins)
                Text("Space separated. A `|` splits menu-bar symbols from dropdown-only ones: `BTC ETH | NVDA QQQ`.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Menu Bar") {
                Toggle("Hide symbols in menu bar", isOn: $hideMenuBarSymbols)
                Toggle("Hide currency symbol", isOn: $hideCurrencySymbol)
            }
        }
        .formStyle(.grouped)
    }

    private var alertsPane: some View {
        Form {
            Section("Rules") {
                TextField("Percent rules", text: $alertRules)
                Text("`BTC:1 ETH:2` alerts when the price moves that percent from the last alert.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextField("Boundary rules", text: $integerAlertRules)
                Text("`BTC:1000 JUP:0.05` alerts when the price crosses a multiple of that step.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextField("Boundary cooldown (minutes)", text: $cooldownMinutes)
            }

            Section {
                Toggle("Play sound", isOn: $alertSoundEnabled)
            }
        }
        .formStyle(.grouped)
    }

    private var sourcePane: some View {
        Form {
            Section("Quotes") {
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
                            tokenWrite = Task { [previous = tokenWrite] in
                                await previous?.value
                                let stored = await Keychain.read(PreferenceKey.relayToken) ?? ""
                                guard token != stored else { return }
                                guard await Keychain.write(token, account: PreferenceKey.relayToken) else {
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
                        }
                    if let tokenError {
                        Text(tokenError)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
            }

            Section {
                Stepper("Refresh every \(refreshSeconds)s", value: $refreshSeconds, in: 5...600, step: 5)
            }
        }
        .formStyle(.grouped)
    }

    private var generalPane: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        setLaunchAtLogin(enabled)
                    }
            }

            Section("About") {
                LabeledContent("Version", value: Self.appVersion)
            }
        }
        .formStyle(.grouped)
    }

    /// "dev" outside a bundle (`swift run`), the Info.plist version inside one.
    private static let appVersion =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"

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
