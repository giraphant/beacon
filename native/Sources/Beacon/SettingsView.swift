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
        window.setContentSize(NSSize(width: 780, height: 600))
        window.minSize = NSSize(width: 700, height: 460)
        // The flow layout no longer needs the very wide frame users may have
        // saved while the symbol editor was a single horizontal row.
        window.setFrameAutosaveName("BeaconSettingsWindowFlowLayout")
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
    case general
    case symbols
    case source

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .symbols: "Symbols"
        case .source: "Source"
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .symbols: "chart.line.uptrend.xyaxis"
        case .source: "antenna.radiowaves.left.and.right"
        }
    }
}

struct SettingsView: View {
    @ObservedObject private var appModel = AppModel.shared
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
    @AppStorage(PreferenceKey.hudAlertsEnabled) private var hudAlertsEnabled = true
    @AppStorage(PreferenceKey.hudDurationSeconds)
    private var hudDurationSeconds = HUDDuration.defaultSeconds
    @AppStorage(PreferenceKey.systemNotificationsEnabled) private var systemNotificationsEnabled = false

    @State private var relayToken = ""
    @State private var tokenError: String?
    @State private var credentialsDebounce: Task<Void, Never>?
    /// Keychain writes are async now, so each keystroke's write is chained onto
    /// the previous one — left to run concurrently they can land out of order
    /// and persist a token the user has already typed past.
    @State private var tokenWrite: Task<Void, Never>?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var selectedPane: SettingsPane? = .general
    @State private var symbolRows: [SymbolSettingsEditorRow] = []
    @State private var structuredPreferencesLoaded = false
    @State private var notificationTestMessage: String?

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
                .navigationTitle((selectedPane ?? .general).title)
        }
        .task {
            loadStructuredPreferences()
            await appModel.refreshNotificationSettings()
            relayToken = await Keychain.read(PreferenceKey.relayToken) ?? ""
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task {
                await appModel.refreshNotificationSettings()
            }
        }
        .onChange(of: symbolRows) { _, rows in
            guard structuredPreferencesLoaded else { return }
            let values = serializeSymbolSettings(rows.compactMap(\.entry))
            if coins != values.coins { coins = values.coins }
            if alertRules != values.alertRules { alertRules = values.alertRules }
            if integerAlertRules != values.integerAlertRules {
                integerAlertRules = values.integerAlertRules
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedPane ?? .general {
        case .general: generalPane
        case .symbols: symbolsPane
        case .source: sourcePane
        }
    }

    private var symbolsPane: some View {
        ScrollView {
            SymbolSettingsEditor(rows: $symbolRows)
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var generalPane: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .help("Open Beacon automatically after you sign in.")
                    .onChange(of: launchAtLogin) { _, enabled in
                        setLaunchAtLogin(enabled)
                    }
            }

            Section("Display") {
                Toggle("Show symbols in the menu bar", isOn: showMenuBarSymbolsBinding)
                    .toggleStyle(.switch)
                    .help("Keep symbol names next to their rotating prices.")

                Toggle("Show the currency symbol", isOn: showCurrencySymbolBinding)
                    .toggleStyle(.switch)
                    .help("Prefix USD prices with a dollar sign.")
            }

            Section("Notifications") {
                Toggle("Floating HUD", isOn: $hudAlertsEnabled)
                    .toggleStyle(.switch)
                    .help("Show a Raycast-style floating alert without using system permissions.")

                if hudAlertsEnabled {
                    Stepper(
                        "HUD display time: \(hudDurationDisplayLabel)",
                        value: $hudDurationSeconds,
                        in: HUDDuration.range,
                        step: HUDDuration.step
                    )
                    .help("Choose how long each floating alert remains visible.")

                    Button("Preview Floating HUD") {
                        appModel.showTestHUD()
                    }
                }

                Toggle("Notification Center", isOn: $systemNotificationsEnabled)
                    .toggleStyle(.switch)
                    .help("Also keep alerts in macOS Notification Center.")
                    .onChange(of: systemNotificationsEnabled) { _, enabled in
                        guard enabled else { return }
                        Task {
                            await appModel.refreshNotificationSettings(requestIfNeeded: true)
                        }
                    }

                if systemNotificationsEnabled {
                    LabeledContent("System permission", value: appModel.notificationSettings.summary)

                    if let explanation = appModel.notificationSettings.explanation {
                        Text(explanation)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    if appModel.notificationSettings.authorizationStatus == .notDetermined,
                       appModel.notificationSettings.isLoaded {
                        Button("Allow Notifications") {
                            Task {
                                await appModel.refreshNotificationSettings(requestIfNeeded: true)
                            }
                        }
                    } else if appModel.notificationSettings.needsSystemSettings {
                        Button("Open Notification Settings") {
                            openBeaconNotificationSettings()
                        }
                    } else if appModel.notificationSettings.canSendTest {
                        Button("Send Test Notification") {
                            notificationTestMessage = nil
                            Task {
                                let sent = await appModel.sendTestNotification()
                                notificationTestMessage = sent
                                    ? "Test notification sent."
                                    : appModel.lastNotificationDeliveryError
                            }
                        }
                    }

                    if let notificationTestMessage {
                        Text(notificationTestMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else if let error = appModel.lastNotificationDeliveryError {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }

                Stepper(
                    "Price-level cooldown: \(cooldownDisplayLabel)",
                    value: cooldownBinding,
                    in: 0...1440,
                    step: 1
                )
                .help("Suppress a recently crossed level for this long.")

                Toggle("Play a sound", isOn: $alertSoundEnabled)
                    .toggleStyle(.switch)
                    .help("Play the system alert sound with each notification.")
            }

            Section("About") {
                LabeledContent("Version", value: Self.appVersion)
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

    /// "dev" outside a bundle (`swift run`), the Info.plist version inside one.
    private static let appVersion =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"

    private var showMenuBarSymbolsBinding: Binding<Bool> {
        Binding(
            get: { !hideMenuBarSymbols },
            set: { hideMenuBarSymbols = !$0 }
        )
    }

    private var showCurrencySymbolBinding: Binding<Bool> {
        Binding(
            get: { !hideCurrencySymbol },
            set: { hideCurrencySymbol = !$0 }
        )
    }

    private var cooldownBinding: Binding<Double> {
        Binding(
            get: { parseIntegerAlertCooldownMinutes(cooldownMinutes) },
            set: { value in
                cooldownMinutes = value == 0 ? "0" : (formatPreferenceNumber(value) ?? "10")
            }
        )
    }

    private var cooldownDisplay: String {
        let value = cooldownBinding.wrappedValue
        return value == 0 ? "Off" : (formatPreferenceNumber(value) ?? "10")
    }

    private var cooldownDisplayLabel: String {
        cooldownDisplay == "Off" ? "Off" : "\(cooldownDisplay) min"
    }

    private var hudDurationDisplayLabel: String {
        let value = HUDDuration.normalized(hudDurationSeconds)
        if value == value.rounded() {
            return "\(Int(value)) sec"
        }
        return String(format: "%.1f sec", value)
    }

    /// Convert the Raycast-era strings into rows once when Settings first
    /// opens. Saving still targets the old keys, so upgrades keep all working
    /// preferences and the Raycast extension remains compatible.
    private func loadStructuredPreferences() {
        guard !structuredPreferencesLoaded else { return }
        symbolRows = parseSymbolSettings(
            coins: coins,
            alertRules: alertRules,
            integerAlertRules: integerAlertRules
        ).map { SymbolSettingsEditorRow(entry: $0) }
        structuredPreferencesLoaded = true
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
