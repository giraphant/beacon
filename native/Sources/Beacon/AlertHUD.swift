import AppKit
import BeaconCore
import Foundation

struct AlertHUDPresentation: Equatable {
    var symbol: String
    var price: String
    var title: String
    var direction: RecentAlert.Direction

    init(
        symbol: String,
        price: String,
        title: String,
        direction: RecentAlert.Direction
    ) {
        self.symbol = symbol
        self.price = price
        self.title = title
        self.direction = direction
    }

    init(notification: AlertNotification) {
        var detail = notification.title
        let redundantPrefix = "\(notification.symbol) "
        if detail.hasPrefix(redundantPrefix) {
            detail.removeFirst(redundantPrefix.count)
            if let first = detail.first {
                detail.replaceSubrange(
                    detail.startIndex...detail.startIndex,
                    with: String(first).uppercased()
                )
            }
        }
        self.init(
            symbol: notification.symbol,
            price: formatPrice(notification.currentPrice),
            title: detail,
            direction: notification.movementPercent > 0 ? .up : .down
        )
    }

    static let preview = AlertHUDPresentation(
        symbol: "QQQ",
        price: "$670.21",
        title: "Crossed above $670",
        direction: .up
    )
}

@MainActor
enum AlertHUDMetrics {
    static let cardHeight: CGFloat = 64
    static let minimumCardWidth: CGFloat = 200
    static let maximumCardWidth: CGFloat = 356
    static let cornerRadius: CGFloat = 21
    static let shadowInsetX: CGFloat = 28
    static let shadowInsetY: CGFloat = 25

    static let horizontalPadding: CGFloat = 15
    static let trailingPadding: CGFloat = 18
    static let badgeSize: CGFloat = 30
    static let badgeTextSpacing: CGFloat = 11
    static let primaryTextSpacing: CGFloat = 8

    static let symbolFont = NSFont.systemFont(ofSize: 13.5, weight: .semibold)
    static let priceFont = NSFont.monospacedDigitSystemFont(ofSize: 16.5, weight: .semibold)
    static let detailFont = NSFont.systemFont(ofSize: 11.5, weight: .medium)

    static func textBlockWidth(for presentation: AlertHUDPresentation) -> CGFloat {
        let symbolWidth = textWidth(presentation.symbol, font: symbolFont)
        let priceWidth = textWidth(presentation.price, font: priceFont)
        let detailWidth = textWidth(presentation.title, font: detailFont)
        let primaryWidth = symbolWidth + primaryTextSpacing + priceWidth
        let maximumTextWidth = maximumCardWidth
            - horizontalPadding
            - badgeSize
            - badgeTextSpacing
            - trailingPadding
        return min(maximumTextWidth, ceil(max(primaryWidth, detailWidth)))
    }

    static func contentGroupWidth(for presentation: AlertHUDPresentation) -> CGFloat {
        badgeSize + badgeTextSpacing + textBlockWidth(for: presentation)
    }

    static func cardWidth(for presentation: AlertHUDPresentation) -> CGFloat {
        let desired = horizontalPadding
            + contentGroupWidth(for: presentation)
            + trailingPadding
        return min(maximumCardWidth, max(minimumCardWidth, ceil(desired)))
    }

    static func contentSize(for presentation: AlertHUDPresentation) -> NSSize {
        NSSize(
            width: cardWidth(for: presentation) + shadowInsetX * 2,
            height: cardHeight + shadowInsetY * 2
        )
    }

    /// Keeps the visible card in the lower fifth of the selected display,
    /// clear of the Dock without hugging the exact bottom edge.
    static func visibleCardBottomInset(in visibleFrame: NSRect) -> CGFloat {
        min(168, max(112, visibleFrame.height * 0.15))
    }

    static func panelOrigin(contentSize: NSSize, in visibleFrame: NSRect) -> NSPoint {
        let cardBottom = visibleFrame.minY + visibleCardBottomInset(in: visibleFrame)
        return NSPoint(
            x: visibleFrame.midX - contentSize.width / 2,
            y: cardBottom - shadowInsetY
        )
    }

    private static func textWidth(_ text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
}

/// A permission-free, non-activating overlay. Alerts are queued so a movement
/// and price-level rule firing on the same refresh are both shown.
@MainActor
final class AlertHUDController {
    static let shared = AlertHUDController()

    private struct PendingPresentation {
        var presentation: AlertHUDPresentation
        var displayDuration: TimeInterval
    }

    private var pending: [PendingPresentation] = []
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    func show(
        _ notification: AlertNotification,
        displayDuration: TimeInterval = HUDDuration.defaultSeconds
    ) {
        show(
            AlertHUDPresentation(notification: notification),
            displayDuration: displayDuration
        )
    }

    func show(
        _ presentation: AlertHUDPresentation,
        displayDuration: TimeInterval = HUDDuration.defaultSeconds
    ) {
        if pending.count < 10 {
            pending.append(
                PendingPresentation(
                    presentation: presentation,
                    displayDuration: HUDDuration.normalized(displayDuration)
                )
            )
        }
        presentNextIfNeeded()
    }

    private func presentNextIfNeeded() {
        guard panel == nil, !pending.isEmpty else { return }
        let request = pending.removeFirst()
        let contentView = AlertHUDContentView(presentation: request.presentation)
        let size = contentView.intrinsicContentSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = contentView
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle,
        ]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false

        let screen = AlertHUDScreenResolver.preferredScreen()
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }
        let finalOrigin = AlertHUDMetrics.panelOrigin(
            contentSize: size,
            in: screen.visibleFrame
        )
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let startOrigin = reduceMotion
            ? finalOrigin
            : NSPoint(x: finalOrigin.x, y: finalOrigin.y - 8)
        panel.setFrame(NSRect(origin: startOrigin, size: size), display: true)

        self.panel = panel
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.10 : 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            if !reduceMotion {
                panel.animator().setFrameOrigin(finalOrigin)
            }
        }

        dismissTask?.cancel()
        dismissTask = Task { [weak self, weak panel] in
            try? await Task.sleep(for: .seconds(request.displayDuration))
            guard !Task.isCancelled, let self, let panel else { return }
            self.dismiss(panel)
        }
    }

    private func dismiss(_ panel: NSPanel) {
        dismissTask = nil
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let currentOrigin = panel.frame.origin
        let endOrigin = NSPoint(x: currentOrigin.x, y: currentOrigin.y - 5)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = reduceMotion ? 0.10 : 0.17
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            if !reduceMotion {
                panel.animator().setFrameOrigin(endOrigin)
            }
        }, completionHandler: { [weak self, weak panel] in
            MainActor.assumeIsolated {
                panel?.orderOut(nil)
                guard let self, self.panel === panel else { return }
                self.panel = nil
                self.presentNextIfNeeded()
            }
        })
    }
}

final class AlertHUDContentView: NSView {
    let directionImageView = NSImageView()
    let directionBadgeView = NSView()
    let symbolLabel: NSTextField
    let priceLabel: NSTextField
    let titleLabel: NSTextField
    let contentGroupView = NSView()

    private let presentation: AlertHUDPresentation
    private let resolvedContentSize: NSSize
    private let cardView = AlertHUDCardHostView()
    private let textBlockView = NSView()

    init(presentation: AlertHUDPresentation) {
        self.presentation = presentation
        resolvedContentSize = AlertHUDMetrics.contentSize(for: presentation)
        symbolLabel = NSTextField(labelWithString: presentation.symbol)
        priceLabel = NSTextField(labelWithString: presentation.price)
        titleLabel = NSTextField(labelWithString: presentation.title)
        super.init(frame: NSRect(origin: .zero, size: resolvedContentSize))

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        let accentColor: NSColor = presentation.direction == .up ? .systemGreen : .systemRed
        let cardContent = AlertHUDCardContentView(accentColor: accentColor)
        let backdrop = AlertHUDBackdropView(
            content: cardContent,
            cornerRadius: AlertHUDMetrics.cornerRadius,
            tintColor: accentColor.withAlphaComponent(0.035)
        )

        cardView.cornerRadius = AlertHUDMetrics.cornerRadius
        cardView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cardView)

        backdrop.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(backdrop)

        let edgeView = AlertHUDEdgeView(
            cornerRadius: AlertHUDMetrics.cornerRadius,
            accentColor: accentColor
        )
        edgeView.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(edgeView)

        configureDirectionBadge(accentColor: accentColor)
        configureLabels()
        configureContentGroup(in: cardContent)

        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: AlertHUDMetrics.shadowInsetX
            ),
            cardView.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -AlertHUDMetrics.shadowInsetX
            ),
            cardView.topAnchor.constraint(
                equalTo: topAnchor,
                constant: AlertHUDMetrics.shadowInsetY
            ),
            cardView.bottomAnchor.constraint(
                equalTo: bottomAnchor,
                constant: -AlertHUDMetrics.shadowInsetY
            ),

            backdrop.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: cardView.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),

            edgeView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            edgeView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            edgeView.topAnchor.constraint(equalTo: cardView.topAnchor),
            edgeView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(
            "\(presentation.symbol), \(presentation.price), \(presentation.title)"
        )
    }

    private func configureDirectionBadge(accentColor: NSColor) {
        directionBadgeView.wantsLayer = true
        directionBadgeView.layer?.cornerRadius = AlertHUDMetrics.badgeSize / 2
        directionBadgeView.layer?.cornerCurve = .continuous
        directionBadgeView.layer?.backgroundColor = accentColor.withAlphaComponent(0.10).cgColor
        directionBadgeView.layer?.borderWidth = 0.5
        directionBadgeView.layer?.borderColor = accentColor.withAlphaComponent(0.18).cgColor
        directionBadgeView.translatesAutoresizingMaskIntoConstraints = false

        let directionName = presentation.direction == .up ? "arrow.up.right" : "arrow.down.right"
        directionImageView.image = NSImage(
            systemSymbolName: directionName,
            accessibilityDescription: presentation.direction == .up ? "Up" : "Down"
        )?.withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        directionImageView.contentTintColor = accentColor
        directionImageView.imageScaling = .scaleProportionallyDown
        directionImageView.translatesAutoresizingMaskIntoConstraints = false

        directionBadgeView.addSubview(directionImageView)
        NSLayoutConstraint.activate([
            directionImageView.centerXAnchor.constraint(equalTo: directionBadgeView.centerXAnchor),
            directionImageView.centerYAnchor.constraint(equalTo: directionBadgeView.centerYAnchor),
            directionImageView.widthAnchor.constraint(equalToConstant: 16),
            directionImageView.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    private func configureLabels() {
        symbolLabel.font = AlertHUDMetrics.symbolFont
        symbolLabel.textColor = .labelColor
        symbolLabel.lineBreakMode = .byTruncatingTail
        symbolLabel.translatesAutoresizingMaskIntoConstraints = false
        symbolLabel.setContentHuggingPriority(.required, for: .horizontal)
        symbolLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        priceLabel.font = AlertHUDMetrics.priceFont
        priceLabel.textColor = .labelColor
        priceLabel.lineBreakMode = .byTruncatingHead
        priceLabel.translatesAutoresizingMaskIntoConstraints = false
        priceLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        titleLabel.font = AlertHUDMetrics.detailFont
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    private func configureContentGroup(in content: NSView) {
        let groupWidth = AlertHUDMetrics.contentGroupWidth(for: presentation)

        contentGroupView.translatesAutoresizingMaskIntoConstraints = false
        textBlockView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(contentGroupView)
        contentGroupView.addSubview(directionBadgeView)
        contentGroupView.addSubview(textBlockView)
        textBlockView.addSubview(symbolLabel)
        textBlockView.addSubview(priceLabel)
        textBlockView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            contentGroupView.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            contentGroupView.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            contentGroupView.widthAnchor.constraint(equalToConstant: groupWidth),
            contentGroupView.leadingAnchor.constraint(
                greaterThanOrEqualTo: content.leadingAnchor,
                constant: AlertHUDMetrics.horizontalPadding
            ),
            contentGroupView.trailingAnchor.constraint(
                lessThanOrEqualTo: content.trailingAnchor,
                constant: -AlertHUDMetrics.trailingPadding
            ),

            directionBadgeView.leadingAnchor.constraint(equalTo: contentGroupView.leadingAnchor),
            directionBadgeView.centerYAnchor.constraint(equalTo: contentGroupView.centerYAnchor),
            directionBadgeView.widthAnchor.constraint(equalToConstant: AlertHUDMetrics.badgeSize),
            directionBadgeView.heightAnchor.constraint(equalToConstant: AlertHUDMetrics.badgeSize),

            textBlockView.leadingAnchor.constraint(
                equalTo: directionBadgeView.trailingAnchor,
                constant: AlertHUDMetrics.badgeTextSpacing
            ),
            textBlockView.trailingAnchor.constraint(equalTo: contentGroupView.trailingAnchor),
            textBlockView.topAnchor.constraint(equalTo: contentGroupView.topAnchor),
            textBlockView.bottomAnchor.constraint(equalTo: contentGroupView.bottomAnchor),

            priceLabel.topAnchor.constraint(equalTo: textBlockView.topAnchor),
            symbolLabel.leadingAnchor.constraint(equalTo: textBlockView.leadingAnchor),
            symbolLabel.firstBaselineAnchor.constraint(equalTo: priceLabel.firstBaselineAnchor),
            priceLabel.leadingAnchor.constraint(
                equalTo: symbolLabel.trailingAnchor,
                constant: AlertHUDMetrics.primaryTextSpacing
            ),
            priceLabel.trailingAnchor.constraint(lessThanOrEqualTo: textBlockView.trailingAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: textBlockView.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: textBlockView.trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: priceLabel.bottomAnchor, constant: 1),
            titleLabel.bottomAnchor.constraint(equalTo: textBlockView.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize { resolvedContentSize }

    var visibleCardFrame: NSRect { cardView.frame }
    var textBlockFrame: NSRect { textBlockView.frame }
}

private final class AlertHUDCardHostView: NSView {
    var cornerRadius: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.008).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.32
        layer?.shadowRadius = 18
        layer?.shadowOffset = CGSize(width: 0, height: -6)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.shadowPath = CGPath(
            roundedRect: bounds,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        CATransaction.commit()
    }
}

private final class AlertHUDBackdropView: NSView {
    init(content: NSView, cornerRadius: CGFloat, tintColor: NSColor) {
        super.init(frame: .zero)

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.style = .regular
            glass.tintColor = tintColor
            glass.translatesAutoresizingMaskIntoConstraints = false
            addSubview(glass)
            pin(glass)

            // Keep controls in a normal AppKit view above the material. A
            // zero-sized NSGlassEffectView does not reliably resize a content
            // view assigned during initialization, which can make labels
            // disappear on the first presentation.
            content.translatesAutoresizingMaskIntoConstraints = false
            addSubview(content)
            pin(content)
        } else {
            let effect = NSVisualEffectView()
            effect.material = .hudWindow
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = cornerRadius
            effect.layer?.cornerCurve = .continuous
            effect.layer?.masksToBounds = true
            effect.translatesAutoresizingMaskIntoConstraints = false
            addSubview(effect)
            pin(effect)

            content.translatesAutoresizingMaskIntoConstraints = false
            effect.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
                content.topAnchor.constraint(equalTo: effect.topAnchor),
                content.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            ])
        }
    }

    private func pin(_ view: NSView) {
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class AlertHUDCardContentView: NSView {
    private let accentLayer = CAGradientLayer()

    init(accentColor: NSColor) {
        super.init(frame: .zero)
        wantsLayer = true
        accentLayer.colors = [
            accentColor.withAlphaComponent(0.045).cgColor,
            accentColor.withAlphaComponent(0.012).cgColor,
            NSColor.clear.cgColor,
        ]
        accentLayer.locations = [0, 0.38, 0.82]
        accentLayer.startPoint = CGPoint(x: 0, y: 0.5)
        accentLayer.endPoint = CGPoint(x: 1, y: 0.5)
        layer?.addSublayer(accentLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        accentLayer.frame = bounds
        CATransaction.commit()
    }
}

private final class AlertHUDEdgeView: NSView {
    private let gradientLayer = CAGradientLayer()
    private let strokeMask = CAShapeLayer()
    private let cornerRadius: CGFloat

    init(cornerRadius: CGFloat, accentColor: NSColor) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        wantsLayer = true
        gradientLayer.colors = [
            NSColor.white.withAlphaComponent(0.24).cgColor,
            NSColor.white.withAlphaComponent(0.06).cgColor,
            accentColor.withAlphaComponent(0.12).cgColor,
        ]
        gradientLayer.locations = [0, 0.58, 1]
        gradientLayer.startPoint = CGPoint(x: 0.08, y: 0.95)
        gradientLayer.endPoint = CGPoint(x: 0.95, y: 0.05)
        strokeMask.fillColor = NSColor.clear.cgColor
        strokeMask.strokeColor = NSColor.black.cgColor
        strokeMask.lineWidth = 1
        gradientLayer.mask = strokeMask
        layer?.addSublayer(gradientLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.frame = bounds
        strokeMask.frame = bounds
        strokeMask.path = CGPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            cornerWidth: cornerRadius - 0.5,
            cornerHeight: cornerRadius - 0.5,
            transform: nil
        )
        CATransaction.commit()
    }
}
