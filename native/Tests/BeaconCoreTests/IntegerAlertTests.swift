@testable import BeaconCore
import XCTest

private struct TestError: Error {}

private let rule = IntegerAlertRule(symbol: "BTC", step: 1000)

private func quote(_ price: Double, symbol: String = "BTC") -> Quote {
    Quote(symbol: symbol, price: price, source: "Test", updatedAt: 1_000)
}

private func state(_ lastBucket: Double, _ lastPrice: Double) -> IntegerAlertState {
    IntegerAlertState(symbol: "BTC", lastBucket: lastBucket, lastPrice: lastPrice)
}

private func cooled(_ startBucket: Double, _ endBucket: Double, at triggeredAt: Millis) -> BoundaryRange {
    BoundaryRange(startBucket: startBucket, endBucket: endBucket, triggeredAt: triggeredAt)
}

final class EvaluateIntegerAlertTests: XCTestCase {
    func testInitializesCurrentBucketWithoutAlerting() {
        XCTAssertEqual(
            evaluateIntegerAlert(rule: rule, quote: quote(65_820), state: nil, now: 10_000),
            .initialize(IntegerAlertState(symbol: "BTC", lastBucket: 65, lastPrice: 65_820))
        )
    }

    func testDoesNothingWithinTheSameBucket() {
        XCTAssertEqual(
            evaluateIntegerAlert(rule: rule, quote: quote(65_999), state: state(65, 65_820), now: 10_000),
            .none
        )
    }

    func testTriggersOnUpwardBoundaryCrossing() {
        let evaluation = evaluateIntegerAlert(rule: rule, quote: quote(66_120), state: state(65, 65_820), now: 10_000)
        guard case .trigger(let notification, let nextState) = evaluation else {
            return XCTFail("expected trigger")
        }
        XCTAssertEqual(nextState, IntegerAlertState(
            symbol: "BTC", lastBucket: 66, lastPrice: 66_120, lastTriggeredAt: 10_000, lastTriggeredPrice: 66_120
        ))
        XCTAssertEqual(notification.title, "BTC crossed above $66,000")
        XCTAssertEqual(notification.crossedSteps, 1)
    }

    func testTriggersOnDownwardBoundaryCrossing() {
        let evaluation = evaluateIntegerAlert(rule: rule, quote: quote(64_900), state: state(65, 65_120), now: 10_000)
        guard case .trigger(let notification, _) = evaluation else { return XCTFail("expected trigger") }
        XCTAssertEqual(notification.title, "BTC crossed below $65,000")
        XCTAssertEqual(notification.crossedSteps, 1)
    }

    func testUpdatesWithoutNotifyingWhileBoundaryIsInCooldown() {
        var previous = state(65, 65_120)
        previous.lastTriggeredBoundaryRanges = [cooled(65, 65, at: 9_500)]

        let evaluation = evaluateIntegerAlert(
            rule: rule, quote: quote(64_900), state: previous, now: 10_000, cooldownMs: 60_000
        )

        XCTAssertEqual(evaluation, .update(IntegerAlertState(
            symbol: "BTC",
            lastBucket: 64,
            lastPrice: 64_900,
            lastTriggeredBoundaryRanges: [cooled(65, 65, at: 9_500)]
        )))
    }

    func testStillNotifiesForADifferentBoundaryDuringCooldown() {
        var previous = state(65, 65_820)
        previous.lastTriggeredBoundaryRanges = [cooled(65, 65, at: 9_500)]

        let evaluation = evaluateIntegerAlert(
            rule: rule, quote: quote(66_120), state: previous, now: 10_000, cooldownMs: 60_000
        )

        guard case .trigger(let notification, _) = evaluation else { return XCTFail("expected trigger") }
        XCTAssertEqual(notification.title, "BTC crossed above $66,000")
    }

    func testNotifiesForSameBoundaryWhenCooldownIsDisabled() {
        var previous = state(65, 65_120)
        previous.lastTriggeredBoundaryRanges = [cooled(65, 65, at: 9_500)]

        let evaluation = evaluateIntegerAlert(
            rule: rule, quote: quote(64_900), state: previous, now: 10_000, cooldownMs: 0
        )

        guard case .trigger = evaluation else { return XCTFail("expected trigger") }
    }

    func testSummarizesMultipleCrossedBuckets() {
        let evaluation = evaluateIntegerAlert(
            rule: rule, quote: quote(68_200), state: state(65, 65_820), now: 10_000, cooldownMs: 60_000
        )
        guard case .trigger(let notification, let nextState) = evaluation else {
            return XCTFail("expected trigger")
        }
        XCTAssertEqual(notification.message, "$65,820 → $68,200, crossed 3 × $1,000 steps")
        XCTAssertEqual(notification.crossedSteps, 3)
        XCTAssertEqual(nextState.lastTriggeredBoundaryRanges, [cooled(66, 68, at: 10_000)])
    }

    func testCoolsDownEveryBoundaryFromAPreviousMultiStepNotification() {
        var previous = state(68, 68_200)
        previous.lastTriggeredBoundaryRanges = [cooled(66, 68, at: 10_000)]

        let evaluation = evaluateIntegerAlert(
            rule: rule, quote: quote(66_900), state: previous, now: 20_000, cooldownMs: 60_000
        )

        guard case .update = evaluation else { return XCTFail("expected update") }
    }

    func testTitlesAMixedCooledAndFreshDropWithTheFreshBoundary() {
        var previous = state(66, 66_200)
        previous.lastTriggeredBoundaryRanges = [cooled(66, 66, at: 10_000)]

        let evaluation = evaluateIntegerAlert(
            rule: rule, quote: quote(64_900), state: previous, now: 20_000, cooldownMs: 60_000
        )

        guard case .trigger(let notification, _) = evaluation else { return XCTFail("expected trigger") }
        XCTAssertEqual(notification.title, "BTC crossed below $65,000")
    }

    /// 0.30 / 0.05 is 5.999… in binary; without the epsilon this lands in bucket
    /// 5 and the boundary is missed.
    func testHandlesDecimalStepsWithoutMissingExactBoundaries() {
        let jupRule = IntegerAlertRule(symbol: "JUP", step: 0.05)
        let jupState = IntegerAlertState(symbol: "JUP", lastBucket: 5, lastPrice: 0.25)

        let evaluation = evaluateIntegerAlert(
            rule: jupRule, quote: quote(0.3, symbol: "JUP"), state: jupState, now: 10_000
        )

        guard case .trigger(let notification, _) = evaluation else { return XCTFail("expected trigger") }
        XCTAssertEqual(notification.title, "JUP crossed above $0.3000")
    }

    func testDoesNothingForInvalidQuotesAndDisabledRules() {
        XCTAssertEqual(
            evaluateIntegerAlert(rule: rule, quote: quote(.nan), state: state(65, 65_820), now: 10_000),
            .none
        )
        let disabled = IntegerAlertRule(symbol: "BTC", step: 1000, enabled: false)
        XCTAssertEqual(
            evaluateIntegerAlert(rule: disabled, quote: quote(66_120), state: state(65, 65_820), now: 10_000),
            .none
        )
    }

    func testDoesNothingForNonPositiveStep() {
        let zeroStep = IntegerAlertRule(symbol: "BTC", step: 0)
        XCTAssertEqual(
            evaluateIntegerAlert(rule: zeroStep, quote: quote(66_120), state: state(65, 65_820), now: 10_000),
            .none
        )
    }

    /// Cooldown entries older than the window must stop suppressing alerts.
    func testExpiredCooldownRangesAreDropped() {
        var previous = state(65, 65_120)
        previous.lastTriggeredBoundaryRanges = [cooled(65, 65, at: 1_000)]

        let evaluation = evaluateIntegerAlert(
            rule: rule, quote: quote(64_900), state: previous, now: 100_000, cooldownMs: 60_000
        )

        guard case .trigger(let notification, let nextState) = evaluation else {
            return XCTFail("expected trigger")
        }
        XCTAssertEqual(notification.title, "BTC crossed below $65,000")
        XCTAssertEqual(nextState.lastTriggeredBoundaryRanges, [cooled(65, 65, at: 100_000)])
    }

    /// State recorded under another symbol must not be trusted as a baseline.
    func testReinitializesWhenStoredStateBelongsToAnotherSymbol() {
        let foreign = IntegerAlertState(symbol: "ETH", lastBucket: 1, lastPrice: 1_000)
        XCTAssertEqual(
            evaluateIntegerAlert(rule: rule, quote: quote(65_820), state: foreign, now: 10_000),
            .initialize(IntegerAlertState(symbol: "BTC", lastBucket: 65, lastPrice: 65_820))
        )
    }
}

final class RunIntegerAlertsTests: XCTestCase {
    func testPersistsUpdatesWithoutCountingThemAsTriggers() async {
        let saved = Recorder<IntegerAlertState>()
        var previous = state(65, 65_120)
        previous.lastTriggeredBoundaryRanges = [cooled(65, 65, at: 9_500)]

        let result = await runIntegerAlerts(
            rules: [rule],
            quotes: ["BTC": quote(64_900)],
            now: 10_000,
            cooldownMs: 60_000,
            getState: { _, _ in previous },
            saveState: { state, _ in saved.append(state) },
            notify: { _ in }
        )

        XCTAssertEqual(result, AlertRunResult(initialized: 0, triggered: 0, skipped: 0, failed: 0))
        XCTAssertEqual(saved.values.count, 1)
        XCTAssertEqual(saved.values.first?.lastBucket, 64)
    }

    func testDoesNotSaveTriggerStateWhenNotificationFails() async {
        let saved = Recorder<IntegerAlertState>()

        let result = await runIntegerAlerts(
            rules: [rule],
            quotes: ["BTC": quote(66_120)],
            now: 10_000,
            getState: { _, _ in state(65, 65_820) },
            saveState: { state, _ in saved.append(state) },
            notify: { _ in throw TestError() }
        )

        XCTAssertEqual(result, AlertRunResult(initialized: 0, triggered: 0, skipped: 0, failed: 1))
        XCTAssertTrue(saved.values.isEmpty)
    }

    func testSkipsRulesWithoutQuotes() async {
        let result = await runIntegerAlerts(
            rules: [rule],
            quotes: [:],
            now: 10_000,
            getState: { _, _ in nil },
            saveState: { _, _ in },
            notify: { _ in }
        )

        XCTAssertEqual(result, AlertRunResult(initialized: 0, triggered: 0, skipped: 1, failed: 0))
    }
}
