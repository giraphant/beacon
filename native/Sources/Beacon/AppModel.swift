import AppKit
import BeaconCore
import Foundation
import UserNotifications

@MainActor
final class AppModel: ObservableObject {
    /// Settings is an AppKit window with no route back to the SwiftUI scene, so
    /// the one model it needs to poke is reachable from here.
    static let shared = AppModel()

    @Published private(set) var menu = MenuBarModel(title: "Beacon", isLoading: true, items: [], sections: [])
    @Published private(set) var recentAlerts: [String: RecentAlert] = [:]

    private let stateStore = AlertStateStore()
    private let diagnostics = QuoteDiagnosticLogger.shared
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var refreshPending = false
    private var settingsDebounce: Task<Void, Never>?

    /// `lastGood` only ever holds a successful fetch, so a run of failures shows
    /// the last real prices with one error appended rather than accumulating one
    /// error per failed tick.
    private var lastGood: QuoteFetchResult?
    private var displayed: QuoteFetchResult?
    private var lastSourceSignature: String?
    private var lastPreferences: Preferences?
    private var scheduledInterval: TimeInterval = 0
    private var started = false

    /// Idempotent: the caller may re-run this on a rebuilt menu bar.
    func start() {
        guard !started else { return }
        started = true
        UserDefaults.standard.register(defaults: Preferences.defaults)
        requestNotificationAuthorization()
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.settingsChanged() }
        }
        triggerRefresh()
    }

    /// A request arriving mid-fetch is requeued rather than dropped. Dropping it
    /// meant a settings change made while a slow fetch was in flight went
    /// unnoticed until the next tick — up to 600s of quoting the old source, or
    /// firing an alert the user had just switched off.
    func triggerRefresh() {
        guard refreshTask == nil else {
            refreshPending = true
            return
        }
        refreshTask = Task { [weak self] in
            await self?.refresh()
            self?.refreshTask = nil
            guard self?.refreshPending == true else { return }
            self?.refreshPending = false
            self?.triggerRefresh()
        }
    }

    /// The relay token lives in the keychain, not defaults, so nothing posts a
    /// `didChangeNotification` for it — Settings has to say so directly.
    func credentialsChanged() {
        lastSourceSignature = nil
        triggerRefresh()
    }

    func dismissAlerts() {
        recentAlerts = [:]
    }

    // MARK: - Refresh

    private func refresh() async {
        let preferences = Preferences.load()
        lastPreferences = preferences
        let display = parseCoinDisplayText(preferences.coins)
        let percentRules = parseAlertRulesText(preferences.alertRules)
        let integerRules = parseIntegerAlertRulesText(preferences.integerAlertRules)
        let cooldownMs = parseIntegerAlertCooldownMinutes(preferences.integerAlertCooldownMinutes) * 60_000

        schedule(interval: preferences.refreshSeconds)

        let signature = quoteSourceSignature(preferences.source, relayURL: preferences.relayURL)
        if signature != lastSourceSignature {
            lastSourceSignature = signature
            lastGood = nil
            displayed = nil
        }

        var seen = Set<String>()
        let quoteSymbols = (display.quoteSymbols
            + percentRules.rules.map(\.symbol)
            + integerRules.rules.map(\.symbol))
            .filter { seen.insert($0).inserted }

        guard !quoteSymbols.isEmpty else {
            rebuild(preferences, display, percentRules, integerRules)
            return
        }

        let now = Date().timeIntervalSince1970 * 1000
        let diagnosticRequest = await diagnostics.begin(
            source: preferences.source,
            symbols: quoteSymbols,
            at: now
        )
        do {
            let result = try await fetchQuotes(
                symbols: quoteSymbols,
                source: preferences.source,
                relayURL: preferences.relayURL,
                // Only the relay source sends it; an exchange user should never
                // see a keychain prompt for a credential nothing reads.
                relayToken: preferences.source == .relay ? await Keychain.read(PreferenceKey.relayToken) : nil,
                now: now
            )
            lastGood = result
            displayed = result
            let completedAt = Date().timeIntervalSince1970 * 1_000
            await diagnostics.succeeded(diagnosticRequest, result: result, at: completedAt)
            await diagnostics.displayed(diagnosticRequest, origin: .live, result: result, at: completedAt)
            // Settings changed while this fetch was in flight: these quotes were
            // taken under rules the user has since replaced, and the requeued
            // refresh will re-evaluate them under the new ones.
            if Preferences.load() == preferences {
                await runAlerts(
                    preferences: preferences,
                    percentRules: percentRules.rules,
                    integerRules: integerRules.rules,
                    cooldownMs: cooldownMs,
                    quotes: result.quotes,
                    now: now
                )
            }
        } catch {
            let message = quoteErrorMessage(error)
            let completedAt = Date().timeIntervalSince1970 * 1_000
            await diagnostics.failed(diagnosticRequest, error: error, at: completedAt)
            if var cached = lastGood {
                cached.errors.append(message)
                displayed = cached
                await diagnostics.displayed(
                    diagnosticRequest,
                    origin: .cacheAfterError,
                    result: cached,
                    at: completedAt
                )
            } else {
                let errorOnly = QuoteFetchResult(errors: [message])
                displayed = errorOnly
                await diagnostics.displayed(
                    diagnosticRequest,
                    origin: .errorOnly,
                    result: errorOnly,
                    at: completedAt
                )
            }
        }

        rebuild(preferences, display, percentRules, integerRules)
    }

    private func rebuild(
        _ preferences: Preferences,
        _ display: CoinDisplay,
        _ percentRules: ParsedRules<AlertRule>,
        _ integerRules: ParsedRules<IntegerAlertRule>
    ) {
        menu = buildMenuBarModel(MenuBarModelInput(
            displaySymbols: display.quoteSymbols,
            titleSymbols: display.titleSymbols,
            hideTitleSymbols: preferences.hideMenuBarSymbols,
            hideCurrencySymbol: preferences.hideCurrencySymbol,
            quoteResult: displayed,
            invalidRuleTokens: percentRules.invalidTokens,
            invalidIntegerRuleTokens: integerRules.invalidTokens,
            isLoading: displayed == nil,
            now: Date().timeIntervalSince1970 * 1000
        ))
    }

    // MARK: - Alerts

    /// Stale quotes are excluded: alerting on a price the relay already flagged
    /// as not-current would fire on data the user cannot act on.
    private func runAlerts(
        preferences: Preferences,
        percentRules: [AlertRule],
        integerRules: [IntegerAlertRule],
        cooldownMs: Double,
        quotes: [String: Quote],
        now: Millis
    ) async {
        guard !percentRules.isEmpty || !integerRules.isEmpty else { return }
        let fresh = quotes.filter { !$0.value.stale }

        _ = await BeaconCore.runAlerts(
            rules: percentRules,
            quotes: fresh,
            now: now,
            getState: { [stateStore] symbol, threshold in
                stateStore.alertState(symbol: symbol, thresholdPercent: threshold)
            },
            saveState: { [stateStore] state, threshold in
                stateStore.save(state, thresholdPercent: threshold)
            },
            notify: { [weak self] notification in
                await self?.deliver(notification, now: now, playSound: preferences.alertSoundEnabled)
            }
        )

        _ = await runIntegerAlerts(
            rules: integerRules,
            quotes: fresh,
            now: now,
            cooldownMs: cooldownMs,
            getState: { [stateStore] symbol, step in
                stateStore.integerAlertState(symbol: symbol, step: step)
            },
            saveState: { [stateStore] state, step in
                stateStore.save(state, step: step)
            },
            notify: { [weak self] notification in
                await self?.deliver(notification, now: now, playSound: preferences.alertSoundEnabled)
            }
        )
    }

    /// Never throws: the menu-bar indicator below is a delivery channel that
    /// cannot fail, so a denied banner permission must not stop alert state from
    /// advancing (which would re-fire the same alert on every refresh).
    private func deliver(_ notification: AlertNotification, now: Millis, playSound: Bool) async {
        recentAlerts[notification.symbol] = RecentAlert(notification: notification, triggeredAt: now)

        if playSound {
            NSSound(named: "Glass")?.play()
        }

        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.message
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func requestNotificationAuthorization() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - Scheduling

    /// Tolerance lets macOS coalesce this wakeup with others already scheduled —
    /// the single biggest power lever a polling menu-bar app has.
    private func schedule(interval: TimeInterval) {
        guard interval != scheduledInterval else { return }
        scheduledInterval = interval
        timer?.invalidate()

        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.triggerRefresh() }
        }
        timer.tolerance = interval * 0.2
        self.timer = timer
    }

    /// Typing in a settings field fires a change per keystroke; wait for a pause
    /// before spending a network round trip on it.
    ///
    /// Alert state lives in the same defaults domain, so saving it also fires
    /// this — comparing against the last loaded preferences is what stops a
    /// refresh → save → refresh feedback loop once any alert rule exists.
    private func settingsChanged() {
        let preferences = Preferences.load()
        guard preferences != lastPreferences else { return }
        lastPreferences = preferences

        settingsDebounce?.cancel()
        settingsDebounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            self?.triggerRefresh()
        }
    }
}

private func quoteErrorMessage(_ error: Error) -> String {
    (error as? QuoteError)?.message ?? error.localizedDescription
}

extension PreferenceKey {
    static let relayToken = "relayToken"
}
