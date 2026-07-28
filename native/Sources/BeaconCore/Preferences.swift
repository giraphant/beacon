import Foundation

public let defaultIntegerAlertCooldownMinutes: Double = 10

/// `[0-9]` rather than `\d`: Swift's `\d` is Unicode-aware and would accept
/// non-ASCII digits that the JavaScript original rejects.
private let ruleRegex = /([A-Za-z0-9._-]+):([0-9]+(?:\.[0-9]+)?)/
private let symbolRegex = /[A-Za-z0-9._-]+/

private func isSeparator(_ character: Character) -> Bool {
    character.isWhitespace || character == "," || character == "|"
}

private func normalizeSymbol(_ value: some StringProtocol) -> String {
    value.trimmingCharacters(in: .whitespaces).uppercased()
}

/// Canonicalizes one symbol entered in the native settings UI. Unlike
/// `parseSymbolsText`, this deliberately accepts exactly one token: a row that
/// contains `BTC ETH` is an editing error, not two silently-created rows.
public func normalizePreferenceSymbol(_ value: String) -> String? {
    let normalized = normalizeSymbol(value)
    guard !normalized.isEmpty,
          (try? symbolRegex.wholeMatch(in: normalized)) != nil
    else { return nil }
    return normalized
}

/// Keeps the first occurrence of each symbol, dropping later duplicates.
private func dedupeSymbols(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { !$0.isEmpty && seen.insert($0).inserted }
}

private func parseSymbolTokens(_ text: some StringProtocol) -> [String] {
    dedupeSymbols(text.split(whereSeparator: isSeparator).map(normalizeSymbol))
}

public func parseSymbolsText(_ text: String) -> [String] {
    parseSymbolTokens(text)
}

public struct CoinDisplay: Equatable {
    public var titleSymbols: [String]
    public var quoteSymbols: [String]
}

/// `BTC ETH | NVDA` shows BTC and ETH in the menu bar title and keeps NVDA in
/// the dropdown only. Without a pipe, every symbol goes in the title.
public func parseCoinDisplayText(_ text: String) -> CoinDisplay {
    guard let pipeIndex = text.firstIndex(of: "|") else {
        let symbols = parseSymbolTokens(text)
        return CoinDisplay(titleSymbols: symbols, quoteSymbols: symbols)
    }

    let titleSymbols = parseSymbolTokens(text[text.startIndex..<pipeIndex])
    let dropdownOnlySymbols = parseSymbolTokens(text[text.index(after: pipeIndex)...])
    return CoinDisplay(
        titleSymbols: titleSymbols,
        quoteSymbols: dedupeSymbols(titleSymbols + dropdownOnlySymbols)
    )
}

public struct ParsedRules<Rule: Equatable>: Equatable {
    public var rules: [Rule]
    public var invalidTokens: [String]
}

public func parseAlertRulesText(_ text: String) -> ParsedRules<AlertRule> {
    parseRuleTokens(text) { AlertRule(symbol: $0, thresholdPercent: $1) }
}

public func parseIntegerAlertRulesText(_ text: String) -> ParsedRules<IntegerAlertRule> {
    parseRuleTokens(text) { IntegerAlertRule(symbol: $0, step: $1) }
}

public func parseIntegerAlertCooldownMinutes(_ text: String?) -> Double {
    let trimmed = text?.trimmingCharacters(in: .whitespaces) ?? ""
    guard !trimmed.isEmpty, let value = Double(trimmed), value.isFinite, value >= 0 else {
        return defaultIntegerAlertCooldownMinutes
    }
    return value
}

private func parseRuleTokens<Rule: Equatable>(
    _ text: String,
    createRule: (String, Double) -> Rule
) -> ParsedRules<Rule> {
    var symbols: [String] = []
    var rulesBySymbol: [String: Rule] = [:]
    var invalidTokens: [String] = []

    for rawToken in text.split(whereSeparator: isSeparator) {
        let token = rawToken.trimmingCharacters(in: .whitespaces)
        if token.isEmpty { continue }

        guard let match = try? ruleRegex.wholeMatch(in: token) else {
            invalidTokens.append(token)
            continue
        }

        let symbol = normalizeSymbol(match.1)
        guard let value = Double(match.2), value.isFinite, value > 0, !symbol.isEmpty else {
            invalidTokens.append(token)
            continue
        }

        // A repeated symbol replaces the earlier rule *and* moves to the end,
        // matching the Map delete-then-set in the TypeScript original.
        symbols.removeAll { $0 == symbol }
        symbols.append(symbol)
        rulesBySymbol[symbol] = createRule(symbol, value)
    }

    return ParsedRules(rules: symbols.compactMap { rulesBySymbol[$0] }, invalidTokens: invalidTokens)
}

// MARK: - Structured settings adapters

/// The native settings UI edits rows, while the Raycast-era preference remains
/// a compact string. This adapter is the compatibility boundary between them.
public struct WatchlistEntry: Equatable, Sendable {
    public var symbol: String
    public var showInMenuBar: Bool

    public init(symbol: String, showInMenuBar: Bool = true) {
        self.symbol = symbol
        self.showInMenuBar = showInMenuBar
    }
}

public func parseWatchlistText(_ text: String) -> [WatchlistEntry] {
    let display = parseCoinDisplayText(text)
    let titleSymbols = Set(display.titleSymbols)
    return display.quoteSymbols.map {
        WatchlistEntry(symbol: $0, showInMenuBar: titleSymbols.contains($0))
    }
}

/// Serializes rows back to the format shared with the Raycast extension.
/// Menu-bar symbols must precede `|` in that format, so the two visibility
/// groups keep their own relative order.
public func serializeWatchlist(_ entries: [WatchlistEntry]) -> String {
    var seen = Set<String>()
    let normalized = entries.compactMap { entry -> WatchlistEntry? in
        guard let symbol = normalizePreferenceSymbol(entry.symbol),
              seen.insert(symbol).inserted
        else { return nil }
        return WatchlistEntry(symbol: symbol, showInMenuBar: entry.showInMenuBar)
    }

    let title = normalized.filter(\.showInMenuBar).map(\.symbol)
    let dropdownOnly = normalized.filter { !$0.showInMenuBar }.map(\.symbol)
    var result = title.joined(separator: " ")
    if !dropdownOnly.isEmpty {
        result += (result.isEmpty ? "| " : " | ") + dropdownOnly.joined(separator: " ")
    }
    return result
}

/// A plain decimal representation accepted by the legacy rule parser.
/// `String(Double)` may emit scientific notation for small crypto steps.
public func formatPreferenceNumber(_ value: Double) -> String? {
    guard value.isFinite, value > 0 else { return nil }
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = false
    formatter.minimumIntegerDigits = 1
    formatter.maximumFractionDigits = 16
    guard let text = formatter.string(from: NSNumber(value: value)),
          Double(text).map({ $0 > 0 }) == true
    else { return nil }
    return text
}

public func serializeAlertRules(_ rules: [AlertRule]) -> String {
    serializeRules(rules.map { ($0.symbol, $0.thresholdPercent) })
}

public func serializeIntegerAlertRules(_ rules: [IntegerAlertRule]) -> String {
    serializeRules(rules.map { ($0.symbol, $0.step) })
}

private func serializeRules(_ values: [(symbol: String, value: Double)]) -> String {
    var order: [String] = []
    var valuesBySymbol: [String: Double] = [:]

    for item in values {
        guard let symbol = normalizePreferenceSymbol(item.symbol),
              formatPreferenceNumber(item.value) != nil
        else { continue }
        // Keep the parser's established "last duplicate wins and moves last"
        // behavior, even while the UI marks duplicates for the user.
        order.removeAll { $0 == symbol }
        order.append(symbol)
        valuesBySymbol[symbol] = item.value
    }

    return order.compactMap { symbol in
        guard let value = valuesBySymbol[symbol],
              let text = formatPreferenceNumber(value)
        else { return nil }
        return "\(symbol):\(text)"
    }.joined(separator: " ")
}

// MARK: - Unified symbol settings

public enum SymbolDisplayMode: String, CaseIterable, Equatable, Hashable, Sendable {
    case menuBar
    case dropdown
    case alertsOnly
}

/// One row in the native settings editor. It is a structured view over all
/// three Raycast-era strings, not a new persistence format.
public struct SymbolSettingsEntry: Equatable, Sendable {
    public var symbol: String
    public var displayMode: SymbolDisplayMode
    public var alertPercent: Double?
    public var boundaryStep: Double?

    public init(
        symbol: String,
        displayMode: SymbolDisplayMode = .menuBar,
        alertPercent: Double? = nil,
        boundaryStep: Double? = nil
    ) {
        self.symbol = symbol
        self.displayMode = displayMode
        self.alertPercent = alertPercent
        self.boundaryStep = boundaryStep
    }
}

public struct SymbolSettingsStrings: Equatable, Sendable {
    public var coins: String
    public var alertRules: String
    public var integerAlertRules: String

    public init(coins: String, alertRules: String, integerAlertRules: String) {
        self.coins = coins
        self.alertRules = alertRules
        self.integerAlertRules = integerAlertRules
    }
}

/// Merge watchlist, percentage rules and price-level rules into one ordered
/// table. Alert-only symbols are appended instead of being discarded.
public func parseSymbolSettings(
    coins: String,
    alertRules: String,
    integerAlertRules: String
) -> [SymbolSettingsEntry] {
    let display = parseCoinDisplayText(coins)
    let titleSymbols = Set(display.titleSymbols)
    let quoteSymbols = Set(display.quoteSymbols)
    let percentRules = parseAlertRulesText(alertRules).rules
    let boundaryRules = parseIntegerAlertRulesText(integerAlertRules).rules
    let percents = Dictionary(
        percentRules.map { ($0.symbol, $0.thresholdPercent) },
        uniquingKeysWith: { _, last in last }
    )
    let steps = Dictionary(
        boundaryRules.map { ($0.symbol, $0.step) },
        uniquingKeysWith: { _, last in last }
    )

    var order = display.quoteSymbols
    var seen = Set(order)
    for symbol in percentRules.map(\.symbol) + boundaryRules.map(\.symbol)
    where seen.insert(symbol).inserted {
        order.append(symbol)
    }

    return order.map { symbol in
        let displayMode: SymbolDisplayMode
        if titleSymbols.contains(symbol) {
            displayMode = .menuBar
        } else if quoteSymbols.contains(symbol) {
            displayMode = .dropdown
        } else {
            displayMode = .alertsOnly
        }
        return SymbolSettingsEntry(
            symbol: symbol,
            displayMode: displayMode,
            alertPercent: percents[symbol],
            boundaryStep: steps[symbol]
        )
    }
}

/// Split the unified rows back into the existing preference keys. Duplicate
/// symbols keep the first row so every column resolves to the same row.
public func serializeSymbolSettings(_ entries: [SymbolSettingsEntry]) -> SymbolSettingsStrings {
    var seen = Set<String>()
    let normalized = entries.compactMap { entry -> SymbolSettingsEntry? in
        guard let symbol = normalizePreferenceSymbol(entry.symbol),
              seen.insert(symbol).inserted
        else { return nil }
        return SymbolSettingsEntry(
            symbol: symbol,
            displayMode: entry.displayMode,
            alertPercent: entry.alertPercent,
            boundaryStep: entry.boundaryStep
        )
    }

    let watchlist = normalized.compactMap { entry -> WatchlistEntry? in
        switch entry.displayMode {
        case .menuBar:
            return WatchlistEntry(symbol: entry.symbol, showInMenuBar: true)
        case .dropdown:
            return WatchlistEntry(symbol: entry.symbol, showInMenuBar: false)
        case .alertsOnly:
            return nil
        }
    }
    let percentRules = normalized.compactMap { entry -> AlertRule? in
        guard let value = entry.alertPercent else { return nil }
        return AlertRule(symbol: entry.symbol, thresholdPercent: value)
    }
    let boundaryRules = normalized.compactMap { entry -> IntegerAlertRule? in
        guard let value = entry.boundaryStep else { return nil }
        return IntegerAlertRule(symbol: entry.symbol, step: value)
    }

    return SymbolSettingsStrings(
        coins: serializeWatchlist(watchlist),
        alertRules: serializeAlertRules(percentRules),
        integerAlertRules: serializeIntegerAlertRules(boundaryRules)
    )
}
