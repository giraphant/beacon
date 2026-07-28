@testable import Beacon
import BeaconCore
import Foundation
import XCTest

final class QuoteDiagnosticsTests: XCTestCase {
    func testWritesVersionedSanitizedQuoteAndDisplayEvents() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let logger = QuoteDiagnosticLogger(
            directoryURL: directory,
            maxBytes: 32 * 1_024,
            sessionId: "test-session",
            appVersion: "1.0.1",
            buildNumber: "2"
        )
        let request = await logger.begin(source: .relay, symbols: ["ETH", "BTC", "ETH"], at: 9_000)
        let result = QuoteFetchResult(
            quotes: [
                "ETH": Quote(
                    symbol: "ETH",
                    price: 3_000,
                    source: "binance-futures",
                    updatedAt: 9_500,
                    stale: true
                ),
                "BTC": Quote(
                    symbol: "BTC",
                    price: 60_000,
                    source: "bybit-linear",
                    updatedAt: 9_900
                ),
            ],
            missingSymbols: ["QQQ"],
            errors: ["Relay unavailable (503)"],
            updatedAt: 9_950
        )

        await logger.succeeded(request, result: result, at: 10_000)
        await logger.displayed(request, origin: .live, result: result, at: 10_010)
        await logger.flush()

        let data = try Data(contentsOf: logger.logURL)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        let lines = text.split(separator: "\n")
        XCTAssertEqual(lines.count, 4)

        let events = try lines.map { line in
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        }
        XCTAssertEqual(events[0]["event"] as? String, "session_start")
        XCTAssertEqual(events[0]["appVersion"] as? String, "1.0.1")
        XCTAssertEqual(events[0]["buildNumber"] as? String, "2")
        XCTAssertEqual(events[1]["symbols"] as? [String], ["BTC", "ETH"])
        XCTAssertEqual(events[2]["event"] as? String, "fetch_success")
        XCTAssertEqual(events[3]["displayOrigin"] as? String, "live")

        let quotes = try XCTUnwrap(events[2]["quotes"] as? [[String: Any]])
        XCTAssertEqual(quotes.map { $0["symbol"] as? String }, ["BTC", "ETH"])
        XCTAssertEqual(quotes[0]["ageMs"] as? Double, 100)
        XCTAssertEqual(quotes[1]["stale"] as? Bool, true)
        XCTAssertFalse(text.contains("60000"))
        XCTAssertFalse(text.contains("3000"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("authorization"))
    }

    func testFailureNormalizationCannotRetainCredentialsOrURLs() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let logger = QuoteDiagnosticLogger(
            directoryURL: directory,
            sessionId: "test-session",
            appVersion: "1.0.1",
            buildNumber: "2"
        )
        let request = await logger.begin(source: .relay, symbols: ["BTC"], at: 1_000)
        let secret = "super-secret-relay-token"

        await logger.failed(
            request,
            error: QuoteError("Failed at https://relay.example.com/path?token=\(secret)"),
            at: 1_250
        )
        await logger.flush()

        let text = try String(contentsOf: logger.logURL)
        XCTAssertFalse(text.contains(secret))
        XCTAssertFalse(text.contains("relay.example.com"))
        XCTAssertTrue(text.contains(#""category":"unknown""#))
        XCTAssertTrue(text.contains(#""message":"request failed""#))
        XCTAssertEqual(
            normalizeDiagnosticError(QuoteError("Relay request timed out after 3000ms")),
            QuoteDiagnosticError(category: "timeout", message: "request timed out")
        )
    }

    func testSymbolsAndUpstreamSourcesUseStrictDiagnosticAllowlists() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let logger = QuoteDiagnosticLogger(
            directoryURL: directory,
            sessionId: "test-session",
            appVersion: "1.0.1",
            buildNumber: "2"
        )
        let secret = "super-secret-source-value"
        let request = await logger.begin(
            source: .relay,
            symbols: ["btc", "https://invalid.example", String(repeating: "A", count: 21)],
            at: 1_000
        )
        let result = QuoteFetchResult(
            quotes: [
                "BTC": Quote(
                    symbol: "BTC",
                    price: 60_000,
                    source: "Bearer \(secret) https://relay.example",
                    updatedAt: 1_100
                ),
                "ETH": Quote(
                    symbol: "ETH",
                    price: 3_000,
                    source: "binance-futures",
                    updatedAt: 1_100
                ),
            ],
            missingSymbols: ["BTC", "ETH", "https://invalid.example"],
            updatedAt: 1_150
        )

        await logger.succeeded(request, result: result, at: 1_200)
        await logger.flush()

        let text = try String(contentsOf: logger.logURL)
        XCTAssertFalse(text.contains(secret))
        XCTAssertFalse(text.contains("relay.example"))
        let lines = text.split(separator: "\n")
        let start = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(lines[1].utf8)) as? [String: Any]
        )
        let success = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(lines[2].utf8)) as? [String: Any]
        )
        XCTAssertEqual(start["symbols"] as? [String], ["BTC"])
        XCTAssertEqual(success["missingSymbols"] as? [String], ["BTC"])
        let quotes = try XCTUnwrap(success["quotes"] as? [[String: Any]])
        XCTAssertEqual(quotes.count, 1)
        XCTAssertEqual(quotes[0]["symbol"] as? String, "BTC")
        XCTAssertEqual(quotes[0]["source"] as? String, "unknown")
    }

    func testLogRotationKeepsOnlyCurrentAndPreviousBoundedFiles() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let maxBytes = 700
        let logger = QuoteDiagnosticLogger(
            directoryURL: directory,
            maxBytes: maxBytes,
            sessionId: "test-session",
            appVersion: "1.0.1",
            buildNumber: "2"
        )

        for sequence in 0..<20 {
            _ = await logger.begin(
                source: .relay,
                symbols: ["BTC", "ETH", "SOL", "NVDA", "QQQ"],
                at: Double(sequence * 1_000)
            )
        }
        await logger.flush()

        XCTAssertTrue(FileManager.default.fileExists(atPath: logger.logURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: logger.previousLogURL.path))
        XCTAssertLessThanOrEqual(try fileSize(logger.logURL), maxBytes)
        XCTAssertLessThanOrEqual(try fileSize(logger.previousLogURL), maxBytes)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).count,
            2
        )
        let current = try String(contentsOf: logger.logURL)
        let firstLine = try XCTUnwrap(current.split(separator: "\n").first)
        let firstEvent = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(firstLine.utf8)) as? [String: Any]
        )
        XCTAssertEqual(firstEvent["event"] as? String, "session_start")
        XCTAssertEqual(firstEvent["appVersion"] as? String, "1.0.1")
        XCTAssertFalse(shouldRotate(currentBytes: 0, nextBytes: 701, maxBytes: 700))
        XCTAssertTrue(shouldRotate(currentBytes: 500, nextBytes: 201, maxBytes: 700))
    }

    func testOversizedEventIsDroppedInsteadOfBreakingTheHardFileBound() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let logger = QuoteDiagnosticLogger(
            directoryURL: directory,
            maxBytes: 128,
            sessionId: "test-session",
            appVersion: "1.0.1",
            buildNumber: "2"
        )

        _ = await logger.begin(
            source: .relay,
            symbols: ["BTC", "ETH", "SOL", "NVDA", "QQQ"],
            at: 1_000
        )
        await logger.flush()

        XCTAssertFalse(FileManager.default.fileExists(atPath: logger.logURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: logger.previousLogURL.path))
    }

    func testPreexistingOversizedCurrentFileIsNotPreservedDuringRotation() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let currentURL = directory.appendingPathComponent(QuoteDiagnosticLogger.logFileName)
        try Data(repeating: 0x41, count: 800).write(to: currentURL)
        let logger = QuoteDiagnosticLogger(
            directoryURL: directory,
            maxBytes: 700,
            sessionId: "test-session",
            appVersion: "1.0.1",
            buildNumber: "2"
        )

        _ = await logger.begin(source: .relay, symbols: ["BTC"], at: 1_000)
        await logger.flush()

        XCTAssertLessThanOrEqual(try fileSize(logger.logURL), 700)
        XCTAssertFalse(FileManager.default.fileExists(atPath: logger.previousLogURL.path))
        let current = try String(contentsOf: logger.logURL)
        XCTAssertTrue(current.contains(#""event":"session_start""#))
        XCTAssertTrue(current.contains(#""event":"fetch_start""#))
    }

    func testRecreatedCurrentFileStartsWithSessionMarker() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let logger = QuoteDiagnosticLogger(
            directoryURL: directory,
            sessionId: "test-session",
            appVersion: "1.0.1",
            buildNumber: "2"
        )

        _ = await logger.begin(source: .relay, symbols: ["BTC"], at: 1_000)
        await logger.flush()
        try FileManager.default.removeItem(at: logger.logURL)
        _ = await logger.begin(source: .relay, symbols: ["ETH"], at: 2_000)
        await logger.flush()

        let current = try String(contentsOf: logger.logURL)
        let firstLine = try XCTUnwrap(current.split(separator: "\n").first)
        let firstEvent = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(firstLine.utf8)) as? [String: Any]
        )
        XCTAssertEqual(firstEvent["event"] as? String, "session_start")
        XCTAssertEqual(firstEvent["appVersion"] as? String, "1.0.1")
    }

    private func fileSize(_ url: URL) throws -> Int {
        try XCTUnwrap(url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
    }
}
