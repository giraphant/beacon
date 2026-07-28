import Foundation

public struct RecentAlert: Equatable, Codable, Sendable {
    public enum Direction: String, Codable, Sendable { case up, down }

    public var symbol: String
    public var direction: Direction
    public var title: String
    public var message: String
    public var triggeredAt: Millis

    public init(notification: AlertNotification, triggeredAt: Millis) {
        self.symbol = notification.symbol
        self.direction = notification.movementPercent > 0 ? .up : .down
        self.title = notification.title
        self.message = notification.message
        self.triggeredAt = triggeredAt
    }

    public var indicator: String { direction == .up ? "🟢" : "🔴" }
}

public struct MenuSection: Equatable {
    public var title: String?
    public var items: [String]

    public init(title: String? = nil, items: [String]) {
        self.title = title
        self.items = items
    }
}

public struct MenuBarModel: Equatable {
    public var title: String
    public var isLoading: Bool
    public var items: [String]
    public var sections: [MenuSection]

    public init(title: String, isLoading: Bool = false, items: [String] = [], sections: [MenuSection] = []) {
        self.title = title
        self.isLoading = isLoading
        self.items = items
        self.sections = sections
    }
}

public struct MenuBarModelInput {
    public var displaySymbols: [String]
    public var titleSymbols: [String]?
    public var hideTitleSymbols = false
    public var hideCurrencySymbol = false
    public var quoteResult: QuoteFetchResult?
    public var invalidRuleTokens: [String] = []
    public var invalidIntegerRuleTokens: [String] = []
    public var recentAlerts: [String: RecentAlert] = [:]
    public var isLoading = false
    public var now: Millis

    public init(
        displaySymbols: [String],
        titleSymbols: [String]? = nil,
        hideTitleSymbols: Bool = false,
        hideCurrencySymbol: Bool = false,
        quoteResult: QuoteFetchResult? = nil,
        invalidRuleTokens: [String] = [],
        invalidIntegerRuleTokens: [String] = [],
        recentAlerts: [String: RecentAlert] = [:],
        isLoading: Bool = false,
        now: Millis
    ) {
        self.displaySymbols = displaySymbols
        self.titleSymbols = titleSymbols
        self.hideTitleSymbols = hideTitleSymbols
        self.hideCurrencySymbol = hideCurrencySymbol
        self.quoteResult = quoteResult
        self.invalidRuleTokens = invalidRuleTokens
        self.invalidIntegerRuleTokens = invalidIntegerRuleTokens
        self.recentAlerts = recentAlerts
        self.isLoading = isLoading
        self.now = now
    }
}

public func buildMenuBarModel(_ input: MenuBarModelInput) -> MenuBarModel {
    let quotes = input.quoteResult?.quotes ?? [:]
    let displayQuotes = input.displaySymbols.compactMap { quotes[$0] }
    let titleSymbols = input.titleSymbols ?? input.displaySymbols
    let titleSymbolSet = Set(titleSymbols)
    let titleQuotes = titleSymbols.compactMap { quotes[$0] }
    let dropdownQuotes = displayQuotes.filter { !titleSymbolSet.contains($0.symbol) }
    let hideCurrency = input.hideCurrencySymbol

    let title = buildTitle(
        titleSymbols: titleSymbols,
        titleQuotes: titleQuotes,
        isLoading: input.isLoading,
        hideTitleSymbols: input.hideTitleSymbols,
        hideCurrencySymbol: hideCurrency
    )
    let items = dropdownQuotes.map { quote -> String in
        let prefix = input.recentAlerts[quote.symbol].map { "\($0.indicator) " } ?? ""
        return "\(prefix)\(quote.symbol): \(formatPrice(quote.price, hideCurrencySymbol: hideCurrency))"
    }

    var sections: [MenuSection] = []

    if let result = input.quoteResult {
        let staleSymbols = displayQuotes.filter(\.stale).map(\.symbol)
        let statusItems: [String?] = [
            sourceLine(for: displayQuotes),
            result.updatedAt != 0 ? "Updated: \(formatAge(updatedAt: result.updatedAt, now: input.now))" : nil,
            result.missingSymbols.isEmpty ? nil : "Not found: \(result.missingSymbols.joined(separator: ", "))",
            staleSymbols.isEmpty ? nil : "Stale: \(staleSymbols.joined(separator: ", "))",
            result.errors.isEmpty ? nil : "Refresh issues: \(result.errors.joined(separator: "; "))",
        ]
        let present = statusItems.compactMap { $0 }
        if !present.isEmpty {
            sections.append(MenuSection(title: "Status", items: present))
        }
    }

    let configurationItems: [String?] = [
        input.invalidRuleTokens.isEmpty ? nil : "Ignored rules: \(input.invalidRuleTokens.joined(separator: ", "))",
        input.invalidIntegerRuleTokens.isEmpty
            ? nil
            : "Ignored integer rules: \(input.invalidIntegerRuleTokens.joined(separator: ", "))",
    ]
    let presentConfiguration = configurationItems.compactMap { $0 }
    if !presentConfiguration.isEmpty {
        sections.append(MenuSection(title: "Configuration", items: presentConfiguration))
    }

    return MenuBarModel(
        title: title,
        isLoading: input.isLoading && titleQuotes.isEmpty,
        items: items,
        sections: sections
    )
}

private func buildTitle(
    titleSymbols: [String],
    titleQuotes: [Quote],
    isLoading: Bool,
    hideTitleSymbols: Bool,
    hideCurrencySymbol: Bool
) -> String {
    if titleSymbols.isEmpty { return "No symbols" }
    if titleQuotes.isEmpty { return isLoading ? "Loading..." : "No prices found" }
    return titleQuotes
        .map { quote in
            let price = formatPrice(quote.price, hideCurrencySymbol: hideCurrencySymbol)
            return hideTitleSymbols ? price : "\(quote.symbol) \(price)"
        }
        .joined(separator: " · ")
}

private func sourceLine(for displayQuotes: [Quote]) -> String? {
    guard !displayQuotes.isEmpty else { return nil }
    var seen = Set<String>()
    let uniqueSources = displayQuotes.map(\.source).filter { seen.insert($0).inserted }
    return "Source: \(uniqueSources.joined(separator: ", "))"
}
