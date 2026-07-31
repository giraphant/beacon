import BeaconCore
import Foundation

enum PreferenceKey {
    static let coins = "coins"
    static let alertRules = "alertRules"
    static let integerAlertRules = "integerAlertRules"
    static let integerAlertCooldownMinutes = "integerAlertCooldownMinutes"
    static let hideMenuBarSymbols = "hideMenuBarSymbols"
    static let hideCurrencySymbol = "hideCurrencySymbol"
    static let source = "source"
    static let relayUrl = "relayUrl"
    static let refreshSeconds = "refreshSeconds"
    static let alertSoundEnabled = "alertSoundEnabled"
    static let hudAlertsEnabled = "hudAlertsEnabled"
    static let hudDurationSeconds = "hudDurationSeconds"
    static let systemNotificationsEnabled = "systemNotificationsEnabled"
}

enum HUDDuration {
    static let defaultSeconds = 3.0
    static let range = 1.0...10.0
    static let step = 0.5

    static func normalized(_ value: Double) -> Double {
        guard value.isFinite else { return defaultSeconds }
        return min(range.upperBound, max(range.lowerBound, value))
    }
}

struct Preferences: Equatable {
    var coins: String
    var alertRules: String
    var integerAlertRules: String
    var integerAlertCooldownMinutes: String
    var hideMenuBarSymbols: Bool
    var hideCurrencySymbol: Bool
    var source: QuoteSourceKind
    var relayURL: String
    var refreshSeconds: Double
    var alertSoundEnabled: Bool
    var hudAlertsEnabled: Bool
    var hudDurationSeconds: Double
    var systemNotificationsEnabled: Bool

    static let defaults: [String: Any] = [
        PreferenceKey.coins: "BTC ETH NVDA QQQ",
        PreferenceKey.integerAlertCooldownMinutes: "10",
        PreferenceKey.source: QuoteSourceKind.bybit.rawValue,
        PreferenceKey.refreshSeconds: 30,
        PreferenceKey.hudAlertsEnabled: true,
        PreferenceKey.hudDurationSeconds: HUDDuration.defaultSeconds,
        PreferenceKey.systemNotificationsEnabled: false,
    ]

    static func load(_ store: UserDefaults = .standard) -> Preferences {
        Preferences(
            coins: store.string(forKey: PreferenceKey.coins) ?? "",
            alertRules: store.string(forKey: PreferenceKey.alertRules) ?? "",
            integerAlertRules: store.string(forKey: PreferenceKey.integerAlertRules) ?? "",
            integerAlertCooldownMinutes: store.string(forKey: PreferenceKey.integerAlertCooldownMinutes) ?? "",
            hideMenuBarSymbols: store.bool(forKey: PreferenceKey.hideMenuBarSymbols),
            hideCurrencySymbol: store.bool(forKey: PreferenceKey.hideCurrencySymbol),
            source: QuoteSourceKind(rawValue: store.string(forKey: PreferenceKey.source) ?? "") ?? .bybit,
            relayURL: store.string(forKey: PreferenceKey.relayUrl) ?? "",
            // Clamped so a stray 0 in defaults cannot turn the timer into a spin loop.
            refreshSeconds: max(5, store.double(forKey: PreferenceKey.refreshSeconds)),
            alertSoundEnabled: store.bool(forKey: PreferenceKey.alertSoundEnabled),
            hudAlertsEnabled: store.bool(forKey: PreferenceKey.hudAlertsEnabled),
            hudDurationSeconds: HUDDuration.normalized(
                (store.object(forKey: PreferenceKey.hudDurationSeconds) as? NSNumber)?.doubleValue
                    ?? HUDDuration.defaultSeconds
            ),
            systemNotificationsEnabled: store.bool(forKey: PreferenceKey.systemNotificationsEnabled)
        )
    }
}

// MARK: - Alert state

/// Keys carry the threshold so editing a rule starts a fresh baseline instead of
/// comparing against a price captured under the old threshold.
struct AlertStateStore {
    var store: UserDefaults = .standard

    func alertState(symbol: String, thresholdPercent: Double) -> AlertState? {
        decode(key("alert-state:", symbol, thresholdPercent))
    }

    func save(_ state: AlertState, thresholdPercent: Double) {
        encode(state, key("alert-state:", state.symbol, thresholdPercent))
    }

    func integerAlertState(symbol: String, step: Double) -> IntegerAlertState? {
        decode(key("integer-alert-state:", symbol, step))
    }

    func save(_ state: IntegerAlertState, step: Double) {
        encode(state, key("integer-alert-state:", state.symbol, step))
    }

    private func decode<T: Decodable>(_ key: String) -> T? {
        guard let data = store.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func encode(_ value: some Encodable, _ key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        store.set(data, forKey: key)
    }

    private func key(_ prefix: String, _ symbol: String, _ value: Double) -> String {
        "\(prefix)\(symbol):\(formatNumberKey(value))"
    }
}

/// Matches JavaScript number-to-string so keys stay stable: `1` not `1.0`.
func formatNumberKey(_ value: Double) -> String {
    value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(value)
}

// MARK: - Keychain

/// The relay token is a bearer credential; UserDefaults is a plaintext plist, so
/// it lives in the keychain instead.
@MainActor
enum Keychain {
    nonisolated private static let service = "com.inol.beacon"

    private enum CacheEntry {
        case value(String)
        case missing

        var value: String? {
            switch self {
            case let .value(value): value
            case .missing: nil
            }
        }
    }

    /// Every `SecItemCopyMatching` can raise the access prompt, so reading once
    /// per refresh means a dialog every 30s on a bundle whose signature macOS
    /// does not recognise. Cache the value for the process lifetime; `write` is
    /// the only thing that can invalidate it.
    private static var cache: [String: CacheEntry] = [:]
    /// App startup and Settings can ask for the relay token at the same time.
    /// Cache alone is insufficient while the first read is still suspended on
    /// the system access dialog, so concurrent callers share the same task.
    private static var pendingReads: [String: Task<String?, Never>] = [:]

    /// Off the main thread, always. A `SecItem*` call blocks until the user
    /// answers the access dialog — and that dialog cannot be drawn while the
    /// main thread is the thing waiting for it, so calling this synchronously
    /// deadlocks the app on launch: the run loop never turns, the status item
    /// keeps its empty title, and macOS eventually tears down the unresponsive
    /// menu bar scene. Symptom is an app that runs with no icon and no crash.
    static func read(_ account: String) async -> String? {
        await read(account, loader: { load(account) })
    }

    static func read(
        _ account: String,
        loader: @escaping @Sendable () -> String?
    ) async -> String? {
        if let cached = cache[account] { return cached.value }
        if let pending = pendingReads[account] { return await pending.value }

        let pending = Task.detached(priority: .utility, operation: loader)
        pendingReads[account] = pending
        let value = await pending.value
        pendingReads[account] = nil
        cache[account] = value.map(CacheEntry.value) ?? .missing
        return value
    }

    static func resetCacheForTesting() {
        pendingReads.values.forEach { $0.cancel() }
        pendingReads.removeAll()
        cache.removeAll()
    }

    nonisolated private static func load(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Update-or-add, not delete-then-add: a failed add after a successful
    /// delete loses the token outright. The cache only advances once the
    /// keychain has actually taken the value, so a failure cannot leave the app
    /// authenticating with a token that was never stored.
    @discardableResult
    static func write(_ value: String, account: String) async -> Bool {
        if let pending = pendingReads[account] {
            _ = await pending.value
            pendingReads[account] = nil
        }
        let saved = await Task.detached(priority: .utility) { store(value, account) }.value
        guard saved else { return false }
        cache[account] = value.isEmpty ? .missing : .value(value)
        return true
    }

    nonisolated private static func store(_ value: String, _ account: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        guard !value.isEmpty else {
            let status = SecItemDelete(base as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }

        let data = Data(value.utf8)
        var status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = base
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(insert as CFDictionary, nil)
        }
        return status == errSecSuccess
    }
}
