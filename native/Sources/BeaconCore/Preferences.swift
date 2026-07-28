import Foundation

public let defaultIntegerAlertCooldownMinutes: Double = 10

/// `[0-9]` rather than `\d`: Swift's `\d` is Unicode-aware and would accept
/// non-ASCII digits that the JavaScript original rejects.
private let ruleRegex = /([A-Za-z0-9._-]+):([0-9]+(?:\.[0-9]+)?)/

private func isSeparator(_ character: Character) -> Bool {
    character.isWhitespace || character == "," || character == "|"
}

private func normalizeSymbol(_ value: some StringProtocol) -> String {
    value.trimmingCharacters(in: .whitespaces).uppercased()
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

// MARK: - Symbol table

/// One row of the Settings symbol table — the structured view over the
/// `coins` / `alertRules` / `integerAlertRules` preference strings. `nil`
/// percent/step means "no such alert for this symbol".
public struct SymbolTableEntry: Equatable, Sendable {
    public var symbol: String
    public var inMenuBar: Bool
    public var alertPercent: Double?
    public var boundaryStep: Double?

    public init(
        symbol: String, inMenuBar: Bool = true,
        alertPercent: Double? = nil, boundaryStep: Double? = nil
    ) {
        self.symbol = symbol
        self.inMenuBar = inMenuBar
        self.alertPercent = alertPercent
        self.boundaryStep = boundaryStep
    }
}

public func parseSymbolTable(
    coins: String, alertRules: String, integerAlertRules: String
) -> [SymbolTableEntry] {
    let display = parseCoinDisplayText(coins)
    let titleSymbols = Set(display.titleSymbols)
    let percents = Dictionary(
        parseAlertRulesText(alertRules).rules.map { ($0.symbol, $0.thresholdPercent) },
        uniquingKeysWith: { _, last in last }
    )
    let steps = Dictionary(
        parseIntegerAlertRulesText(integerAlertRules).rules.map { ($0.symbol, $0.step) },
        uniquingKeysWith: { _, last in last }
    )
    return display.quoteSymbols.map { symbol in
        SymbolTableEntry(
            symbol: symbol,
            inMenuBar: titleSymbols.contains(symbol),
            alertPercent: percents[symbol],
            boundaryStep: steps[symbol]
        )
    }
}

/// Inverse of `parseSymbolTable`. Blank symbols drop out, duplicates keep the
/// first row, and rules for symbols no longer in the table disappear — they
/// never fired anyway. Non-positive percent/step values serialize as no rule,
/// matching what the rule parser would reject.
public func serializeSymbolTable(
    _ entries: [SymbolTableEntry]
) -> (coins: String, alertRules: String, integerAlertRules: String) {
    var seen = Set<String>()
    let rows: [SymbolTableEntry] = entries.compactMap { entry in
        let symbol = normalizeSymbol(entry.symbol)
        guard !symbol.isEmpty, seen.insert(symbol).inserted else { return nil }
        var row = entry
        row.symbol = symbol
        return row
    }

    let title = rows.filter(\.inMenuBar).map(\.symbol)
    let dropdownOnly = rows.filter { !$0.inMenuBar }.map(\.symbol)
    var coins = title.joined(separator: " ")
    if !dropdownOnly.isEmpty {
        coins += (coins.isEmpty ? "| " : " | ") + dropdownOnly.joined(separator: " ")
    }

    func rules(_ value: (SymbolTableEntry) -> Double?) -> String {
        rows.compactMap { row in
            guard let raw = value(row), let text = formatRuleValue(raw) else { return nil }
            return "\(row.symbol):\(text)"
        }.joined(separator: " ")
    }

    return (coins, rules(\.alertPercent), rules(\.boundaryStep))
}

/// Plain decimal text for a rule value — `String(_: Double)` would print a
/// tiny step as `5e-05`, which the rule regex rejects. `nil` when the value
/// is non-positive or rounds to nothing at the precision the regex carries.
/// Public because the Settings table renders its number cells with it.
public func formatRuleValue(_ value: Double) -> String? {
    guard value > 0, value.isFinite else { return nil }
    var text = String(format: "%.10f", value)
    while text.hasSuffix("0") { text.removeLast() }
    if text.hasSuffix(".") { text.removeLast() }
    guard let parsed = Double(text), parsed > 0 else { return nil }
    return text
}
