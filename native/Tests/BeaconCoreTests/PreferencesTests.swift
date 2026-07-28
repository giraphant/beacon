@testable import BeaconCore
import XCTest

final class PreferencesTests: XCTestCase {
    func testNormalizesSpaceCommaAndPipeSeparatedSymbols() {
        XCTAssertEqual(parseSymbolsText("btc, eth | NVDA  qqq"), ["BTC", "ETH", "NVDA", "QQQ"])
    }

    func testDeduplicatesSymbolsPreservingFirstOccurrence() {
        XCTAssertEqual(parseSymbolsText("BTC eth btc ETH sol"), ["BTC", "ETH", "SOL"])
    }

    func testParsesSymbolThresholdPairs() {
        let parsed = parseAlertRulesText("BTC:2 NVDA:1.5 sol:1")
        XCTAssertEqual(parsed.rules, [
            AlertRule(symbol: "BTC", thresholdPercent: 2),
            AlertRule(symbol: "NVDA", thresholdPercent: 1.5),
            AlertRule(symbol: "SOL", thresholdPercent: 1),
        ])
        XCTAssertEqual(parsed.invalidTokens, [])
    }

    func testSkipsInvalidTokensAndKeepsValidRules() {
        let parsed = parseAlertRulesText("BTC:2 nope ETH:-1 SOL:0 JUP:1.25")
        XCTAssertEqual(parsed.rules, [
            AlertRule(symbol: "BTC", thresholdPercent: 2),
            AlertRule(symbol: "JUP", thresholdPercent: 1.25),
        ])
        XCTAssertEqual(parsed.invalidTokens, ["nope", "ETH:-1", "SOL:0"])
    }

    /// A repeated symbol both replaces the earlier rule and moves to the end.
    func testLastDuplicateRuleWins() {
        let parsed = parseAlertRulesText("BTC:2 ETH:1 BTC:3")
        XCTAssertEqual(parsed.rules, [
            AlertRule(symbol: "ETH", thresholdPercent: 1),
            AlertRule(symbol: "BTC", thresholdPercent: 3),
        ])
    }

    func testRejectsNonAsciiDigitsAndMalformedColons() {
        let parsed = parseAlertRulesText("BTC::2 ETH:١ SOL:1.2.3 :5")
        XCTAssertEqual(parsed.rules, [])
        XCTAssertEqual(parsed.invalidTokens, ["BTC::2", "ETH:١", "SOL:1.2.3", ":5"])
    }

    func testSplitsTitleSymbolsBeforeThePipe() {
        let display = parseCoinDisplayText("BTC ETH | NVDA QQQ")
        XCTAssertEqual(display.titleSymbols, ["BTC", "ETH"])
        XCTAssertEqual(display.quoteSymbols, ["BTC", "ETH", "NVDA", "QQQ"])
    }

    func testUsesAllSymbolsInTitleWhenNoPipe() {
        let display = parseCoinDisplayText("btc, eth nvda")
        XCTAssertEqual(display.titleSymbols, ["BTC", "ETH", "NVDA"])
        XCTAssertEqual(display.quoteSymbols, ["BTC", "ETH", "NVDA"])
    }

    func testParsesCooldownMinutesAndDefaultsInvalidValues() {
        XCTAssertEqual(parseIntegerAlertCooldownMinutes("0"), 0)
        XCTAssertEqual(parseIntegerAlertCooldownMinutes("5.5"), 5.5)
        XCTAssertEqual(parseIntegerAlertCooldownMinutes(" 5 "), 5)
        XCTAssertEqual(parseIntegerAlertCooldownMinutes("bad"), 10)
        XCTAssertEqual(parseIntegerAlertCooldownMinutes(""), 10)
        XCTAssertEqual(parseIntegerAlertCooldownMinutes("-1"), 10)
        XCTAssertEqual(parseIntegerAlertCooldownMinutes(nil), 10)
    }

    func testParsesSymbolStepPairs() {
        let parsed = parseIntegerAlertRulesText("BTC:1000 sol:5 JUP:0.05")
        XCTAssertEqual(parsed.rules, [
            IntegerAlertRule(symbol: "BTC", step: 1000),
            IntegerAlertRule(symbol: "SOL", step: 5),
            IntegerAlertRule(symbol: "JUP", step: 0.05),
        ])
        XCTAssertEqual(parsed.invalidTokens, [])
    }

    func testSkipsInvalidIntegerRuleTokens() {
        let parsed = parseIntegerAlertRulesText("BTC:1000 nope ETH:-1 SOL:0 JUP:0.05")
        XCTAssertEqual(parsed.rules, [
            IntegerAlertRule(symbol: "BTC", step: 1000),
            IntegerAlertRule(symbol: "JUP", step: 0.05),
        ])
        XCTAssertEqual(parsed.invalidTokens, ["nope", "ETH:-1", "SOL:0"])
    }

    func testLastDuplicateIntegerRuleWins() {
        let parsed = parseIntegerAlertRulesText("BTC:1000 ETH:5 BTC:500")
        XCTAssertEqual(parsed.rules, [
            IntegerAlertRule(symbol: "ETH", step: 5),
            IntegerAlertRule(symbol: "BTC", step: 500),
        ])
    }

    // MARK: - Structured settings adapters

    func testWatchlistRowsMigrateFromAndBackToRaycastText() {
        let rows = parseWatchlistText("btc eth | NVDA QQQ")
        XCTAssertEqual(rows, [
            WatchlistEntry(symbol: "BTC", showInMenuBar: true),
            WatchlistEntry(symbol: "ETH", showInMenuBar: true),
            WatchlistEntry(symbol: "NVDA", showInMenuBar: false),
            WatchlistEntry(symbol: "QQQ", showInMenuBar: false),
        ])
        XCTAssertEqual(serializeWatchlist(rows), "BTC ETH | NVDA QQQ")
    }

    func testWatchlistSerializerNormalizesAndDeduplicatesRows() {
        XCTAssertEqual(serializeWatchlist([
            WatchlistEntry(symbol: " nvda ", showInMenuBar: false),
            WatchlistEntry(symbol: "btc", showInMenuBar: true),
            WatchlistEntry(symbol: "BTC", showInMenuBar: false),
            WatchlistEntry(symbol: ""),
        ]), "BTC | NVDA")
    }

    func testRuleSerializersKeepAlertOnlySymbolsAndPlainDecimals() {
        XCTAssertEqual(serializeAlertRules([
            AlertRule(symbol: " btc ", thresholdPercent: 1.25),
            AlertRule(symbol: "jup", thresholdPercent: 2),
        ]), "BTC:1.25 JUP:2")
        XCTAssertEqual(serializeIntegerAlertRules([
            IntegerAlertRule(symbol: "JUP", step: 0.000000000001),
        ]), "JUP:0.000000000001")
    }

    func testRuleSerializerKeepsLastDuplicate() {
        XCTAssertEqual(serializeAlertRules([
            AlertRule(symbol: "BTC", thresholdPercent: 1),
            AlertRule(symbol: "ETH", thresholdPercent: 2),
            AlertRule(symbol: "btc", thresholdPercent: 3),
        ]), "ETH:2 BTC:3")
    }

    func testSingleSymbolNormalizerRejectsMultipleOrMalformedTokens() {
        XCTAssertEqual(normalizePreferenceSymbol(" btc "), "BTC")
        XCTAssertEqual(normalizePreferenceSymbol("BTC-USDT"), "BTC-USDT")
        XCTAssertNil(normalizePreferenceSymbol("BTC ETH"))
        XCTAssertNil(normalizePreferenceSymbol("BTC:1"))
        XCTAssertNil(normalizePreferenceSymbol(""))
    }

    func testUnifiedSettingsMergeAllThreeLegacyStringsWithoutLosingAlertOnlySymbols() {
        let rows = parseSymbolSettings(
            coins: "BTC | NVDA",
            alertRules: "BTC:1 SOL:2",
            integerAlertRules: "BTC:1000 JUP:0.05"
        )
        XCTAssertEqual(rows, [
            SymbolSettingsEntry(
                symbol: "BTC", displayMode: .menuBar,
                alertPercent: 1, boundaryStep: 1000
            ),
            SymbolSettingsEntry(symbol: "NVDA", displayMode: .dropdown),
            SymbolSettingsEntry(symbol: "SOL", displayMode: .alertsOnly, alertPercent: 2),
            SymbolSettingsEntry(symbol: "JUP", displayMode: .alertsOnly, boundaryStep: 0.05),
        ])
    }

    func testUnifiedSettingsSplitBackToCompatibleStrings() {
        let strings = serializeSymbolSettings([
            SymbolSettingsEntry(
                symbol: "BTC", displayMode: .menuBar,
                alertPercent: 1, boundaryStep: 1000
            ),
            SymbolSettingsEntry(symbol: "NVDA", displayMode: .dropdown),
            SymbolSettingsEntry(symbol: "SOL", displayMode: .alertsOnly, alertPercent: 2),
            SymbolSettingsEntry(symbol: "JUP", displayMode: .alertsOnly, boundaryStep: 0.05),
        ])
        XCTAssertEqual(strings, SymbolSettingsStrings(
            coins: "BTC | NVDA",
            alertRules: "BTC:1 SOL:2",
            integerAlertRules: "BTC:1000 JUP:0.05"
        ))
    }

    func testUnifiedSettingsDuplicatesKeepOneCompleteRow() {
        let strings = serializeSymbolSettings([
            SymbolSettingsEntry(symbol: "BTC", displayMode: .menuBar, alertPercent: 1),
            SymbolSettingsEntry(symbol: "btc", displayMode: .alertsOnly, boundaryStep: 500),
        ])
        XCTAssertEqual(strings, SymbolSettingsStrings(
            coins: "BTC",
            alertRules: "BTC:1",
            integerAlertRules: ""
        ))
    }
}
