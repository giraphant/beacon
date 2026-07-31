import AppKit
import CoreGraphics

@MainActor
enum AlertHUDScreenResolver {
    /// Prefer the frontmost app's topmost normal window. Unlike the
    /// Accessibility API, CGWindowList gives us enough geometry for display
    /// selection without asking the user for another permission.
    static func preferredScreen() -> NSScreen? {
        let screens = NSScreen.screens
        if let windowFrame = frontmostWindowFrame(screens: screens),
           let bestFrame = bestScreenFrame(
               forWindowFrame: windowFrame,
               screenFrames: screens.map(\.frame)
           ),
           let screen = screens.first(where: { $0.frame == bestFrame }) {
            return screen
        }

        if let main = NSScreen.main {
            return main
        }

        let mouse = NSEvent.mouseLocation
        return screens.first(where: { $0.frame.contains(mouse) }) ?? screens.first
    }

    static func appKitWindowFrame(
        quartzBounds: CGRect,
        primaryScreenMaxY: CGFloat
    ) -> CGRect? {
        guard quartzBounds.origin.x.isFinite,
              quartzBounds.origin.y.isFinite,
              quartzBounds.width.isFinite,
              quartzBounds.height.isFinite,
              quartzBounds.width > 0,
              quartzBounds.height > 0 else {
            return nil
        }
        return CGRect(
            x: quartzBounds.minX,
            y: primaryScreenMaxY - quartzBounds.minY - quartzBounds.height,
            width: quartzBounds.width,
            height: quartzBounds.height
        )
    }

    static func bestScreenFrame(
        forWindowFrame windowFrame: CGRect,
        screenFrames: [CGRect]
    ) -> CGRect? {
        guard !windowFrame.isNull, !windowFrame.isEmpty else { return nil }

        var best: (frame: CGRect, area: CGFloat)?
        for frame in screenFrames {
            let intersection = windowFrame.intersection(frame)
            let area = intersection.isNull || intersection.isEmpty
                ? 0
                : intersection.width * intersection.height
            if area > (best?.area ?? 0) {
                best = (frame, area)
            }
        }
        if let best, best.area > 0 {
            return best.frame
        }

        let center = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        return screenFrames.first(where: { $0.contains(center) })
    }

    private static func frontmostWindowFrame(screens: [NSScreen]) -> CGRect? {
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.bundleIdentifier != Bundle.main.bundleIdentifier,
              let primaryMaxY = screens.first(where: { $0.frame.origin == .zero })?.frame.maxY
                ?? screens.first?.frame.maxY,
              let windowInfo = CGWindowListCopyWindowInfo(
                  [.optionOnScreenOnly, .excludeDesktopElements],
                  kCGNullWindowID
              ) as? [[String: Any]] else {
            return nil
        }

        for info in windowInfo {
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
                    == frontmost.processIdentifier,
                  (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let dictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let quartzBounds = CGRect(
                      dictionaryRepresentation: dictionary as CFDictionary
                  ),
                  quartzBounds.width >= 120,
                  quartzBounds.height >= 80,
                  let frame = appKitWindowFrame(
                      quartzBounds: quartzBounds,
                      primaryScreenMaxY: primaryMaxY
                  ) else {
                continue
            }
            return frame
        }
        return nil
    }
}
