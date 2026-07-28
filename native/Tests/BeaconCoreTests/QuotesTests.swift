@testable import BeaconCore
import XCTest

private struct TestError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Serves canned bodies and records the URLs asked for.
private final class FakeTransport: @unchecked Sendable {
    private let bodies: [String]
    private let statusCode: Int
    private(set) var requestedURLs: [URL] = []
    private(set) var headers: [[String: String]] = []
    private var index = 0

    init(_ bodies: [String], statusCode: Int = 200) {
        self.bodies = bodies
        self.statusCode = statusCode
    }

    var transport: HTTPTransport {
        { [self] request in
            let url = request.url!
            requestedURLs.append(url)
            headers.append(request.allHTTPHeaderFields ?? [:])
            let body = bodies[min(index, bodies.count - 1)]
            index += 1
            let response = HTTPURLResponse(
                url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil
            )!
            return (Data(body.utf8), response)
        }
    }
}

/// Fails the first `failures` attempts, then serves `body`.
private final class FlakyTransport: @unchecked Sendable {
    private let failures: Int
    private let body: String
    private(set) var attempts = 0

    init(failures: Int, body: String) {
        self.failures = failures
        self.body = body
    }

    var transport: HTTPTransport {
        { [self] request in
            attempts += 1
            if attempts <= failures { throw TestError(message: "boom") }
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (Data(body.utf8), response)
        }
    }
}

private func provider(_ name: String, _ fetch: @escaping ([String]) async throws -> [String: Quote]) -> QuoteProvider {
    QuoteProvider(name: name, fetchQuotes: fetch)
}

private func quote(_ symbol: String, _ price: Double, source: String = "Test") -> Quote {
    Quote(symbol: symbol, price: price, source: source, updatedAt: 1_000)
}

final class FallbackTests: XCTestCase {
    func testAsksLaterProvidersOnlyForSymbolsStillMissing() async throws {
        let asked = Recorder<[String]>()

        let result = try await fetchQuotes(
            symbols: ["BTC", "ETH", "NVDA"],
            from: [
                provider("Bybit") { symbols in
                    asked.append(symbols)
                    return ["BTC": quote("BTC", 100)]
                },
                provider("Relay") { symbols in
                    asked.append(symbols)
                    return ["ETH": quote("ETH", 200), "NVDA": quote("NVDA", 300)]
                },
            ],
            updatedAt: 1_000
        )

        XCTAssertEqual(asked.values, [["BTC", "ETH", "NVDA"], ["ETH", "NVDA"]])
        XCTAssertEqual(Set(result.quotes.keys), ["BTC", "ETH", "NVDA"])
        XCTAssertEqual(result.missingSymbols, [])
        XCTAssertEqual(result.errors, [])
    }

    /// Nothing left to resolve means no reason to spend a second round trip.
    func testStopsOnceEverySymbolIsResolved() async throws {
        let asked = Recorder<[String]>()

        _ = try await fetchQuotes(
            symbols: ["BTC"],
            from: [
                provider("Bybit") { _ in ["BTC": quote("BTC", 100)] },
                provider("Binance") { symbols in
                    asked.append(symbols)
                    return [:]
                },
            ],
            updatedAt: 1_000
        )

        XCTAssertTrue(asked.values.isEmpty)
    }

    func testRecordsAFailingProviderAndKeepsGoing() async throws {
        let result = try await fetchQuotes(
            symbols: ["BTC", "SOL"],
            from: [
                provider("Bybit") { _ in throw QuoteError("down") },
                provider("Binance") { _ in ["BTC": quote("BTC", 100)] },
            ],
            updatedAt: 1_000
        )

        XCTAssertEqual(result.errors, ["Bybit: down"])
        XCTAssertEqual(result.missingSymbols, ["SOL"])
        XCTAssertEqual(result.quotes["BTC"], quote("BTC", 100))
    }

    func testThrowsAnAggregateWhenEveryProviderFails() async {
        do {
            _ = try await fetchQuotes(
                symbols: ["BTC"],
                from: [
                    provider("Bybit") { _ in throw QuoteError("bybit down") },
                    provider("Binance") { _ in throw QuoteError("binance down") },
                ],
                updatedAt: 1_000
            )
            XCTFail("expected a throw")
        } catch {
            XCTAssertEqual(errorMessage(error), "Bybit: bybit down, Binance: binance down")
        }
    }

    func testDeduplicatesRequestedSymbols() async throws {
        let asked = Recorder<[String]>()

        let result = try await fetchQuotes(
            symbols: ["BTC", "BTC", "ETH"],
            from: [provider("Bybit") { symbols in
                asked.append(symbols)
                return [:]
            }],
            updatedAt: 1_000
        )

        XCTAssertEqual(asked.values, [["BTC", "ETH"]])
        XCTAssertEqual(result.missingSymbols, ["BTC", "ETH"])
    }

    /// No symbols means no providers ran, so there is no failure to aggregate.
    func testDoesNotThrowWhenThereIsNothingToFetch() async throws {
        let result = try await fetchQuotes(
            symbols: [],
            from: [provider("Bybit") { _ in throw QuoteError("down") }],
            updatedAt: 1_000
        )
        XCTAssertEqual(result, QuoteFetchResult(updatedAt: 1_000))
    }

    func testOrdersExchangesByThePreferredSource() {
        XCTAssertEqual(exchangeProviders(preferring: .bybit, now: 0).map(\.name), ["Bybit", "Binance"])
        XCTAssertEqual(exchangeProviders(preferring: .binance, now: 0).map(\.name), ["Binance", "Bybit"])
    }
}

final class ExchangeParsingTests: XCTestCase {
    private let bybitBody = """
    {"retCode":0,"result":{"list":[
      {"symbol":"BTCUSDT","lastPrice":"103245.18","highPrice24h":"104000","lowPrice24h":"102000"},
      {"symbol":"ETHUSDT","lastPrice":"0","highPrice24h":"3500","lowPrice24h":"3400"},
      {"symbol":"SOLUSDT","lastPrice":"bad"},
      {"symbol":"XRPUSDT","lastPrice":"1.5","highPrice24h":"2","lowPrice24h":"1"}
    ]}}
    """

    func testParsesBybitTickersAndStripsTheUSDTSuffix() async throws {
        let transport = FakeTransport([bybitBody])
        let quotes = try await fetchBybitLinearQuotes(
            symbols: ["BTC", "ETH", "SOL", "XRP"], now: 1_000, transport: transport.transport
        )

        XCTAssertEqual(quotes["BTC"], Quote(
            symbol: "BTC", price: 103_245.18, source: "Bybit linear (USDT)", updatedAt: 1_000
        ))
        XCTAssertEqual(quotes["XRP"]?.price, 1.5)
        // Non-positive price and a row missing required fields are both dropped so
        // the symbols fall through to the next source.
        XCTAssertNil(quotes["ETH"])
        XCTAssertNil(quotes["SOL"])
    }

    func testIgnoresTickersThatWereNotRequested() async throws {
        let transport = FakeTransport([bybitBody])
        let quotes = try await fetchBybitLinearQuotes(symbols: ["BTC"], now: 1_000, transport: transport.transport)
        XCTAssertEqual(Array(quotes.keys), ["BTC"])
    }

    func testSurfacesBybitApiErrors() async {
        let transport = FakeTransport([#"{"retCode":10001,"retMsg":"params error"}"#])
        do {
            _ = try await fetchBybitLinearQuotes(symbols: ["BTC"], now: 1_000, transport: transport.transport)
            XCTFail("expected a throw")
        } catch {
            XCTAssertEqual(errorMessage(error), "params error")
        }
    }

    func testRejectsMalformedBybitPayloads() async {
        let transport = FakeTransport(["not json"])
        do {
            _ = try await fetchBybitLinearQuotes(symbols: ["BTC"], now: 1_000, transport: transport.transport)
            XCTFail("expected a throw")
        } catch {
            XCTAssertEqual(errorMessage(error), "Bybit returned an invalid response")
        }
    }

    func testParsesBinanceTickers() async throws {
        let body = """
        [{"symbol":"BTCUSDT","lastPrice":"103245.18","highPrice":"104000","lowPrice":"102000"},
         {"symbol":"BTCUSDC","lastPrice":"1","highPrice":"1","lowPrice":"1"}]
        """
        let transport = FakeTransport([body])
        let quotes = try await fetchBinanceSpotQuotes(symbols: ["BTC"], now: 1_000, transport: transport.transport)

        XCTAssertEqual(quotes, ["BTC": Quote(
            symbol: "BTC", price: 103_245.18, source: "Binance spot (USDT)", updatedAt: 1_000
        )])
    }

    func testTreatsNon2xxAsAFailure() async {
        let transport = FakeTransport([bybitBody], statusCode: 500)
        do {
            _ = try await fetchBybitLinearQuotes(symbols: ["BTC"], now: 1_000, transport: transport.transport)
            XCTFail("expected a throw")
        } catch {
            XCTAssertTrue(errorMessage(error).contains("500 HTTP error"), errorMessage(error))
        }
    }

    /// A single blip must not cost a refresh cycle, and with it an alert.
    func testRetriesTheExchangeRequestOnce() async throws {
        let transport = FlakyTransport(failures: 1, body: bybitBody)
        let quotes = try await fetchBybitLinearQuotes(symbols: ["BTC"], now: 1_000, transport: transport.transport)

        XCTAssertEqual(transport.attempts, 2)
        XCTAssertEqual(quotes["BTC"]?.price, 103_245.18)
    }

    func testGivesUpAfterTheSecondFailure() async {
        let transport = FlakyTransport(failures: 5, body: bybitBody)
        do {
            _ = try await fetchBybitLinearQuotes(symbols: ["BTC"], now: 1_000, transport: transport.transport)
            XCTFail("expected a throw")
        } catch {
            XCTAssertEqual(transport.attempts, 2)
        }
    }
}

final class RelayTests: XCTestCase {
    private let relayBody = """
    {"serverTime":1700000000000,
     "quotes":{"NVDA":{"price":421.456,"high24h":430,"low24h":410,
                       "source":"Relay","updatedAt":1699999999000,"stale":true}},
     "missingSymbols":["FOO"]}
    """

    func testBuildsTheQuotesURLWithUppercasedUniqueSymbols() throws {
        let url = try buildRelayURL(symbols: ["btc", " eth ", "BTC", "  "], relayURL: " https://relay.example.com ")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        XCTAssertEqual(components?.host, "relay.example.com")
        XCTAssertEqual(components?.path, "/v1/quotes")
        XCTAssertEqual(components?.queryItems, [URLQueryItem(name: "symbols", value: "BTC,ETH")])
    }

    /// The bearer token would otherwise travel in cleartext.
    func testRejectsPlaintextRelayURLsOffThisMachine() {
        XCTAssertThrowsError(try buildRelayURL(symbols: ["BTC"], relayURL: "http://relay.example.com")) {
            XCTAssertEqual(errorMessage($0), "Relay URL must use HTTPS")
        }
        XCTAssertNoThrow(try buildRelayURL(symbols: ["BTC"], relayURL: "http://localhost:8080"))
        XCTAssertNoThrow(try buildRelayURL(symbols: ["BTC"], relayURL: "http://127.0.0.1:8080"))
    }

    func testRejectsMissingAndUnusableRelayURLs() {
        XCTAssertThrowsError(try buildRelayURL(symbols: ["BTC"], relayURL: "  ")) {
            XCTAssertEqual(errorMessage($0), "Relay URL is not configured")
        }
        XCTAssertThrowsError(try buildRelayURL(symbols: ["BTC"], relayURL: "relay.example.com")) {
            XCTAssertEqual(errorMessage($0), "Relay URL is invalid")
        }
    }

    func testParsesRelayQuotesIncludingStaleness() async throws {
        let transport = FakeTransport([relayBody])
        let result = try await fetchRelayQuotes(
            symbols: ["NVDA", "FOO"],
            relayURL: "https://relay.example.com",
            relayToken: "secret",
            transport: transport.transport
        )

        XCTAssertEqual(result.quotes["NVDA"], Quote(
            symbol: "NVDA", price: 421.456, source: "Relay", updatedAt: 1_699_999_999_000, stale: true
        ))
        XCTAssertEqual(result.missingSymbols, ["FOO"])
        XCTAssertEqual(result.updatedAt, 1_700_000_000_000)
        XCTAssertEqual(transport.headers.first?["Authorization"], "Bearer secret")
    }

    func testRequiresAToken() async {
        do {
            _ = try await fetchRelayQuotes(
                symbols: ["NVDA"],
                relayURL: "https://relay.example.com",
                relayToken: "  ",
                transport: FakeTransport([relayBody]).transport
            )
            XCTFail("expected a throw")
        } catch {
            XCTAssertEqual(errorMessage(error), "Relay token is not configured")
        }
    }

    func testMapsHTTPStatusesToActionableMessages() async {
        for (status, message) in [
            (401, "Relay authentication failed (401)"),
            (429, "Relay rate limit exceeded (429)"),
            (503, "Relay unavailable (503)"),
            (500, "Relay request failed"),
        ] {
            let transport = FakeTransport(["{}"], statusCode: status)
            do {
                _ = try await fetchRelayQuotes(
                    symbols: ["NVDA"],
                    relayURL: "https://relay.example.com",
                    relayToken: "secret",
                    transport: transport.transport
                )
                XCTFail("expected a throw for \(status)")
            } catch {
                XCTAssertEqual(errorMessage(error), message)
            }
        }
    }

    func testRejectsRelayQuotesCarryingUnusableNumbers() async {
        let body = """
        {"serverTime":1700000000000,
         "quotes":{"NVDA":{"price":0,"high24h":430,"low24h":410,
                           "source":"Relay","updatedAt":1699999999000,"stale":false}},
         "missingSymbols":[]}
        """
        let transport = FakeTransport([body])
        do {
            _ = try await fetchRelayQuotes(
                symbols: ["NVDA"],
                relayURL: "https://relay.example.com",
                relayToken: "secret",
                transport: transport.transport
            )
            XCTFail("expected a throw")
        } catch {
            XCTAssertEqual(errorMessage(error), "Relay returned an invalid response")
        }
    }

    /// The relay is authoritative for its own symbols; no exchange fallback runs.
    func testRelaySourceSkipsTheExchanges() async throws {
        let transport = FakeTransport([relayBody])
        let result = try await fetchQuotes(
            symbols: ["NVDA"],
            source: .relay,
            relayURL: "https://relay.example.com",
            relayToken: "secret",
            now: 1_000,
            transport: transport.transport
        )

        XCTAssertEqual(transport.requestedURLs.count, 1)
        XCTAssertEqual(transport.requestedURLs.first?.host, "relay.example.com")
        XCTAssertEqual(result.quotes["NVDA"]?.price, 421.456)
    }
}

final class SourceSignatureTests: XCTestCase {
    /// Switching source or relay host must invalidate cached prices.
    func testDistinguishesSourcesAndRelayHosts() {
        XCTAssertNotEqual(
            quoteSourceSignature(.bybit, relayURL: nil),
            quoteSourceSignature(.binance, relayURL: nil)
        )
        XCTAssertNotEqual(
            quoteSourceSignature(.relay, relayURL: "https://a.example.com"),
            quoteSourceSignature(.relay, relayURL: "https://b.example.com")
        )
        XCTAssertEqual(
            quoteSourceSignature(.relay, relayURL: " https://a.example.com "),
            quoteSourceSignature(.relay, relayURL: "https://a.example.com")
        )
    }
}
