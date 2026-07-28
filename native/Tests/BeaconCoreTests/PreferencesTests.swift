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
}
