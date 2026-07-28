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

/// UI row for the symbol table. The rule cells keep the user's raw text —
/// parsing happens on serialize, so half-typed numbers don't get clobbered
/// mid-edit.
private struct SymbolRow: Identifiable, Equatable {
    let id = UUID()
    var symbol: String
    var inMenuBar: Bool
    var percentText: String
    var stepText: String

    init(entry: SymbolTableEntry = SymbolTableEntry(symbol: "")) {
        symbol = entry.symbol
        inMenuBar = entry.inMenuBar
        percentText = entry.alertPercent.flatMap(formatRuleValue) ?? ""
        stepText = entry.boundaryStep.flatMap(formatRuleValue) ?? ""
    }

    var entry: SymbolTableEntry {
        SymbolTableEntry(
            symbol: symbol, inMenuBar: inMenuBar,
            alertPercent: Self.parseRuleText(percentText),
            boundaryStep: Self.parseRuleText(stepText)
        )
    }

    static func parseRuleText(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let value = Double(trimmed), value.isFinite, value > 0 else { return nil }
        return value
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
    @State private var selectedPane: SettingsPane? = .symbols
    @State private var symbolRows: [SymbolRow] = []
    @State private var symbolSelection: SymbolRow.ID?

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
        .onAppear { relayToken = Keychain.read(PreferenceKey.relayToken) ?? "" }
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Symbol").frame(maxWidth: .infinity, alignment: .leading)
                Text("Menu Bar").frame(width: 64)
                Text("Alert %").frame(width: 72)
                Text("Step").frame(width: 84)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)

            List(selection: $symbolSelection) {
                ForEach($symbolRows) { $row in
                    HStack(spacing: 8) {
                        TextField("Symbol", text: $row.symbol, prompt: Text("SYMBOL"))
                            .textFieldStyle(.plain)
                            .frame(maxWidth: .infinity)
                        Toggle("In menu bar", isOn: $row.inMenuBar)
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                            .frame(width: 64)
                        ruleField("Alert %", text: $row.percentText, width: 72)
                        ruleField("Step", text: $row.stepText, width: 84)
                    }
                }
                .onMove { symbolRows.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.bordered)
            .alternatingRowBackgrounds()
            .onDeleteCommand(perform: removeSelectedSymbolRow)

            HStack(spacing: 12) {
                Button(action: addSymbolRow) { Image(systemName: "plus") }
                Button(action: removeSelectedSymbolRow) { Image(systemName: "minus") }
                    .disabled(symbolSelection == nil)
            }
            .buttonStyle(.borderless)

            Text("Checked symbols cycle through the menu-bar title; unchecked ones only appear in the dropdown. Drag rows to reorder. Alert % notifies when the price moves that percent since the last alert, Step when it crosses a multiple of that step — leave a cell empty for no alert.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .onAppear(perform: loadSymbolRows)
        .onChange(of: symbolRows) { _, rows in storeSymbolRows(rows) }
    }

    /// A rule cell: free text, red while it holds something that isn't a
    /// positive number (which serializes as "no rule").
    private func ruleField(_ title: String, text: Binding<String>, width: CGFloat) -> some View {
        let invalid = SymbolRow.parseRuleText(text.wrappedValue) == nil
            && !text.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty
        return TextField(title, text: text, prompt: Text("—"))
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .foregroundStyle(invalid ? Color.red : Color.primary)
            .frame(width: width)
    }

    private func loadSymbolRows() {
        symbolRows = parseSymbolTable(
            coins: coins, alertRules: alertRules, integerAlertRules: integerAlertRules
        ).map(SymbolRow.init(entry:))
    }

    private func storeSymbolRows(_ rows: [SymbolRow]) {
        let strings = serializeSymbolTable(rows.map(\.entry))
        if coins != strings.coins { coins = strings.coins }
        if alertRules != strings.alertRules { alertRules = strings.alertRules }
        if integerAlertRules != strings.integerAlertRules { integerAlertRules = strings.integerAlertRules }
    }

    private func addSymbolRow() {
        let row = SymbolRow()
        symbolRows.append(row)
        symbolSelection = row.id
    }

    private func removeSelectedSymbolRow() {
        guard let selection = symbolSelection else { return }
        symbolRows.removeAll { $0.id == selection }
        symbolSelection = nil
    }

    private var alertsPane: some View {
        Form {
            Section {
                Stepper(
                    "Boundary cooldown: \(cooldownMinutesBinding.wrappedValue) min",
                    value: cooldownMinutesBinding, in: 0...240, step: 5
                )
                Text("Spaces out repeated boundary-crossing alerts. Per-symbol thresholds live in the Symbols table.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Toggle("Play sound", isOn: $alertSoundEnabled)
            }
        }
        .formStyle(.grouped)
    }

    /// The preference stays a string (Raycast heritage); the stepper wants Int.
    private var cooldownMinutesBinding: Binding<Int> {
        Binding(
            get: { Int(parseIntegerAlertCooldownMinutes(cooldownMinutes)) },
            set: { cooldownMinutes = String($0) }
        )
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

            Section("Menu Bar") {
                Toggle("Hide symbols in menu bar", isOn: $hideMenuBarSymbols)
                Toggle("Hide currency symbol", isOn: $hideCurrencySymbol)
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
