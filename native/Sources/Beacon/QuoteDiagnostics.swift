import BeaconCore
import Foundation

enum QuoteDiagnosticDisplayOrigin: String, Codable, Sendable {
    case cacheAfterError = "cache_after_error"
    case errorOnly = "error_only"
    case live
}

struct QuoteDiagnosticError: Codable, Equatable, Sendable {
    var category: String
    var message: String
}

struct QuoteDiagnosticQuote: Codable, Equatable, Sendable {
    var symbol: String
    var source: String
    var updatedAt: Millis
    var ageMs: Millis
    var stale: Bool
}

struct QuoteDiagnosticEvent: Codable, Sendable {
    var schemaVersion = 1
    var sessionId: String
    var timestamp: Millis
    var event: String
    var diagnosticsVersion: Int?
    var appVersion: String?
    var buildNumber: String?
    var requestId: String?
    var source: String?
    var symbols: [String]?
    var durationMs: Millis?
    var resultUpdatedAt: Millis?
    var resultAgeMs: Millis?
    var quotes: [QuoteDiagnosticQuote]?
    var missingSymbols: [String]?
    var errors: [QuoteDiagnosticError]?
    var displayOrigin: QuoteDiagnosticDisplayOrigin?
}

struct QuoteDiagnosticRequest: Sendable {
    var id: String
    var source: QuoteSourceKind
    var symbols: Set<String>
    var startedAt: Millis
}

actor QuoteDiagnosticLogger {
    static let shared = QuoteDiagnosticLogger()
    static let maxLogBytes = 256 * 1024
    static let logFileName = "quote-diagnostics.jsonl"
    static let previousLogFileName = "quote-diagnostics.previous.jsonl"

    nonisolated let logURL: URL
    nonisolated let previousLogURL: URL

    private let sessionId: String
    private let writer: QuoteDiagnosticFileWriter
    private var requestSequence = 0
    private var pendingWrite: Task<Void, Never>?

    init(
        directoryURL: URL = QuoteDiagnosticLogger.defaultDirectoryURL(),
        maxBytes: Int = QuoteDiagnosticLogger.maxLogBytes,
        sessionId: String = UUID().uuidString,
        appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "unknown",
        buildNumber: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    ) {
        self.sessionId = sessionId
        let currentURL = directoryURL.appendingPathComponent(Self.logFileName)
        let previousURL = directoryURL.appendingPathComponent(Self.previousLogFileName)
        logURL = currentURL
        previousLogURL = previousURL
        writer = QuoteDiagnosticFileWriter(
            logURL: currentURL,
            previousLogURL: previousURL,
            maxBytes: maxBytes,
            sessionId: sessionId,
            appVersion: appVersion,
            buildNumber: buildNumber
        )
    }

    func begin(source: QuoteSourceKind, symbols: [String], at timestamp: Millis) -> QuoteDiagnosticRequest {
        requestSequence += 1
        let safeSymbols = Set(symbols.compactMap(sanitizeDiagnosticSymbol))
        let request = QuoteDiagnosticRequest(
            id: "\(sessionId):\(requestSequence)",
            source: source,
            symbols: safeSymbols,
            startedAt: timestamp
        )
        enqueue(QuoteDiagnosticEvent(
            sessionId: sessionId,
            timestamp: timestamp,
            event: "fetch_start",
            requestId: request.id,
            source: source.rawValue,
            symbols: safeSymbols.sorted()
        ))
        return request
    }

    func succeeded(_ request: QuoteDiagnosticRequest, result: QuoteFetchResult, at timestamp: Millis) {
        enqueue(QuoteDiagnosticEvent(
            sessionId: sessionId,
            timestamp: timestamp,
            event: "fetch_success",
            requestId: request.id,
            source: request.source.rawValue,
            durationMs: elapsed(from: request.startedAt, to: timestamp),
            resultUpdatedAt: result.updatedAt,
            resultAgeMs: result.updatedAt > 0 ? elapsed(from: result.updatedAt, to: timestamp) : nil,
            quotes: quoteSnapshots(result, requestedSymbols: request.symbols, at: timestamp),
            missingSymbols: safeMissingSymbols(result, requestedSymbols: request.symbols),
            errors: result.errors.map(normalizeDiagnosticError)
        ))
    }

    func failed(_ request: QuoteDiagnosticRequest, error: Error, at timestamp: Millis) {
        enqueue(QuoteDiagnosticEvent(
            sessionId: sessionId,
            timestamp: timestamp,
            event: "fetch_failure",
            requestId: request.id,
            source: request.source.rawValue,
            durationMs: elapsed(from: request.startedAt, to: timestamp),
            errors: [normalizeDiagnosticError(error)]
        ))
    }

    func displayed(
        _ request: QuoteDiagnosticRequest,
        origin: QuoteDiagnosticDisplayOrigin,
        result: QuoteFetchResult,
        at timestamp: Millis
    ) {
        enqueue(QuoteDiagnosticEvent(
            sessionId: sessionId,
            timestamp: timestamp,
            event: "display_decision",
            requestId: request.id,
            source: request.source.rawValue,
            resultUpdatedAt: result.updatedAt > 0 ? result.updatedAt : nil,
            resultAgeMs: result.updatedAt > 0 ? elapsed(from: result.updatedAt, to: timestamp) : nil,
            quotes: quoteSnapshots(result, requestedSymbols: request.symbols, at: timestamp),
            missingSymbols: safeMissingSymbols(result, requestedSymbols: request.symbols),
            errors: result.errors.map(normalizeDiagnosticError),
            displayOrigin: origin
        ))
    }

    func flush() async {
        await pendingWrite?.value
    }

    private func enqueue(_ event: QuoteDiagnosticEvent) {
        let previous = pendingWrite
        let writer = writer
        pendingWrite = Task {
            await previous?.value
            await writer.write(event)
        }
    }

    nonisolated static func defaultDirectoryURL(fileManager: FileManager = .default) -> URL {
        let library = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        return library.appendingPathComponent("Logs/Beacon", isDirectory: true)
    }
}

private actor QuoteDiagnosticFileWriter {
    private let logURL: URL
    private let previousLogURL: URL
    private let fileManager: FileManager
    private let maxBytes: Int
    private let sessionId: String
    private let appVersion: String
    private let buildNumber: String
    private var sessionMarkerWritten = false

    init(
        logURL: URL,
        previousLogURL: URL,
        maxBytes: Int,
        sessionId: String,
        appVersion: String,
        buildNumber: String
    ) {
        self.logURL = logURL
        self.previousLogURL = previousLogURL
        fileManager = FileManager()
        self.maxBytes = maxBytes
        self.sessionId = sessionId
        self.appVersion = appVersion
        self.buildNumber = buildNumber
    }

    func write(_ event: QuoteDiagnosticEvent) {
        do {
            try fileManager.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let marker = sessionMarker()
            let markerData = try encode([marker])
            let eventData = try encode([event])
            let currentBytes = fileSize(logURL)
            let needsMarker = !sessionMarkerWritten || currentBytes == 0
            let appendData = needsMarker ? markerData + eventData : eventData
            let rotate = shouldRotate(
                currentBytes: currentBytes,
                nextBytes: appendData.count,
                maxBytes: maxBytes
            )
            let output = rotate && !needsMarker ? markerData + eventData : appendData

            // One unusually large event must not violate the documented hard
            // file bound. Dropping diagnostics is safer than affecting refresh.
            guard output.count <= maxBytes else { return }

            if rotate {
                if fileManager.fileExists(atPath: previousLogURL.path) {
                    try fileManager.removeItem(at: previousLogURL)
                }
                if fileManager.fileExists(atPath: logURL.path) {
                    if currentBytes <= maxBytes {
                        try fileManager.moveItem(at: logURL, to: previousLogURL)
                    } else {
                        // Do not preserve an oversized file left by an older or
                        // externally modified diagnostic build.
                        try fileManager.removeItem(at: logURL)
                    }
                }
            }

            if !fileManager.fileExists(atPath: logURL.path) {
                _ = fileManager.createFile(atPath: logURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: logURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: output)
            sessionMarkerWritten = true
        } catch {
            // Diagnostics must never alter refresh, display, or alert behaviour.
        }
    }

    private func sessionMarker() -> QuoteDiagnosticEvent {
        QuoteDiagnosticEvent(
            sessionId: sessionId,
            timestamp: Date().timeIntervalSince1970 * 1_000,
            event: "session_start",
            diagnosticsVersion: 1,
            appVersion: appVersion,
            buildNumber: buildNumber
        )
    }

    private func encode(_ events: [QuoteDiagnosticEvent]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try events.reduce(into: Data()) { data, event in
            data.append(try encoder.encode(event))
            data.append(0x0A)
        }
    }

    private func fileSize(_ url: URL) -> Int {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.intValue ?? 0
    }

}

func normalizeDiagnosticError(_ error: Error) -> QuoteDiagnosticError {
    normalizeDiagnosticError((error as? QuoteError)?.message ?? error.localizedDescription)
}

func normalizeDiagnosticError(_ message: String) -> QuoteDiagnosticError {
    let normalized = message.lowercased()

    if normalized.contains("timed out") || normalized.contains("timeout") || normalized.contains("cancelled") {
        return QuoteDiagnosticError(category: "timeout", message: "request timed out")
    }
    if normalized.contains("authentication") || normalized.contains("unauthorized") || normalized.contains("401") {
        return QuoteDiagnosticError(category: "authentication", message: "authentication failed")
    }
    if normalized.contains("rate limit") || normalized.contains("429") {
        return QuoteDiagnosticError(category: "rate_limit", message: "rate limit exceeded")
    }
    if normalized.contains("unavailable") || normalized.contains("503") {
        return QuoteDiagnosticError(category: "unavailable", message: "service unavailable")
    }
    if normalized.contains("invalid response") || normalized.contains("invalid json") {
        return QuoteDiagnosticError(category: "invalid_response", message: "invalid response")
    }
    if normalized.contains("network") || normalized.contains("connection") || normalized.contains("socket") {
        return QuoteDiagnosticError(category: "network", message: "network request failed")
    }
    return QuoteDiagnosticError(category: "unknown", message: "request failed")
}

func shouldRotate(currentBytes: Int, nextBytes: Int, maxBytes: Int) -> Bool {
    currentBytes > 0 && currentBytes + nextBytes > maxBytes
}

private func quoteSnapshots(
    _ result: QuoteFetchResult,
    requestedSymbols: Set<String>,
    at timestamp: Millis
) -> [QuoteDiagnosticQuote] {
    result.quotes.values
        .compactMap { quote in
            guard let symbol = sanitizeDiagnosticSymbol(quote.symbol),
                  requestedSymbols.contains(symbol)
            else { return nil }
            return QuoteDiagnosticQuote(
                symbol: symbol,
                source: normalizeDiagnosticSource(quote.source),
                updatedAt: quote.updatedAt,
                ageMs: elapsed(from: quote.updatedAt, to: timestamp),
                stale: quote.stale
            )
        }
        .sorted { $0.symbol < $1.symbol }
}

private func safeMissingSymbols(
    _ result: QuoteFetchResult,
    requestedSymbols: Set<String>
) -> [String] {
    Set(result.missingSymbols.compactMap(sanitizeDiagnosticSymbol))
        .intersection(requestedSymbols)
        .sorted()
}

private func sanitizeDiagnosticSymbol(_ raw: String) -> String? {
    let symbol = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard (2...20).contains(symbol.utf8.count),
          symbol.unicodeScalars.allSatisfy({
              ($0.value >= 65 && $0.value <= 90) || ($0.value >= 48 && $0.value <= 57)
          })
    else { return nil }
    return symbol
}

private func normalizeDiagnosticSource(_ raw: String) -> String {
    switch raw {
    case "Bybit linear (USDT)", "Binance spot (USDT)",
         "bybit-linear", "binance-futures", "binance-spot":
        return raw
    default:
        return "unknown"
    }
}

private func elapsed(from start: Millis, to end: Millis) -> Millis {
    max(0, end - start)
}
