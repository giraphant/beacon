import Foundation

/// Timestamps are milliseconds since epoch, matching the TypeScript original so
/// the ported alert/format logic stays line-for-line comparable.
public typealias Millis = Double

public struct Quote: Equatable, Sendable {
    public var symbol: String
    public var price: Double
    public var source: String
    public var updatedAt: Millis
    public var stale: Bool

    public init(symbol: String, price: Double, source: String, updatedAt: Millis, stale: Bool = false) {
        self.symbol = symbol
        self.price = price
        self.source = source
        self.updatedAt = updatedAt
        self.stale = stale
    }
}

public struct AlertRule: Equatable, Sendable {
    public var symbol: String
    public var thresholdPercent: Double
    public var enabled: Bool

    public init(symbol: String, thresholdPercent: Double, enabled: Bool = true) {
        self.symbol = symbol
        self.thresholdPercent = thresholdPercent
        self.enabled = enabled
    }
}

public struct IntegerAlertRule: Equatable, Sendable {
    public var symbol: String
    public var step: Double
    public var enabled: Bool

    public init(symbol: String, step: Double, enabled: Bool = true) {
        self.symbol = symbol
        self.step = step
        self.enabled = enabled
    }
}

public struct AlertState: Equatable, Codable, Sendable {
    public var symbol: String
    public var lastBaselinePrice: Double
    public var lastTriggeredAt: Millis?
    public var lastTriggeredPrice: Double?

    public init(
        symbol: String,
        lastBaselinePrice: Double,
        lastTriggeredAt: Millis? = nil,
        lastTriggeredPrice: Double? = nil
    ) {
        self.symbol = symbol
        self.lastBaselinePrice = lastBaselinePrice
        self.lastTriggeredAt = lastTriggeredAt
        self.lastTriggeredPrice = lastTriggeredPrice
    }
}

/// Half-open on the low end: crossing bucket 65 → 68 covers boundaries 66...68.
public struct BoundaryRange: Equatable, Codable, Sendable {
    public var startBucket: Double
    public var endBucket: Double
    public var triggeredAt: Millis

    public init(startBucket: Double, endBucket: Double, triggeredAt: Millis) {
        self.startBucket = startBucket
        self.endBucket = endBucket
        self.triggeredAt = triggeredAt
    }
}

public struct IntegerAlertState: Equatable, Codable, Sendable {
    public var symbol: String
    public var lastBucket: Double
    public var lastPrice: Double
    public var lastTriggeredAt: Millis?
    public var lastTriggeredPrice: Double?
    public var lastTriggeredBoundaryRanges: [BoundaryRange]?

    public init(
        symbol: String,
        lastBucket: Double,
        lastPrice: Double,
        lastTriggeredAt: Millis? = nil,
        lastTriggeredPrice: Double? = nil,
        lastTriggeredBoundaryRanges: [BoundaryRange]? = nil
    ) {
        self.symbol = symbol
        self.lastBucket = lastBucket
        self.lastPrice = lastPrice
        self.lastTriggeredAt = lastTriggeredAt
        self.lastTriggeredPrice = lastTriggeredPrice
        self.lastTriggeredBoundaryRanges = lastTriggeredBoundaryRanges
    }
}

public struct AlertNotification: Equatable, Sendable {
    public var symbol: String
    public var title: String
    public var message: String
    public var movementPercent: Double
    public var thresholdPercent: Double
    public var crossedSteps: Int
    public var currentPrice: Double
    public var baselinePrice: Double
}

public enum AlertEvaluation: Equatable {
    case none
    case initialize(AlertState)
    case trigger(AlertNotification, AlertState)
}

public enum IntegerAlertEvaluation: Equatable {
    case none
    case initialize(IntegerAlertState)
    case update(IntegerAlertState)
    case trigger(AlertNotification, IntegerAlertState)
}

public struct QuoteFetchResult: Equatable, Sendable {
    public var quotes: [String: Quote]
    public var missingSymbols: [String]
    public var errors: [String]
    public var updatedAt: Millis

    public init(
        quotes: [String: Quote] = [:],
        missingSymbols: [String] = [],
        errors: [String] = [],
        updatedAt: Millis = 0
    ) {
        self.quotes = quotes
        self.missingSymbols = missingSymbols
        self.errors = errors
        self.updatedAt = updatedAt
    }
}
