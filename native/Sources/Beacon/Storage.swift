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

    static let defaults: [String: Any] = [
        PreferenceKey.coins: "BTC ETH NVDA QQQ",
        PreferenceKey.integerAlertCooldownMinutes: "10",
        PreferenceKey.source: QuoteSourceKind.bybit.rawValue,
        PreferenceKey.refreshSeconds: 30,
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
            alertSoundEnabled: store.bool(forKey: PreferenceKey.alertSoundEnabled)
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
    private static let service = "com.inol.beacon"

    /// Every `SecItemCopyMatching` can raise the access prompt, so reading once
    /// per refresh means a dialog every 30s on a bundle whose signature macOS
    /// does not recognise. Cache the value for the process lifetime; `write` is
    /// the only thing that can invalidate it.
    private static var cache: [String: String?] = [:]

    static func read(_ account: String) -> String? {
        if let cached = cache[account] { return cached }
        let value = load(account)
        cache[account] = value
        return value
    }

    private static func load(_ account: String) -> String? {
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
    static func write(_ value: String, account: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        guard !value.isEmpty else {
            let status = SecItemDelete(base as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { return false }
            cache[account] = String?.none
            return true
        }

        let data = Data(value.utf8)
        var status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = base
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(insert as CFDictionary, nil)
        }
        guard status == errSecSuccess else { return false }
        cache[account] = value
        return true
    }
}
