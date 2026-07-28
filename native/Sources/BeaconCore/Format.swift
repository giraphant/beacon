import Foundation

private let priceDigitTiers: [(max: Double, digits: Int)] = [(1, 4), (100, 3), (1000, 2)]

/// `.halfUp` (ties away from zero) matches `Intl.NumberFormat`'s default
/// `halfExpand`; Foundation would otherwise round ties to even and drift from
/// the TypeScript output on values like 0.125.
private func formatter(currency: Bool, digits: Int, grouping: Bool = true) -> NumberFormatter {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US")
    formatter.numberStyle = currency ? .currency : .decimal
    if currency { formatter.currencyCode = "USD" }
    formatter.usesGroupingSeparator = grouping
    formatter.minimumFractionDigits = digits
    formatter.maximumFractionDigits = digits
    formatter.roundingMode = .halfUp
    return formatter
}

public func formatPrice(_ price: Double, hideCurrencySymbol: Bool = false) -> String {
    let digits = priceDigitTiers.first { abs(price) < $0.max }?.digits ?? 0
    let formatted = formatter(currency: !hideCurrencySymbol, digits: digits)
        .string(from: NSNumber(value: price))
    return formatted ?? String(price)
}

public func formatPercent(_ value: Double) -> String {
    let sign = value > 0 ? "+" : ""
    // No grouping: JS `toFixed` never inserts thousands separators.
    let magnitude = formatter(currency: false, digits: 2, grouping: false)
        .string(from: NSNumber(value: value)) ?? String(value)
    return "\(sign)\(magnitude)%"
}

public func formatAge(updatedAt: Millis, now: Millis) -> String {
    let ageSeconds = max(0, ((now - updatedAt) / 1000).rounded())
    if ageSeconds < 60 {
        return "\(Int(ageSeconds))s ago"
    }
    return "\(Int((ageSeconds / 60).rounded(.down)))m ago"
}
