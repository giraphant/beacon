@testable import BeaconCore
import XCTest

private func quote(
    _ symbol: String,
    _ price: Double,
    source: String = "Bybit linear (USDT)",
    updatedAt: Millis = 1_000,
    stale: Bool = false
) -> Quote {
    Quote(symbol: symbol, price: price, source: source, updatedAt: updatedAt, stale: stale)
}

private func result(
    _ quotes: [Quote],
    missingSymbols: [String] = [],
    errors: [String] = [],
    updatedAt: Millis = 1_000
) -> QuoteFetchResult {
    QuoteFetchResult(
        quotes: Dictionary(uniqueKeysWithValues: quotes.map { ($0.symbol, $0) }),
        missingSymbols: missingSymbols,
        errors: errors,
        updatedAt: updatedAt
    )
}

final class MenuModelTests: XCTestCase {
    func testShowsLoadingBeforeTheFirstResult() {
        let model = buildMenuBarModel(MenuBarModelInput(displaySymbols: ["BTC"], isLoading: true, now: 1_000))
        XCTAssertEqual(model.title, "Loading...")
        XCTAssertTrue(model.isLoading)
        XCTAssertEqual(model.sections, [])
    }

    func testShowsNoSymbolsWhenNothingIsConfigured() {
        let model = buildMenuBarModel(MenuBarModelInput(displaySymbols: [], isLoading: true, now: 1_000))
        XCTAssertEqual(model.title, "No symbols")
    }

    func testShowsNoPricesFoundWhenTheFetchReturnedNothing() {
        let model = buildMenuBarModel(MenuBarModelInput(
            displaySymbols: ["BTC"],
            quoteResult: result([], missingSymbols: ["BTC"]),
            now: 12_000
        ))
        XCTAssertEqual(model.title, "No prices found")
        XCTAssertFalse(model.isLoading)
    }

    /// A refresh in flight must not blank out prices already on screen.
    func testKeepsShowingPricesWhileRefreshing() {
        let model = buildMenuBarModel(MenuBarModelInput(
            displaySymbols: ["BTC"],
            quoteResult: result([quote("BTC", 103_245.18)]),
            isLoading: true,
            now: 12_000
        ))
        XCTAssertEqual(model.title, "BTC $103,245")
        XCTAssertFalse(model.isLoading)
    }

    func testJoinsMultipleTitleSymbols() {
        let model = buildMenuBarModel(MenuBarModelInput(
            displaySymbols: ["BTC", "ETH"],
            quoteResult: result([quote("BTC", 103_245.18), quote("ETH", 3_421.5)]),
            now: 12_000
        ))
        XCTAssertEqual(model.title, "BTC $103,245 · ETH $3,422")
        XCTAssertEqual(model.items, [])
    }

    func testMovesNonTitleSymbolsIntoTheDropdown() {
        let model = buildMenuBarModel(MenuBarModelInput(
            displaySymbols: ["BTC", "ETH", "NVDA"],
            titleSymbols: ["BTC"],
            quoteResult: result([
                quote("BTC", 103_245.18),
                quote("ETH", 3_421.5),
                quote("NVDA", 421.456, source: "Relay"),
            ]),
            now: 12_000
        ))
        XCTAssertEqual(model.title, "BTC $103,245")
        XCTAssertEqual(model.items, ["ETH: $3,422", "NVDA: $421.46"])
    }

    func testCanHideSymbolNamesAndCurrencySymbols() {
        let model = buildMenuBarModel(MenuBarModelInput(
            displaySymbols: ["BTC", "ETH"],
            titleSymbols: ["BTC"],
            hideTitleSymbols: true,
            hideCurrencySymbol: true,
            quoteResult: result([quote("BTC", 103_245.18), quote("ETH", 3_421.5)]),
            now: 12_000
        ))
        XCTAssertEqual(model.title, "103,245")
        XCTAssertEqual(model.items, ["ETH: 3,422"])
    }

    func testKeepsAlertPresentationOutOfQuoteText() {
        let model = buildMenuBarModel(MenuBarModelInput(
            displaySymbols: ["BTC", "ETH"],
            titleSymbols: ["BTC"],
            quoteResult: result([quote("BTC", 103_245.18), quote("ETH", 3_421.5)]),
            now: 12_000
        ))
        XCTAssertEqual(model.items, ["ETH: $3,422"])
    }

    func testReportsSourceAndAgeInTheStatusSection() {
        let model = buildMenuBarModel(MenuBarModelInput(
            displaySymbols: ["BTC"],
            quoteResult: result([quote("BTC", 103_245.18)], updatedAt: 1_000),
            now: 12_000
        ))
        XCTAssertEqual(model.sections, [MenuSection(
            title: "Status",
            items: ["Source: Bybit linear (USDT)", "Updated: 11s ago"]
        )])
    }

    func testReportsTheOldestDisplayedQuoteAgeInsteadOfRelayResponseTime() {
        let model = buildMenuBarModel(MenuBarModelInput(
            displaySymbols: ["BTC", "QQQ"],
            quoteResult: result(
                [
                    quote("BTC", 103_245.18, updatedAt: 11_700),
                    quote("QQQ", 567.89, updatedAt: 8_000),
                ],
                updatedAt: 11_950
            ),
            now: 12_000
        ))

        XCTAssertEqual(model.sections.first?.items, [
            "Source: Bybit linear (USDT)",
            "Updated: 4s ago",
        ])
    }

    func testDeduplicatesSourcesInOrderOfAppearance() {
        let model = buildMenuBarModel(MenuBarModelInput(
            displaySymbols: ["BTC", "ETH", "NVDA"],
            quoteResult: result([
                quote("BTC", 1),
                quote("ETH", 2),
                quote("NVDA", 3, source: "Relay"),
            ]),
            now: 1_000
        ))
        XCTAssertEqual(model.sections.first?.items.first, "Source: Bybit linear (USDT), Relay")
    }

    func testReportsMissingStaleAndFailedSymbols() {
        let model = buildMenuBarModel(MenuBarModelInput(
            displaySymbols: ["BTC", "ETH"],
            quoteResult: result(
                [quote("BTC", 103_245.18), quote("ETH", 3_421.5, stale: true)],
                missingSymbols: ["SOL"],
                errors: ["Bybit: down"]
            ),
            now: 12_000
        ))
        XCTAssertEqual(model.sections.first?.items, [
            "Source: Bybit linear (USDT)",
            "Updated: 11s ago",
            "Not found: SOL",
            "Stale: ETH",
            "Refresh issues: Bybit: down",
        ])
    }

    func testListsIgnoredRuleTokensInAConfigurationSection() {
        let model = buildMenuBarModel(MenuBarModelInput(
            displaySymbols: ["BTC"],
            quoteResult: result([quote("BTC", 103_245.18)]),
            invalidRuleTokens: ["nope"],
            invalidIntegerRuleTokens: ["ETH:-1"],
            now: 12_000
        ))
        XCTAssertEqual(model.sections.last, MenuSection(
            title: "Configuration",
            items: ["Ignored rules: nope", "Ignored integer rules: ETH:-1"]
        ))
    }

    /// A result that never completed has no age to report.
    func testOmitsTheUpdatedLineWhenNoFetchHasSucceeded() {
        let model = buildMenuBarModel(MenuBarModelInput(
            displaySymbols: ["BTC"],
            quoteResult: result([], errors: ["Bybit: down"], updatedAt: 0),
            now: 12_000
        ))
        XCTAssertEqual(model.sections, [MenuSection(title: "Status", items: ["Refresh issues: Bybit: down"])])
    }
}
