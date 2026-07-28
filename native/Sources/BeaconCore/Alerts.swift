import Foundation

// MARK: - Percentage-movement alerts

public func evaluateAlert(
    rule: AlertRule,
    quote: Quote,
    state: AlertState?,
    now: Millis
) -> AlertEvaluation {
    guard rule.enabled, quote.symbol == rule.symbol, quote.price.isFinite, quote.price > 0 else {
        return .none
    }

    guard let state, state.lastBaselinePrice.isFinite, state.lastBaselinePrice > 0 else {
        return .initialize(AlertState(symbol: rule.symbol, lastBaselinePrice: quote.price))
    }

    let movementPercent = ((quote.price - state.lastBaselinePrice) / state.lastBaselinePrice) * 100
    let absoluteMovementPercent = abs(movementPercent)
    guard absoluteMovementPercent >= rule.thresholdPercent else { return .none }

    let crossedSteps = intClamped((absoluteMovementPercent / rule.thresholdPercent).rounded(.down))
    let verb = movementPercent > 0 ? "rose" : "fell"
    let notification = AlertNotification(
        symbol: rule.symbol,
        title: "\(rule.symbol) \(verb) \(unsigned(absoluteMovementPercent))",
        message: "\(formatPrice(state.lastBaselinePrice)) → \(formatPrice(quote.price)), "
            + "crossed \(crossedSteps) × \(unsigned(rule.thresholdPercent)) steps",
        movementPercent: movementPercent,
        thresholdPercent: rule.thresholdPercent,
        crossedSteps: crossedSteps,
        currentPrice: quote.price,
        baselinePrice: state.lastBaselinePrice
    )
    let nextState = AlertState(
        symbol: rule.symbol,
        lastBaselinePrice: quote.price,
        lastTriggeredAt: now,
        lastTriggeredPrice: quote.price
    )
    return .trigger(notification, nextState)
}

// MARK: - Integer-boundary alerts

public func evaluateIntegerAlert(
    rule: IntegerAlertRule,
    quote: Quote,
    state: IntegerAlertState?,
    now: Millis,
    cooldownMs: Double = 0
) -> IntegerAlertEvaluation {
    guard rule.enabled, quote.symbol == rule.symbol,
          quote.price.isFinite, quote.price > 0,
          rule.step.isFinite, rule.step > 0
    else { return .none }

    // The epsilon keeps prices that land exactly on a boundary (0.30 / 0.05)
    // from falling into the lower bucket through binary rounding error.
    let currentBucket = (quote.price / rule.step + 1e-9).rounded(.down)

    guard let state, state.symbol == rule.symbol, state.lastBucket.isFinite else {
        return .initialize(
            IntegerAlertState(symbol: rule.symbol, lastBucket: currentBucket, lastPrice: quote.price)
        )
    }

    let bucketDelta = currentBucket - state.lastBucket
    guard bucketDelta != 0 else { return .none }

    let crossedRange = boundaryRange(from: state.lastBucket, to: currentBucket)
    let cooledRanges = cooldownMs > 0
        ? (state.lastTriggeredBoundaryRanges ?? []).filter { now - $0.triggeredAt < cooldownMs }
        : []
    let freshRanges = subtract(cooledRanges, from: crossedRange)

    guard let freshRange = freshRanges.first else {
        var nextState = state
        nextState.lastBucket = currentBucket
        nextState.lastPrice = quote.price
        return .update(nextState)
    }

    let crossedSteps = intClamped(abs(bucketDelta))
    let direction = bucketDelta > 0 ? "above" : "below"
    // Name the boundary the user actually cares about — the newest one crossed —
    // unless cooldown already covered it, then the highest still-fresh boundary.
    let preferredBoundary = bucketDelta > 0 ? currentBucket : state.lastBucket
    let boundaryBucket = contains(freshRange, preferredBoundary)
        ? preferredBoundary
        : freshRanges.map(\.endBucket).max() ?? preferredBoundary
    let boundary = boundaryBucket * rule.step

    let notification = AlertNotification(
        symbol: rule.symbol,
        title: "\(rule.symbol) crossed \(direction) \(formatPrice(boundary))",
        message: "\(formatPrice(state.lastPrice)) → \(formatPrice(quote.price)), "
            + "crossed \(crossedSteps) × \(formatPrice(rule.step)) \(crossedSteps == 1 ? "step" : "steps")",
        movementPercent: bucketDelta,
        thresholdPercent: rule.step,
        crossedSteps: crossedSteps,
        currentPrice: quote.price,
        baselinePrice: state.lastPrice
    )
    var triggeredRange = crossedRange
    triggeredRange.triggeredAt = now
    let nextState = IntegerAlertState(
        symbol: rule.symbol,
        lastBucket: currentBucket,
        lastPrice: quote.price,
        lastTriggeredAt: now,
        lastTriggeredPrice: quote.price,
        lastTriggeredBoundaryRanges: cooldownMs > 0 ? cooledRanges + [triggeredRange] : nil
    )
    return .trigger(notification, nextState)
}

private func boundaryRange(from previousBucket: Double, to currentBucket: Double) -> BoundaryRange {
    BoundaryRange(
        startBucket: min(previousBucket, currentBucket) + 1,
        endBucket: max(previousBucket, currentBucket),
        triggeredAt: 0
    )
}

private func subtract(_ cooledRanges: [BoundaryRange], from range: BoundaryRange) -> [BoundaryRange] {
    var freshRanges = [range]
    for cooled in cooledRanges {
        freshRanges = freshRanges.flatMap { subtract(cooled, from: $0) }
    }
    return freshRanges
}

private func subtract(_ cooled: BoundaryRange, from range: BoundaryRange) -> [BoundaryRange] {
    guard cooled.endBucket >= range.startBucket, cooled.startBucket <= range.endBucket else {
        return [range]
    }
    var remainder: [BoundaryRange] = []
    if range.startBucket < cooled.startBucket {
        remainder.append(BoundaryRange(
            startBucket: range.startBucket,
            endBucket: cooled.startBucket - 1,
            triggeredAt: range.triggeredAt
        ))
    }
    if range.endBucket > cooled.endBucket {
        remainder.append(BoundaryRange(
            startBucket: cooled.endBucket + 1,
            endBucket: range.endBucket,
            triggeredAt: range.triggeredAt
        ))
    }
    return remainder
}

private func contains(_ range: BoundaryRange, _ bucket: Double) -> Bool {
    range.startBucket <= bucket && bucket <= range.endBucket
}

// MARK: - Runners

public struct AlertRunResult: Equatable {
    public var initialized = 0
    public var triggered = 0
    public var skipped = 0
    public var failed = 0
}

/// A failed `notify` deliberately skips the state save so the alert is retried
/// on the next refresh instead of being silently swallowed.
public func runAlerts(
    rules: [AlertRule],
    quotes: [String: Quote],
    now: Millis,
    getState: (String, Double) async throws -> AlertState?,
    saveState: (AlertState, Double) async throws -> Void,
    notify: (AlertNotification) async throws -> Void
) async -> AlertRunResult {
    var result = AlertRunResult()

    for rule in rules {
        guard let quote = quotes[rule.symbol] else {
            result.skipped += 1
            continue
        }

        let state: AlertState?
        do {
            state = try await getState(rule.symbol, rule.thresholdPercent)
        } catch {
            result.failed += 1
            continue
        }

        switch evaluateAlert(rule: rule, quote: quote, state: state, now: now) {
        case .none:
            continue
        case .initialize(let nextState):
            do {
                try await saveState(nextState, rule.thresholdPercent)
                result.initialized += 1
            } catch {
                result.failed += 1
            }
        case .trigger(let notification, let nextState):
            do {
                try await notify(notification)
                try await saveState(nextState, rule.thresholdPercent)
                result.triggered += 1
            } catch {
                result.failed += 1
            }
        }
    }

    return result
}

public func runIntegerAlerts(
    rules: [IntegerAlertRule],
    quotes: [String: Quote],
    now: Millis,
    cooldownMs: Double = 0,
    getState: (String, Double) async throws -> IntegerAlertState?,
    saveState: (IntegerAlertState, Double) async throws -> Void,
    notify: (AlertNotification) async throws -> Void
) async -> AlertRunResult {
    var result = AlertRunResult()

    for rule in rules {
        guard let quote = quotes[rule.symbol] else {
            result.skipped += 1
            continue
        }

        let state: IntegerAlertState?
        do {
            state = try await getState(rule.symbol, rule.step)
        } catch {
            result.failed += 1
            continue
        }

        let evaluation = evaluateIntegerAlert(
            rule: rule, quote: quote, state: state, now: now, cooldownMs: cooldownMs
        )

        switch evaluation {
        case .none:
            continue
        case .update(let nextState):
            do {
                try await saveState(nextState, rule.step)
            } catch {
                result.failed += 1
            }
        case .initialize(let nextState):
            do {
                try await saveState(nextState, rule.step)
                result.initialized += 1
            } catch {
                result.failed += 1
            }
        case .trigger(let notification, let nextState):
            do {
                try await notify(notification)
                try await saveState(nextState, rule.step)
                result.triggered += 1
            } catch {
                result.failed += 1
            }
        }
    }

    return result
}

// MARK: - Helpers

/// `formatPercent` adds a leading `+`; alert copy already carries the direction
/// in its verb, so the sign is dropped.
private func unsigned(_ percent: Double) -> String {
    formatPercent(percent).replacingOccurrences(of: "+", with: "")
}

/// Step counts come from user-supplied thresholds; a pathologically small one
/// would overflow a plain `Int(_:)` conversion and trap. Comparing before
/// converting is the only safe order — `Double(Int.max)` rounds *up* to 2^63, so
/// clamping to it still traps. A NaN fails both comparisons and lands on `.max`.
private func intClamped(_ value: Double) -> Int {
    guard value < Double(Int.max) else { return Int.max }
    guard value > Double(Int.min) else { return Int.min }
    return Int(value)
}
