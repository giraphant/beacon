@testable import BeaconCore
import XCTest

private struct TestError: Error {}

private let rule = AlertRule(symbol: "BTC", thresholdPercent: 1)

private func quote(_ price: Double, symbol: String = "BTC") -> Quote {
    Quote(symbol: symbol, price: price, source: "Test", updatedAt: 1_000)
}

private func state(_ lastBaselinePrice: Double) -> AlertState {
    AlertState(symbol: "BTC", lastBaselinePrice: lastBaselinePrice)
}

final class EvaluateAlertTests: XCTestCase {
    func testInitializesBaselineWithoutAlerting() {
        XCTAssertEqual(
            evaluateAlert(rule: rule, quote: quote(100), state: nil, now: 10_000),
            .initialize(AlertState(symbol: "BTC", lastBaselinePrice: 100))
        )
    }

    func testDoesNothingBelowThreshold() {
        XCTAssertEqual(evaluateAlert(rule: rule, quote: quote(100.5), state: state(100), now: 10_000), .none)
    }

    func testTriggersOnUpwardMovement() throws {
        let evaluation = evaluateAlert(rule: rule, quote: quote(101), state: state(100), now: 10_000)
        guard case .trigger(let notification, let nextState) = evaluation else {
            return XCTFail("expected trigger")
        }
        XCTAssertEqual(nextState, AlertState(
            symbol: "BTC", lastBaselinePrice: 101, lastTriggeredAt: 10_000, lastTriggeredPrice: 101
        ))
        XCTAssertEqual(notification.title, "BTC rose 1.00%")
        XCTAssertEqual(notification.crossedSteps, 1)
    }

    func testTriggersOnDownwardMovement() {
        let evaluation = evaluateAlert(rule: rule, quote: quote(98), state: state(100), now: 10_000)
        guard case .trigger(let notification, _) = evaluation else { return XCTFail("expected trigger") }
        XCTAssertEqual(notification.title, "BTC fell 2.00%")
        XCTAssertEqual(notification.crossedSteps, 2)
    }

    func testSummarizesMultipleCrossedSteps() {
        let evaluation = evaluateAlert(rule: rule, quote: quote(103.2), state: state(100), now: 10_000)
        guard case .trigger(let notification, _) = evaluation else { return XCTFail("expected trigger") }
        XCTAssertEqual(notification.message, "$100.00 → $103.20, crossed 3 × 1.00% steps")
        XCTAssertEqual(notification.crossedSteps, 3)
    }

    func testIgnoresDisabledRules() {
        let disabled = AlertRule(symbol: "BTC", thresholdPercent: 1, enabled: false)
        XCTAssertEqual(evaluateAlert(rule: disabled, quote: quote(103), state: state(100), now: 10_000), .none)
    }

    func testDoesNothingWhenSymbolsDiffer() {
        let eth = quote(101, symbol: "ETH")
        XCTAssertEqual(evaluateAlert(rule: rule, quote: eth, state: state(100), now: 10_000), .none)
        XCTAssertEqual(evaluateAlert(rule: rule, quote: eth, state: nil, now: 10_000), .none)
    }

    func testDoesNothingForNonPositivePrices() {
        XCTAssertEqual(evaluateAlert(rule: rule, quote: quote(0), state: state(100), now: 10_000), .none)
        XCTAssertEqual(evaluateAlert(rule: rule, quote: quote(-5), state: state(100), now: 10_000), .none)
        XCTAssertEqual(evaluateAlert(rule: rule, quote: quote(0), state: nil, now: 10_000), .none)
    }

    func testDoesNothingForNonFinitePrices() {
        XCTAssertEqual(evaluateAlert(rule: rule, quote: quote(.nan), state: state(100), now: 10_000), .none)
        XCTAssertEqual(evaluateAlert(rule: rule, quote: quote(.infinity), state: state(100), now: 10_000), .none)
    }

    /// A corrupt baseline must re-initialize rather than divide by zero or NaN.
    func testReinitializesOnUnusableBaseline() {
        let expected = AlertEvaluation.initialize(AlertState(symbol: "BTC", lastBaselinePrice: 100))
        XCTAssertEqual(evaluateAlert(rule: rule, quote: quote(100), state: state(0), now: 10_000), expected)
        XCTAssertEqual(evaluateAlert(rule: rule, quote: quote(100), state: state(.nan), now: 10_000), expected)
    }

    func testDoesNotDivideByZeroWhenBothAreInvalid() {
        XCTAssertEqual(evaluateAlert(rule: rule, quote: quote(0), state: state(0), now: 10_000), .none)
    }

    /// A pathologically small threshold would overflow an unchecked `Int(_:)`.
    func testHugeStepCountDoesNotTrap() {
        let tiny = AlertRule(symbol: "BTC", thresholdPercent: 1e-300)
        let evaluation = evaluateAlert(rule: tiny, quote: quote(200), state: state(100), now: 10_000)
        guard case .trigger(let notification, _) = evaluation else { return XCTFail("expected trigger") }
        XCTAssertEqual(notification.crossedSteps, Int.max)
    }
}

final class RunAlertsTests: XCTestCase {
    func testCreatesBaselineStatesWithoutNotifying() async {
        let saved = Recorder<AlertState>()
        let notified = Recorder<AlertNotification>()

        let result = await runAlerts(
            rules: [AlertRule(symbol: "BTC", thresholdPercent: 1)],
            quotes: ["BTC": quote(100)],
            now: 10_000,
            getState: { _, _ in nil },
            saveState: { state, _ in saved.append(state) },
            notify: { notified.append($0) }
        )

        XCTAssertEqual(result, AlertRunResult(initialized: 1, triggered: 0, skipped: 0, failed: 0))
        XCTAssertEqual(saved.values, [AlertState(symbol: "BTC", lastBaselinePrice: 100)])
        XCTAssertTrue(notified.values.isEmpty)
    }

    func testSavesNextStateAfterNotificationSucceeds() async {
        let saved = Recorder<AlertState>()

        let result = await runAlerts(
            rules: [AlertRule(symbol: "BTC", thresholdPercent: 1)],
            quotes: ["BTC": quote(102)],
            now: 10_000,
            getState: { _, _ in AlertState(symbol: "BTC", lastBaselinePrice: 100) },
            saveState: { state, _ in saved.append(state) },
            notify: { _ in }
        )

        XCTAssertEqual(result, AlertRunResult(initialized: 0, triggered: 1, skipped: 0, failed: 0))
        XCTAssertEqual(saved.values, [AlertState(
            symbol: "BTC", lastBaselinePrice: 102, lastTriggeredAt: 10_000, lastTriggeredPrice: 102
        )])
    }

    /// State must not advance past an alert the user never saw, or it is lost.
    func testDoesNotSaveTriggerStateWhenNotificationFails() async {
        let saved = Recorder<AlertState>()

        let result = await runAlerts(
            rules: [AlertRule(symbol: "BTC", thresholdPercent: 1)],
            quotes: ["BTC": quote(102)],
            now: 10_000,
            getState: { _, _ in AlertState(symbol: "BTC", lastBaselinePrice: 100) },
            saveState: { state, _ in saved.append(state) },
            notify: { _ in throw TestError() }
        )

        XCTAssertEqual(result, AlertRunResult(initialized: 0, triggered: 0, skipped: 0, failed: 1))
        XCTAssertTrue(saved.values.isEmpty)
    }

    func testSkipsRulesWithoutQuotes() async {
        let result = await runAlerts(
            rules: [AlertRule(symbol: "BTC", thresholdPercent: 1)],
            quotes: [:],
            now: 10_000,
            getState: { _, _ in nil },
            saveState: { _, _ in },
            notify: { _ in }
        )

        XCTAssertEqual(result, AlertRunResult(initialized: 0, triggered: 0, skipped: 1, failed: 0))
    }

    func testUsesRuleIdentityWhenLoadingAndSavingState() async {
        let requested = Recorder<String>()
        let savedThresholds = Recorder<Double>()

        _ = await runAlerts(
            rules: [AlertRule(symbol: "BTC", thresholdPercent: 2)],
            quotes: ["BTC": quote(100)],
            now: 10_000,
            getState: { symbol, threshold in
                requested.append("\(symbol):\(threshold)")
                return nil
            },
            saveState: { _, threshold in savedThresholds.append(threshold) },
            notify: { _ in }
        )

        XCTAssertEqual(requested.values, ["BTC:2.0"])
        XCTAssertEqual(savedThresholds.values, [2])
    }

    func testContinuesAfterLoadAndSaveFailures() async {
        let saved = Recorder<AlertState>()

        let result = await runAlerts(
            rules: [
                AlertRule(symbol: "BTC", thresholdPercent: 1),
                AlertRule(symbol: "ETH", thresholdPercent: 1),
                AlertRule(symbol: "SOL", thresholdPercent: 1),
            ],
            quotes: [
                "BTC": quote(100, symbol: "BTC"),
                "ETH": quote(200, symbol: "ETH"),
                "SOL": quote(300, symbol: "SOL"),
            ],
            now: 10_000,
            getState: { symbol, _ in
                if symbol == "BTC" { throw TestError() }
                return nil
            },
            saveState: { state, _ in
                if state.symbol == "ETH" { throw TestError() }
                saved.append(state)
            },
            notify: { _ in }
        )

        XCTAssertEqual(result, AlertRunResult(initialized: 1, triggered: 0, skipped: 0, failed: 2))
        XCTAssertEqual(saved.values, [AlertState(symbol: "SOL", lastBaselinePrice: 300)])
    }
}

/// Collects values from the non-escaping callbacks the runners take.
final class Recorder<Value>: @unchecked Sendable {
    private(set) var values: [Value] = []
    func append(_ value: Value) { values.append(value) }
}
