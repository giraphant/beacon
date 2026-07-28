import Foundation

public struct QuoteError: LocalizedError, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public enum QuoteSourceKind: String, CaseIterable, Identifiable, Sendable {
    case bybit = "Bybit"
    case binance = "Binance"
    case relay = "Relay"

    public var id: String { rawValue }
}

/// Identifies which upstream a cached result came from, so switching sources in
/// Settings never leaves the old source's prices on screen.
public func quoteSourceSignature(_ source: QuoteSourceKind, relayURL: String?) -> String {
    source == .relay ? "Relay:\(relayURL?.trimmingCharacters(in: .whitespaces) ?? "")" : source.rawValue
}

// MARK: - Transport

public typealias HTTPTransport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

/// No URL cache: responses are large, always-changing tickers, so caching only
/// buys disk writes.
private let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.waitsForConnectivity = false
    // `timeoutInterval` on the request is a stall timer — it resets every time a
    // byte arrives, so a slow-drip response never trips it. Without a wall-clock
    // cap the refresh task would stay in flight indefinitely and the app would
    // quietly stop updating.
    configuration.timeoutIntervalForResource = 30
    return URLSession(configuration: configuration)
}()

public let liveTransport: HTTPTransport = { request in
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
        throw QuoteError("Request failed: \(request.url?.absoluteString ?? "")")
    }
    return (data, http)
}

private func request(_ url: URL, headers: [String: String], timeout: TimeInterval) -> URLRequest {
    var request = URLRequest(url: url, timeoutInterval: timeout)
    for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
    return request
}

/// Two attempts mirrors the original's fetch-then-curl retry budget; a single
/// blip should not cost a refresh cycle (and with it, an alert).
private func fetchData(
    _ url: URL,
    headers: [String: String] = [:],
    timeout: TimeInterval,
    attempts: Int,
    transport: HTTPTransport
) async throws -> Data {
    var lastError: Error = QuoteError("Request failed: \(url.absoluteString)")

    for attempt in 0..<max(1, attempts) {
        do {
            let (data, response) = try await transport(request(url, headers: headers, timeout: timeout))
            guard (200..<300).contains(response.statusCode) else {
                throw QuoteError("Request failed (\(response.statusCode) HTTP error): \(url.absoluteString)")
            }
            return data
        } catch {
            lastError = error
            if attempt == attempts - 1 { throw error }
        }
    }

    throw lastError
}

// MARK: - Exchanges

/// Both exchanges are queried for their *entire* ticker list on purpose: their
/// filtered endpoints reject unknown symbols with a 400, which would break a
/// watchlist mixing crypto with equities that only the relay can resolve.
private let bybitTickersURL = URL(string: "https://api.bytick.com/v5/market/tickers?category=linear")!
private let binanceTickersURL = URL(string: "https://api.binance.com/api/v3/ticker/24hr?type=MINI")!

/// One malformed row must not discard the whole ticker list.
private struct Lenient<Wrapped: Decodable>: Decodable {
    let value: Wrapped?
    init(from decoder: Decoder) throws { value = try? Wrapped(from: decoder) }
}

private struct BybitResponse: Decodable {
    struct Result: Decodable { let list: [Lenient<Ticker>]? }
    struct Ticker: Decodable {
        let symbol: String
        let lastPrice: String
        let highPrice24h: String
        let lowPrice24h: String
    }

    let retCode: Int
    let retMsg: String?
    let result: Result?
}

private struct BinanceTicker: Decodable {
    let symbol: String
    let lastPrice: String
    let highPrice: String
    let lowPrice: String
}

public func fetchBybitLinearQuotes(
    symbols: [String],
    now: Millis,
    transport: HTTPTransport = liveTransport
) async throws -> [String: Quote] {
    let data = try await fetchData(bybitTickersURL, timeout: 8, attempts: 2, transport: transport)
    guard let response = try? JSONDecoder().decode(BybitResponse.self, from: data) else {
        throw QuoteError("Bybit returned an invalid response")
    }
    guard response.retCode == 0 else {
        let message = response.retMsg.flatMap { $0.isEmpty ? nil : $0 }
        throw QuoteError(message ?? "Bybit returned retCode \(response.retCode)")
    }
    guard let list = response.result?.list else {
        throw QuoteError("Bybit returned an invalid response")
    }

    return collectQuotes(symbols: symbols, source: "Bybit linear (USDT)", updatedAt: now) { wanted in
        list.compactMap(\.value)
            .filter { wanted.contains($0.symbol) }
            .map { ($0.symbol, $0.lastPrice, $0.highPrice24h, $0.lowPrice24h) }
    }
}

public func fetchBinanceSpotQuotes(
    symbols: [String],
    now: Millis,
    transport: HTTPTransport = liveTransport
) async throws -> [String: Quote] {
    let data = try await fetchData(binanceTickersURL, timeout: 3.5, attempts: 2, transport: transport)
    guard let tickers = try? JSONDecoder().decode([Lenient<BinanceTicker>].self, from: data) else {
        throw QuoteError("Binance returned an invalid response")
    }

    return collectQuotes(symbols: symbols, source: "Binance spot (USDT)", updatedAt: now) { wanted in
        tickers.compactMap(\.value)
            .filter { wanted.contains($0.symbol) }
            .map { ($0.symbol, $0.lastPrice, $0.highPrice, $0.lowPrice) }
    }
}

/// A ticker quoting a non-positive price, high or low is treated as bad data and
/// dropped, so the symbol falls through to the next source instead of surfacing
/// a bogus number.
private func collectQuotes(
    symbols: [String],
    source: String,
    updatedAt: Millis,
    rows: (Set<String>) -> [(symbol: String, price: String, high: String, low: String)]
) -> [String: Quote] {
    let wanted = Set(symbols.map { "\($0)USDT" })
    var quotes: [String: Quote] = [:]

    for row in rows(wanted) {
        guard let price = Double(row.price), let high = Double(row.high), let low = Double(row.low),
              isPositiveFinite(price), isPositiveFinite(high), isPositiveFinite(low)
        else { continue }

        let symbol = String(row.symbol.dropLast(4))
        quotes[symbol] = Quote(symbol: symbol, price: price, source: source, updatedAt: updatedAt)
    }

    return quotes
}

// MARK: - Relay

private struct RelayResponse: Decodable {
    struct RelayQuote: Decodable {
        let price: Double
        let high24h: Double
        let low24h: Double
        let source: String
        let updatedAt: Double
        let stale: Bool
    }

    let serverTime: Double
    let quotes: [String: RelayQuote]
    let missingSymbols: [String]
}

public func fetchRelayQuotes(
    symbols: [String],
    relayURL: String?,
    relayToken: String?,
    transport: HTTPTransport = liveTransport
) async throws -> QuoteFetchResult {
    let url = try buildRelayURL(symbols: symbols, relayURL: relayURL)
    guard let token = relayToken?.trimmingCharacters(in: .whitespaces), !token.isEmpty else {
        throw QuoteError("Relay token is not configured")
    }

    let data: Data
    do {
        data = try await fetchData(
            url,
            headers: ["Authorization": "Bearer \(token)"],
            timeout: 3,
            attempts: 1,
            transport: transport
        )
    } catch let error as QuoteError {
        throw relayHTTPError(error)
    } catch let error as URLError where error.code == .timedOut {
        throw QuoteError("Relay request timed out after 3000ms")
    } catch {
        throw QuoteError("Relay request failed")
    }

    guard let response = try? JSONDecoder().decode(RelayResponse.self, from: data),
          isPositiveFinite(response.serverTime)
    else {
        throw QuoteError("Relay returned an invalid response")
    }

    var quotes: [String: Quote] = [:]
    for (symbol, raw) in response.quotes {
        guard isPositiveFinite(raw.price), isPositiveFinite(raw.high24h), isPositiveFinite(raw.low24h),
              isPositiveFinite(raw.updatedAt), !raw.source.trimmingCharacters(in: .whitespaces).isEmpty
        else {
            throw QuoteError("Relay returned an invalid response")
        }
        quotes[symbol] = Quote(
            symbol: symbol,
            price: raw.price,
            source: raw.source,
            updatedAt: raw.updatedAt,
            stale: raw.stale
        )
    }

    return QuoteFetchResult(
        quotes: quotes,
        missingSymbols: response.missingSymbols,
        errors: [],
        updatedAt: response.serverTime
    )
}

private func relayHTTPError(_ error: QuoteError) -> QuoteError {
    if error.message.contains("(401 ") { return QuoteError("Relay authentication failed (401)") }
    if error.message.contains("(429 ") { return QuoteError("Relay rate limit exceeded (429)") }
    if error.message.contains("(503 ") { return QuoteError("Relay unavailable (503)") }
    return QuoteError("Relay request failed")
}

func buildRelayURL(symbols: [String], relayURL: String?) throws -> URL {
    let raw = relayURL?.trimmingCharacters(in: .whitespaces) ?? ""
    guard !raw.isEmpty else { throw QuoteError("Relay URL is not configured") }
    guard var components = URLComponents(string: raw),
          let scheme = components.scheme,
          let host = components.host, !host.isEmpty
    else { throw QuoteError("Relay URL is invalid") }

    // The token rides in an Authorization header, so plaintext is only tolerated
    // when the relay is on this machine.
    let isLocalHTTP = scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)
    guard scheme == "https" || isLocalHTTP else { throw QuoteError("Relay URL must use HTTPS") }

    var seen = Set<String>()
    let uniqueSymbols = symbols
        .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
        .filter { !$0.isEmpty && seen.insert($0).inserted }

    components.path = "/v1/quotes"
    components.queryItems = [URLQueryItem(name: "symbols", value: uniqueSymbols.joined(separator: ","))]
    guard let url = components.url else { throw QuoteError("Relay URL is invalid") }
    return url
}

// MARK: - Source selection & fallback

public struct QuoteProvider {
    public var name: String
    public var fetchQuotes: ([String]) async throws -> [String: Quote]

    public init(name: String, fetchQuotes: @escaping ([String]) async throws -> [String: Quote]) {
        self.name = name
        self.fetchQuotes = fetchQuotes
    }
}

public func exchangeProviders(
    preferring preferred: QuoteSourceKind,
    now: Millis,
    transport: @escaping HTTPTransport = liveTransport
) -> [QuoteProvider] {
    let bybit = QuoteProvider(name: "Bybit") {
        try await fetchBybitLinearQuotes(symbols: $0, now: now, transport: transport)
    }
    let binance = QuoteProvider(name: "Binance") {
        try await fetchBinanceSpotQuotes(symbols: $0, now: now, transport: transport)
    }
    return preferred == .binance ? [binance, bybit] : [bybit, binance]
}

/// Each provider is asked only for the symbols still missing, and a provider's
/// failure is recorded rather than fatal — unless every provider failed, in
/// which case there is nothing to show and the error propagates.
public func fetchQuotes(
    symbols: [String],
    from providers: [QuoteProvider],
    updatedAt: Millis
) async throws -> QuoteFetchResult {
    var seen = Set<String>()
    let uniqueSymbols = symbols.filter { seen.insert($0).inserted }
    var quotes: [String: Quote] = [:]
    var errors: [String] = []
    var attempted = 0

    for provider in providers {
        let missing = uniqueSymbols.filter { quotes[$0] == nil }
        if missing.isEmpty { break }
        attempted += 1

        do {
            let fetched = try await provider.fetchQuotes(missing)
            for symbol in missing where quotes[symbol] == nil {
                if let quote = fetched[symbol] { quotes[symbol] = quote }
            }
        } catch {
            errors.append("\(provider.name): \(errorMessage(error))")
        }
    }

    if attempted > 0 && errors.count == attempted {
        throw QuoteError(errors.joined(separator: ", "))
    }

    return QuoteFetchResult(
        quotes: quotes,
        missingSymbols: uniqueSymbols.filter { quotes[$0] == nil },
        errors: errors,
        updatedAt: updatedAt
    )
}

public func fetchQuotes(
    symbols: [String],
    source: QuoteSourceKind,
    relayURL: String?,
    relayToken: String?,
    now: Millis,
    transport: @escaping HTTPTransport = liveTransport
) async throws -> QuoteFetchResult {
    if source == .relay {
        return try await fetchRelayQuotes(
            symbols: symbols, relayURL: relayURL, relayToken: relayToken, transport: transport
        )
    }
    return try await fetchQuotes(
        symbols: symbols,
        from: exchangeProviders(preferring: source, now: now, transport: transport),
        updatedAt: now
    )
}

func errorMessage(_ error: Error) -> String {
    (error as? QuoteError)?.message ?? error.localizedDescription
}

private func isPositiveFinite(_ value: Double) -> Bool {
    value.isFinite && value > 0
}
