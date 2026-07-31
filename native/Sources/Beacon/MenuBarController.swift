import AppKit
import BeaconCore

/// Owns the status item and turns a `MenuBarModel` into an `NSMenu`. Everything
/// it can't do itself — refreshing, dismissing, opening Settings — is injected.
///
/// Deliberately AppKit rather than SwiftUI's `MenuBarExtra`: when macOS declines
/// to place a `MenuBarExtra` — a menu bar with no room left, an item dragged off
/// — its backing `NSSceneStatusItem` responds by calling
/// `NSApplication.terminate:`, so the whole app exits a few seconds after every
/// launch with no crash and no log. An `NSStatusItem` merely goes undrawn, the
/// app keeps polling, and relaunching still reaches Settings.
@MainActor
final class MenuBarController: NSObject {
    struct Actions {
        var refresh: () -> Void
        var dismissAlerts: () -> Void
        var openSettings: () -> Void
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let actions: Actions
    private var model = MenuBarModel(title: "Beacon", isLoading: true)
    private var alerts: [RecentAlert] = []

    init(actions: Actions) {
        self.actions = actions
        super.init()
        // A stable autosave identity makes macOS remember this item's menu-bar
        // slot instead of occasionally parking it off-screen on multi-display
        // setups.
        statusItem.autosaveName = "BeaconMenuBarItem"
        // Beacon without its menu bar item is a background process the user
        // cannot see or reach, so a persisted "dragged off" state is overridden
        // rather than honoured.
        statusItem.isVisible = true
        menu.delegate = self
        statusItem.menu = menu
    }

    /// Only the button is touched here. Replacing the menu's contents on a
    /// refresh would yank the dropdown out from under a user who has it open;
    /// `menuNeedsUpdate` rebuilds it at the moment it is shown instead.
    func render(_ model: MenuBarModel, alerts: [RecentAlert]) {
        self.model = model
        self.alerts = alerts
        guard let button = statusItem.button else { return }
        button.title = model.title
        if let direction = prominentAlertDirection(in: alerts) {
            button.image = alertImage(for: direction, pointSize: 11)
            button.imagePosition = .imageLeading
        } else {
            button.image = nil
            button.imagePosition = .noImage
        }
    }

    // MARK: - Menu

    private func populate(_ menu: NSMenu) {
        menu.removeAllItems()

        for item in model.items { menu.addItem(quote(item)) }

        if !alerts.isEmpty {
            if menu.numberOfItems > 0 { menu.addItem(.separator()) }
            menu.addItem(.sectionHeader(title: "Recent Alerts"))
            for alert in alerts {
                menu.addItem(recentAlert(alert))
            }
        }

        for section in model.sections {
            if menu.numberOfItems > 0 { menu.addItem(.separator()) }
            if let title = section.title { menu.addItem(.sectionHeader(title: title)) }
            for item in section.items { menu.addItem(label(item)) }
        }

        if menu.numberOfItems > 0 { menu.addItem(.separator()) }

        menu.addItem(
            action(
                "Refresh Now",
                key: "r",
                systemImage: "arrow.clockwise",
                #selector(refresh)
            )
        )
        if !alerts.isEmpty {
            menu.addItem(
                action(
                    "Dismiss Alerts",
                    key: "",
                    systemImage: "bell.slash",
                    #selector(dismissAlerts)
                )
            )
        }
        menu.addItem(action("Settings…", key: ",", #selector(openSettings)))
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(title: "Quit Beacon", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        )
    }

    /// Status and configuration lines are deliberately secondary. Quotes use
    /// a custom two-column row instead so AppKit does not wash the primary data
    /// out with its disabled-menu-item appearance.
    private func label(_ text: String) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = InfoMenuRowView(text: text)
        item.isEnabled = false
        return item
    }

    private func quote(_ text: String) -> NSMenuItem {
        guard let columns = splitQuoteMenuLine(text) else { return label(text) }
        let item = NSMenuItem()
        item.view = QuoteMenuRowView(
            symbol: columns.symbol,
            price: columns.price,
            alertDirection: latestAlert(for: columns.symbol, in: alerts)?.direction
        )
        item.isEnabled = false
        return item
    }

    private func recentAlert(_ alert: RecentAlert) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = RecentAlertMenuRowView(
            alert: alert,
            now: Date().timeIntervalSince1970 * 1_000
        )
        item.isEnabled = false
        return item
    }

    private func action(
        _ title: String,
        key: String,
        systemImage: String? = nil,
        _ selector: Selector
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        if let systemImage {
            item.image = NSImage(
                systemSymbolName: systemImage,
                accessibilityDescription: title
            )
        }
        return item
    }

    // MARK: - Actions

    @objc private func refresh() { actions.refresh() }
    @objc private func dismissAlerts() { actions.dismissAlerts() }
    @objc private func openSettings() { actions.openSettings() }
}

struct QuoteMenuColumns: Equatable {
    var symbol: String
    var price: String
}

func splitQuoteMenuLine(_ line: String) -> QuoteMenuColumns? {
    guard let separator = line.firstIndex(of: ":") else { return nil }
    let symbol = line[..<separator].trimmingCharacters(in: .whitespaces)
    let price = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
    guard !symbol.isEmpty, !price.isEmpty else { return nil }
    return QuoteMenuColumns(symbol: symbol, price: price)
}

func prominentAlertDirection(in alerts: [RecentAlert]) -> RecentAlert.Direction? {
    latestAlert(in: alerts)?.direction
}

func latestAlert(for symbol: String? = nil, in alerts: [RecentAlert]) -> RecentAlert? {
    var latest: RecentAlert?
    for alert in alerts where symbol == nil || alert.symbol == symbol {
        if let current = latest, alert.triggeredAt <= current.triggeredAt {
            continue
        } else {
            latest = alert
        }
    }
    return latest
}

private func alertImage(
    for direction: RecentAlert.Direction,
    pointSize: CGFloat
) -> NSImage? {
    let name = direction == .up ? "arrow.up.right" : "arrow.down.right"
    let description = direction == .up ? "Price increased" : "Price decreased"
    let color: NSColor = direction == .up ? .systemGreen : .systemRed
    let size = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
    let palette = NSImage.SymbolConfiguration(paletteColors: [color])
    return NSImage(systemSymbolName: name, accessibilityDescription: description)?
        .withSymbolConfiguration(size.applying(palette))
}

private enum MenuLayout {
    static let width: CGFloat = 200
    static let horizontalInset: CGFloat = 16
    static let alertWidth: CGFloat = width
}

struct CompactAlertTitle: Equatable {
    let symbol: String
    let percentage: String?
}

func compactAlertTitle(_ alert: RecentAlert) -> CompactAlertTitle {
    let rosePrefix = alert.symbol + " rose "
    if alert.title.hasPrefix(rosePrefix) {
        let percentage = alert.title.dropFirst(rosePrefix.count)
        return CompactAlertTitle(symbol: alert.symbol, percentage: "(+\(percentage))")
    }

    let fellPrefix = alert.symbol + " fell "
    if alert.title.hasPrefix(fellPrefix) {
        let percentage = alert.title.dropFirst(fellPrefix.count)
        return CompactAlertTitle(symbol: alert.symbol, percentage: "(−\(percentage))")
    }

    let crossedPrefixes = [
        alert.symbol + " crossed above ",
        alert.symbol + " crossed below ",
    ]
    if crossedPrefixes.contains(where: alert.title.hasPrefix) {
        return CompactAlertTitle(symbol: alert.symbol, percentage: nil)
    }

    return CompactAlertTitle(symbol: alert.title, percentage: nil)
}

func compactAlertMessage(_ message: String) -> String {
    guard let separator = message.firstIndex(of: ",") else { return message }
    return String(message[..<separator]).trimmingCharacters(in: .whitespaces)
}

final class RecentAlertMenuRowView: NSView {
    static let rowSize = NSSize(width: MenuLayout.alertWidth, height: 42)

    let directionImageView = NSImageView()
    let titleLabel: NSTextField
    let percentageLabel: NSTextField
    let detailStackView: NSStackView
    let ageLabel: NSTextField
    let messageLabel: NSTextField

    init(alert: RecentAlert, now: Millis) {
        let compactTitle = compactAlertTitle(alert)
        let titleLabel = NSTextField(labelWithString: compactTitle.symbol)
        let percentageLabel = NSTextField(labelWithString: compactTitle.percentage ?? "")
        self.titleLabel = titleLabel
        self.percentageLabel = percentageLabel
        ageLabel = NSTextField(labelWithString: formatAge(updatedAt: alert.triggeredAt, now: now))
        messageLabel = NSTextField(labelWithString: compactAlertMessage(alert.message))
        detailStackView = NSStackView(views: [messageLabel, percentageLabel])
        super.init(frame: NSRect(origin: .zero, size: Self.rowSize))

        directionImageView.image = alertImage(for: alert.direction, pointSize: 9)
        directionImageView.imageScaling = .scaleProportionallyDown
        directionImageView.translatesAutoresizingMaskIntoConstraints = false
        directionImageView.setAccessibilityHidden(true)

        titleLabel.font = .menuFont(ofSize: 0)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        percentageLabel.font = .systemFont(
            ofSize: max(9, NSFont.smallSystemFontSize - 1),
            weight: .medium
        )
        percentageLabel.textColor = (
            alert.direction == .up ? NSColor.systemGreen : NSColor.systemRed
        ).withAlphaComponent(0.85)
        percentageLabel.lineBreakMode = .byTruncatingTail
        percentageLabel.translatesAutoresizingMaskIntoConstraints = false
        percentageLabel.isHidden = compactTitle.percentage == nil
        percentageLabel.setContentHuggingPriority(.required, for: .horizontal)
        percentageLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        ageLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        ageLabel.textColor = .tertiaryLabelColor
        ageLabel.alignment = .right
        ageLabel.translatesAutoresizingMaskIntoConstraints = false
        ageLabel.setContentHuggingPriority(.required, for: .horizontal)

        messageLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.lineBreakMode = .byTruncatingTail
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        detailStackView.orientation = .horizontal
        detailStackView.alignment = .firstBaseline
        detailStackView.spacing = 5
        detailStackView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(directionImageView)
        addSubview(titleLabel)
        addSubview(ageLabel)
        addSubview(detailStackView)
        NSLayoutConstraint.activate([
            directionImageView.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: MenuLayout.horizontalInset
            ),
            directionImageView.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            directionImageView.widthAnchor.constraint(equalToConstant: 11),
            directionImageView.heightAnchor.constraint(equalToConstant: 11),
            titleLabel.leadingAnchor.constraint(
                equalTo: directionImageView.trailingAnchor,
                constant: 6
            ),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: ageLabel.leadingAnchor,
                constant: -8
            ),
            ageLabel.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -MenuLayout.horizontalInset
            ),
            ageLabel.firstBaselineAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor),
            detailStackView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailStackView.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor,
                constant: -MenuLayout.horizontalInset
            ),
            detailStackView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
        ])

        toolTip = "\(alert.title)\n\(alert.message)"
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("\(alert.title), \(alert.message), \(ageLabel.stringValue)")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize { Self.rowSize }
}

final class QuoteMenuRowView: NSView {
    static let rowSize = NSSize(width: MenuLayout.width, height: 24)

    let alertImageView: NSImageView
    let symbolLabel: NSTextField
    let priceLabel: NSTextField

    init(
        symbol: String,
        price: String,
        alertDirection: RecentAlert.Direction? = nil
    ) {
        alertImageView = NSImageView()
        symbolLabel = NSTextField(labelWithString: symbol)
        priceLabel = NSTextField(labelWithString: price)
        super.init(frame: NSRect(origin: .zero, size: Self.rowSize))

        alertImageView.image = alertDirection.flatMap {
            alertImage(for: $0, pointSize: 9)
        }
        alertImageView.imageScaling = .scaleProportionallyDown
        alertImageView.isHidden = alertDirection == nil
        alertImageView.translatesAutoresizingMaskIntoConstraints = false
        alertImageView.setAccessibilityHidden(true)
        let alertWidth: CGFloat = alertDirection == nil ? 0 : 11
        let alertSpacing: CGFloat = alertDirection == nil ? 0 : 4

        symbolLabel.font = .menuFont(ofSize: 0)
        symbolLabel.textColor = .labelColor
        symbolLabel.alignment = .left
        symbolLabel.lineBreakMode = .byTruncatingTail
        symbolLabel.translatesAutoresizingMaskIntoConstraints = false

        priceLabel.font = .monospacedDigitSystemFont(
            ofSize: NSFont.systemFontSize,
            weight: .regular
        )
        priceLabel.textColor = .labelColor
        priceLabel.alignment = .right
        priceLabel.lineBreakMode = .byTruncatingHead
        priceLabel.translatesAutoresizingMaskIntoConstraints = false
        priceLabel.setContentHuggingPriority(.required, for: .horizontal)
        priceLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        // NSTextField's intrinsic width omits a few points of cell padding and
        // clips the leading currency/digits; fittingSize includes that padding.
        let priceWidth = ceil(priceLabel.fittingSize.width)

        addSubview(alertImageView)
        addSubview(symbolLabel)
        addSubview(priceLabel)
        NSLayoutConstraint.activate([
            symbolLabel.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: MenuLayout.horizontalInset
            ),
            symbolLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            alertImageView.leadingAnchor.constraint(
                equalTo: symbolLabel.trailingAnchor,
                constant: alertSpacing
            ),
            alertImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            alertImageView.widthAnchor.constraint(equalToConstant: alertWidth),
            alertImageView.heightAnchor.constraint(equalToConstant: alertWidth),
            symbolLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: alertImageView.leadingAnchor,
                constant: -alertSpacing
            ),
            alertImageView.trailingAnchor.constraint(
                lessThanOrEqualTo: priceLabel.leadingAnchor,
                constant: -8
            ),
            priceLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: priceWidth),
            priceLabel.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -MenuLayout.horizontalInset
            ),
            priceLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        let alertDescription = alertDirection.map {
            $0 == .up ? ", upward alert" : ", downward alert"
        } ?? ""
        setAccessibilityLabel("\(symbol)\(alertDescription), \(price)")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize { Self.rowSize }
}

final class InfoMenuRowView: NSView {
    static let rowSize = NSSize(width: MenuLayout.width, height: 22)

    let textLabel: NSTextField

    init(text: String) {
        textLabel = NSTextField(labelWithString: text)
        super.init(frame: NSRect(origin: .zero, size: Self.rowSize))

        textLabel.font = .menuFont(ofSize: 0)
        textLabel.textColor = .secondaryLabelColor
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(textLabel)
        NSLayoutConstraint.activate([
            textLabel.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: MenuLayout.horizontalInset
            ),
            textLabel.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -MenuLayout.horizontalInset
            ),
            textLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        toolTip = text
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(text)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize { Self.rowSize }
}

extension MenuBarController: NSMenuDelegate {
    /// Called just before the dropdown is shown, so it always reflects the most
    /// recent refresh without being rebuilt 2,880 times a day for nobody.
    func menuNeedsUpdate(_ menu: NSMenu) {
        populate(menu)
    }
}
